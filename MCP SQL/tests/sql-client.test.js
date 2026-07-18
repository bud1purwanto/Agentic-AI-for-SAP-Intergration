import { test } from 'node:test';
import assert from 'node:assert/strict';
import { applyRowLimit, describeConnectionError } from '../src/utils/sql-client.js';

test('injects TOP into a plain SELECT', () => {
  const result = applyRowLimit('SELECT * FROM Foo', 5);
  assert.equal(result.injected, true);
  assert.equal(result.sql, 'SELECT TOP (5) * FROM Foo');
});

test('injects TOP after DISTINCT', () => {
  const result = applyRowLimit('SELECT DISTINCT Name FROM Foo', 5);
  assert.equal(result.injected, true);
  assert.equal(result.sql, 'SELECT DISTINCT TOP (5) Name FROM Foo');
});

test('leaves an existing TOP clause untouched', () => {
  const result = applyRowLimit('SELECT TOP 10 * FROM Foo', 5);
  assert.equal(result.injected, false);
  assert.equal(result.sql, 'SELECT TOP 10 * FROM Foo');
});

test('leaves a CTE (WITH...SELECT) untouched', () => {
  const original = 'WITH cte AS (SELECT 1 AS x) SELECT * FROM cte';
  const result = applyRowLimit(original, 5);
  assert.equal(result.injected, false);
  assert.equal(result.sql, original);
});

test('is case-insensitive on SELECT/DISTINCT/TOP', () => {
  const result = applyRowLimit('select distinct Name from Foo', 5);
  assert.equal(result.injected, true);
  assert.equal(result.sql, 'select distinct TOP (5) Name from Foo');
});

test('leaves an existing TOP untouched even when combined with DISTINCT', () => {
  const original = 'SELECT DISTINCT TOP 5 Name FROM Foo';
  const result = applyRowLimit(original, 3);
  assert.equal(result.injected, false);
  assert.equal(result.sql, original);
});

const fakeServer = { name: 'dev-224', host: '192.168.1.224', port: 1433, user: 'DEVELOPER', password_env: 'SQL_PWD_DEV_224' };

test('describeConnectionError maps ELOGIN code to a login-failed message', () => {
  const out = describeConnectionError({ code: 'ELOGIN', message: 'Login failed for user' }, fakeServer);
  assert.match(out, /Login gagal/);
  assert.match(out, /SQL_PWD_DEV_224/);
});

test('describeConnectionError maps ETIMEOUT code (no substring in message) to unreachable message', () => {
  const out = describeConnectionError({ code: 'ETIMEOUT', message: 'Failed to connect to 192.168.1.224:1433 in 15000ms' }, fakeServer);
  assert.match(out, /Tidak bisa menjangkau/);
});

test('describeConnectionError falls back to raw message for unknown errors', () => {
  const out = describeConnectionError({ message: 'Some other SQL error' }, fakeServer);
  assert.equal(out, 'Some other SQL error');
});
