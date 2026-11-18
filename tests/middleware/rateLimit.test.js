const test = require('node:test');
const assert = require('node:assert/strict');

const {
  clientKeyFor, isPrivateAddress, rateLimitMode, readLimit,
} = require('../../src/middleware/rateLimit');

test('clientKeyFor keeps IPv4 as-is and unwraps IPv4-mapped IPv6', () => {
  assert.equal(clientKeyFor('203.0.113.7'), '203.0.113.7');
  assert.equal(clientKeyFor('::ffff:203.0.113.7'), '203.0.113.7');
  assert.notEqual(clientKeyFor('::ffff:203.0.113.7'), clientKeyFor('::ffff:203.0.113.8'));
});

test('clientKeyFor keys IPv6 on its /64, however the address is written', () => {
  const a = clientKeyFor('2001:db8:1:2::1');
  assert.equal(a, '2001:db8:1:2::/64');
  assert.equal(clientKeyFor('2001:0DB8:0001:0002:ffff:eeee:dddd:cccc'), a);
  assert.equal(clientKeyFor('2001:db8:1:2:0:0:0:9'), a);
  assert.notEqual(clientKeyFor('2001:db8:1:3::1'), a);
  assert.equal(clientKeyFor('::1'), '0:0:0:0::/64');
});

test('clientKeyFor returns null when there is no address', () => {
  assert.equal(clientKeyFor(undefined), null);
  assert.equal(clientKeyFor(''), null);
});

test('isPrivateAddress flags loopback, private, link-local and CGNAT ranges', () => {
  for (const ip of ['127.0.0.1', '10.1.2.3', '172.16.0.1', '172.31.255.255', '192.168.1.1',
    '100.64.0.1', '100.127.255.255', '169.254.1.1', '::1', '::ffff:10.0.0.1', 'fd12:3456::1', 'fe80::1', 'garbage']) {
    assert.equal(isPrivateAddress(ip), true, ip);
  }
  for (const ip of ['203.0.113.7', '8.8.8.8', '172.32.0.1', '100.128.0.1', '2001:db8::1', '::ffff:8.8.8.8']) {
    assert.equal(isPrivateAddress(ip), false, ip);
  }
});

test('rateLimitMode is observe unless explicitly enforce', () => {
  assert.equal(rateLimitMode({}), 'observe');
  assert.equal(rateLimitMode({ RATE_LIMIT_MODE: 'observe' }), 'observe');
  assert.equal(rateLimitMode({ RATE_LIMIT_MODE: 'typo' }), 'observe');
  assert.equal(rateLimitMode({ RATE_LIMIT_MODE: 'enforce' }), 'enforce');
  assert.equal(rateLimitMode({ RATE_LIMIT_MODE: ' Enforce ' }), 'enforce');
});

test('readLimit takes a positive integer from the environment, else the default', () => {
  assert.equal(readLimit('X', 60, {}), 60);
  assert.equal(readLimit('X', 60, { X: '25' }), 25);
  for (const bad of ['', 'abc', '0', '-5', '2.5']) assert.equal(readLimit('X', 60, { X: bad }), 60, bad);
});
