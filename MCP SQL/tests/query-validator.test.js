import { test } from 'node:test';
import assert from 'node:assert/strict';
import { validateReadOnlyQuery } from '../src/utils/query-validator.js';

test('allows a plain SELECT', () => {
  const result = validateReadOnlyQuery('SELECT * FROM Customers');
  assert.equal(result.ok, true);
});

test('allows SELECT with WHERE and a string literal', () => {
  const result = validateReadOnlyQuery("SELECT id, name FROM dbo.Orders WHERE status = 'DELETE ME'");
  assert.equal(result.ok, true);
});

test('allows WITH...SELECT (CTE)', () => {
  const result = validateReadOnlyQuery('WITH cte AS (SELECT 1 AS x) SELECT * FROM cte');
  assert.equal(result.ok, true);
});

test('allows a trailing line comment containing a forbidden keyword', () => {
  const result = validateReadOnlyQuery('SELECT * FROM Foo -- remember to DELETE old rows later');
  assert.equal(result.ok, true);
});

test('rejects an empty query', () => {
  const result = validateReadOnlyQuery('   ');
  assert.equal(result.ok, false);
  assert.match(result.reason, /kosong/i);
});

test('rejects DELETE', () => {
  const result = validateReadOnlyQuery('DELETE FROM Customers');
  assert.equal(result.ok, false);
});

test('rejects INSERT', () => {
  const result = validateReadOnlyQuery('INSERT INTO Foo VALUES (1)');
  assert.equal(result.ok, false);
});

test('rejects UPDATE', () => {
  const result = validateReadOnlyQuery('UPDATE Foo SET x = 1');
  assert.equal(result.ok, false);
});

test('rejects DROP TABLE', () => {
  const result = validateReadOnlyQuery('DROP TABLE Foo');
  assert.equal(result.ok, false);
});

test('rejects SELECT ... INTO (creates a table)', () => {
  const result = validateReadOnlyQuery('SELECT * INTO NewTable FROM Foo');
  assert.equal(result.ok, false);
});

test('rejects EXEC', () => {
  const result = validateReadOnlyQuery('EXEC sp_who');
  assert.equal(result.ok, false);
});

test('rejects multi-statement batches', () => {
  const result = validateReadOnlyQuery('SELECT * FROM Foo; DELETE FROM Foo');
  assert.equal(result.ok, false);
  assert.match(result.reason, /multi-statement/i);
});

test('allows a single statement with a harmless trailing semicolon', () => {
  const result = validateReadOnlyQuery('SELECT * FROM Foo;');
  assert.equal(result.ok, true);
});
