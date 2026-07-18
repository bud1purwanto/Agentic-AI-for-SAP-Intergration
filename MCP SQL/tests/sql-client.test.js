import { test } from 'node:test';
import assert from 'node:assert/strict';
import { applyRowLimit } from '../src/utils/sql-client.js';

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
