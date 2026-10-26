'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const { validateBoard, validateSubmission, createHandler } = require('../src/api');

test('accepts only campaign stages 01 through 24 and survival', () => {
  for (let stage = 1; stage <= 24; stage++) assert.equal(validateBoard(`stage-${String(stage).padStart(2, '0')}`), `stage-${String(stage).padStart(2, '0')}`);
  assert.equal(validateBoard('survival'), 'survival');
  for (const board of ['stage-00', 'stage-25', 'stage-1', 'stage-001', 'STAGE-01', 'survival ', '../survival', null, 1]) {
    assert.throws(() => validateBoard(board), /board/);
  }
});

test('validates exact submission shape and safe nickname and integer score', () => {
  assert.deepEqual(validateSubmission({ nickname: 'Ace_2', board: 'stage-24', score: 100 }),
    { nickname: 'Ace_2', nameKey: 'ace_2', board: 'stage-24', score: 100 });
  assert.deepEqual(validateSubmission({ nickname: '신호왕', board: 'stage-01', score: 5 }),
    { nickname: '신호왕', nameKey: '신호왕', board: 'stage-01', score: 5 });
  for (const nickname of ['', 'a', ' Ace', 'Ace ', 'a'.repeat(21), '<script>', 'a\nb', 123]) {
    assert.throws(() => validateSubmission({ nickname, board: 'survival', score: 0 }), /nickname/);
  }
  for (const score of [-1, 1.2, '12', null, NaN, Infinity, 1000000001]) {
    assert.throws(() => validateSubmission({ nickname: 'Ace', board: 'survival', score }), /score/);
  }
  assert.throws(() => validateSubmission({ nickname: 'Ace', board: 'survival', score: 0, admin: true }), /fields/);
  assert.throws(() => validateSubmission(null), /body/);
  assert.throws(() => validateSubmission([]), /body/);
});

test('POST atomically stores best score with conditional DynamoDB update', async () => {
  const commands = [];
  const handler = createHandler({ send: async command => {
    commands.push(command);
    return { Attributes: { nickname: 'Ace', score: 42 } };
  } }, 'scores');
  const response = await handler({ requestContext: { http: { method: 'POST' } }, body: JSON.stringify({ nickname: 'Ace', board: 'stage-01', score: 42 }) });
  assert.equal(response.statusCode, 200);
  assert.deepEqual(JSON.parse(response.body), { updated: true });
  assert.equal(commands.length, 1);
  assert.equal(commands[0].constructor.name, 'UpdateCommand');
  assert.equal(commands[0].input.TableName, 'scores');
  assert.deepEqual(commands[0].input.Key, { board: 'stage-01', nameKey: 'ace' });
  assert.match(commands[0].input.ConditionExpression, /attribute_not_exists\(#score\).*#score < :score/);
  assert.equal(commands[0].input.ExpressionAttributeValues[':score'], 42);
});

test('GET reads every board page and ranks top ten by score then nickname', async () => {
  const commands = [];
  const handler = createHandler({ send: async command => {
    commands.push(command);
    if (commands.length === 1) return { Items: [{ nickname: 'Zed', score: 50 }], LastEvaluatedKey: { board: 'survival', nameKey: 'zed' } };
    return { Items: [
      { nickname: 'Amy', score: 50 },
      ...Array.from({ length: 12 }, (_, i) => ({ nickname: `P${String(i).padStart(2, '0')}`, score: i }))
    ] };
  } }, 'scores');
  const response = await handler({ requestContext: { http: { method: 'GET' } }, queryStringParameters: { board: 'survival' } });
  assert.equal(response.statusCode, 200);
  const data = JSON.parse(response.body);
  assert.deepEqual(Object.keys(data), ['entries']);
  assert.equal(data.entries.length, 10);
  assert.deepEqual(data.entries.slice(0, 3), [
    { nickname: 'Amy', score: 50 },
    { nickname: 'Zed', score: 50 },
    { nickname: 'P11', score: 11 }
  ]);
  assert.equal(commands[0].constructor.name, 'QueryCommand');
  assert.equal(commands[0].input.ProjectionExpression, '#nickname, #score');
  assert.deepEqual(commands[0].input.ExpressionAttributeNames, { '#board': 'board', '#nickname': 'nickname', '#score': 'score' });
  assert.deepEqual(commands[0].input.ExpressionAttributeValues, { ':board': 'survival' });
  assert.deepEqual(commands[1].input.ExclusiveStartKey, { board: 'survival', nameKey: 'zed' });
});

test('lower or tied POST reports unchanged without overwriting it', async () => {
  const commands = [];
  const handler = createHandler({ send: async command => {
    commands.push(command);
    if (command.constructor.name === 'UpdateCommand') {
      const error = new Error('Conditional check failed');
      error.name = 'ConditionalCheckFailedException';
      throw error;
    }
    return { Item: { nickname: 'ACE', score: 90 } };
  } }, 'scores');
  const result = await handler({ requestContext: { http: { method: 'POST' } }, body: JSON.stringify({ nickname: 'Ace', board: 'survival', score: 50 }) });
  assert.equal(result.statusCode, 200);
  assert.deepEqual(JSON.parse(result.body), { updated: false });
  assert.equal(commands.length, 1);
});

test('invalid requests return 400 or 405 without accessing DynamoDB', async () => {
  const handler = createHandler({ send: async () => { throw new Error('unexpected db access'); } }, 'scores');
  const cases = [
    [{ requestContext: { http: { method: 'GET' } }, queryStringParameters: { board: 'stage-25' } }, 400],
    [{ requestContext: { http: { method: 'GET' } }, queryStringParameters: { board: 'survival', other: 'x' } }, 400],
    [{ requestContext: { http: { method: 'POST' } }, body: '{broken' }, 400],
    [{ requestContext: { http: { method: 'POST' } }, body: JSON.stringify({ nickname: 'Ace', board: 'survival', score: '10' }) }, 400],
    [{ requestContext: { http: { method: 'POST' } }, body: '{}', isBase64Encoded: true }, 400],
    [{ requestContext: { http: { method: 'POST' } }, body: 'x'.repeat(4097) }, 400],
    [{ requestContext: { http: { method: 'DELETE' } } }, 405]
  ];
  for (const [event, status] of cases) {
    const result = await handler(event);
    assert.equal(result.statusCode, status, JSON.stringify(event).slice(0, 70));
    assert.ok(JSON.parse(result.body).error);
  }
});

test('unexpected database failures return 500 without leaking detail', async () => {
  const handler = createHandler({ send: async () => { throw new Error('internal database secret'); } }, 'scores');
  const response = await handler({ requestContext: { http: { method: 'GET' } }, queryStringParameters: { board: 'survival' } });
  assert.equal(response.statusCode, 500);
  assert.equal(JSON.stringify(response).includes('internal database secret'), false);
});

test('Lambda exports handler and SAM defines isolated table, URL CORS, and least-privilege access', () => {
  assert.equal(typeof require('../src/index').handler, 'function');
  const template = fs.readFileSync(path.join(__dirname, '..', 'template.yaml'), 'utf8');
  for (const fragment of ['AWS::DynamoDB::Table', 'AWS::Serverless::Function', 'nodejs24.x',
    'src/index.handler', 'AuthType: NONE', 'Cors:', 'AllowOrigins:', 'AllowMethods:',
    'dynamodb:Query', 'dynamodb:UpdateItem', 'TABLE_NAME', 'DeletionPolicy: Retain']) {
    assert.ok(template.includes(fragment), `missing ${fragment}`);
  }
});
