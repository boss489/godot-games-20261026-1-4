'use strict';
const { DynamoDBClient } = require('@aws-sdk/client-dynamodb');
const { DynamoDBDocumentClient } = require('@aws-sdk/lib-dynamodb');
const { createHandler } = require('./api');

const client = DynamoDBDocumentClient.from(new DynamoDBClient({}));
exports.handler = createHandler(client, process.env.TABLE_NAME);
