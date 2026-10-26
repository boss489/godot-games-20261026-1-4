'use strict';
const { UpdateCommand, QueryCommand } = require('@aws-sdk/lib-dynamodb');

function validateBoard(board) {
  if (typeof board !== 'string' || !/^(?:stage-(?:0[1-9]|1[0-9]|2[0-4])|survival)$/.test(board)) {
    throw new Error('Invalid board');
  }
  return board;
}

function validateSubmission(body) {
  if (body === null || typeof body !== 'object' || Array.isArray(body)) throw new Error('Invalid body');
  if (Object.keys(body).sort().join(',') !== 'board,nickname,score') throw new Error('Invalid fields');
  const { nickname, board, score } = body;
  if (typeof nickname !== 'string' || !/^[\p{Script=Hangul}A-Za-z0-9_ -]{2,16}$/u.test(nickname) || nickname.trim() !== nickname) {
    throw new Error('Invalid nickname');
  }
  validateBoard(board);
  if (!Number.isInteger(score) || score < 0 || score > 1000000000) throw new Error('Invalid score');
  return { nickname, nameKey: nickname.toLowerCase(), board, score };
}

function response(statusCode, value) {
  return { statusCode, headers: { 'content-type': 'application/json; charset=utf-8' }, body: JSON.stringify(value) };
}

function createHandler(client, tableName) {
  return async function handler(event) {
    try {
    const method = event?.requestContext?.http?.method;
    if (method !== 'GET' && method !== 'POST') return response(405, { error: 'Method not allowed' });
    if (method === 'GET') {
      if (Object.keys(event.queryStringParameters || {}).join(',') !== 'board') throw new Error('Invalid query');
      const board = validateBoard(event.queryStringParameters?.board);
      const items = [];
      let cursor;
      do {
        const page = await client.send(new QueryCommand({
          TableName: tableName,
          KeyConditionExpression: '#board = :board',
          ExpressionAttributeNames: { '#board': 'board', '#nickname': 'nickname', '#score': 'score' },
          ExpressionAttributeValues: { ':board': board },
          ProjectionExpression: '#nickname, #score',
          ExclusiveStartKey: cursor
        }));
        items.push(...(page.Items || []));
        cursor = page.LastEvaluatedKey;
      } while (cursor);
      items.sort((a, b) => b.score - a.score || a.nickname.toLowerCase().localeCompare(b.nickname.toLowerCase()));
      return response(200, { entries: items.slice(0, 10).map(item => ({ nickname: item.nickname, score: item.score })) });
    }
    if (event.isBase64Encoded || typeof event.body !== 'string' || Buffer.byteLength(event.body, 'utf8') > 4096) throw new Error('Invalid body');
    const { nickname, nameKey, board, score } = validateSubmission(JSON.parse(event.body));
    try {
      await client.send(new UpdateCommand({
        TableName: tableName,
        Key: { board, nameKey },
        UpdateExpression: 'SET #nickname = :nickname, #score = :score',
        ConditionExpression: 'attribute_not_exists(#score) OR #score < :score',
        ExpressionAttributeNames: { '#nickname': 'nickname', '#score': 'score' },
        ExpressionAttributeValues: { ':nickname': nickname, ':score': score },
        ReturnValues: 'ALL_NEW'
      }));
      return response(200, { updated: true });
    } catch (error) {
      if (error.name !== 'ConditionalCheckFailedException') throw error;
      return response(200, { updated: false });
    }
    } catch (error) {
      if (error instanceof SyntaxError || /^Invalid /.test(error.message)) return response(400, { error: 'Invalid request' });
      console.error('Leaderboard request failed:', error);
      return response(500, { error: 'Internal error' });
    }
  };
}

module.exports = { validateBoard, validateSubmission, createHandler };
