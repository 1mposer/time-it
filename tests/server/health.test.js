const test = require('node:test');
const assert = require('node:assert/strict');
const supertest = require('supertest');
const app = require('../../src/server');

test('GET /health returns 200 with status ok and a timestamp', async () => {
  const res = await supertest(app).get('/health');
  assert.equal(res.status, 200);
  assert.equal(res.body.status, 'ok');
  assert.equal(typeof res.body.timestamp, 'string');
});
