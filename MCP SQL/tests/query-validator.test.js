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

// The forbidden-keyword loop is generic, so a typo in FORBIDDEN_KEYWORDS would
// silently stop blocking a verb. Exercise every one of them.
const FORBIDDEN = [
  'INSERT', 'UPDATE', 'DELETE', 'MERGE', 'DROP', 'ALTER', 'TRUNCATE', 'CREATE',
  'INTO', 'BULK', 'EXEC', 'EXECUTE', 'GRANT', 'REVOKE', 'DENY', 'USE', 'SET',
  'DBCC', 'KILL', 'SHUTDOWN', 'RECONFIGURE', 'WAITFOR', 'BACKUP', 'RESTORE',
  'OPENROWSET', 'OPENQUERY', 'OPENDATASOURCE'
];

test('rejects every forbidden keyword, even smuggled after a leading SELECT', () => {
  for (const kw of FORBIDDEN) {
    const result = validateReadOnlyQuery(`SELECT 1\n${kw} something`);
    assert.equal(result.ok, false, `${kw} was not rejected`);
    assert.match(result.reason, new RegExp(kw, 'i'), `${kw} rejection did not name the keyword`);
  }
});

// T-SQL statements need no terminator, so a second statement on a new line is
// one legal batch that SQL Server executes in full — the ";" check alone does
// not catch this.
test('rejects a second statement separated only by a newline (no semicolon)', () => {
  const result = validateReadOnlyQuery('SELECT 1\nDBCC FREEPROCCACHE');
  assert.equal(result.ok, false);
});

test('rejects USE, which would change the pooled connection database context', () => {
  const result = validateReadOnlyQuery('SELECT 1\nUSE OtherDatabase');
  assert.equal(result.ok, false);
});

test('strips block comments so a keyword inside one does not reject a valid query', () => {
  const result = validateReadOnlyQuery('SELECT 1 /* we should DELETE this table someday */ FROM Foo');
  assert.equal(result.ok, true);
});

test('still allows ordinary SELECTs containing keyword-like substrings', () => {
  for (const q of [
    'SELECT * FROM Orders ORDER BY id OFFSET 10 ROWS',
    'SELECT CreatedBy, Inserted FROM Houses',
    'SELECT SettingValue FROM UserSettings'
  ]) {
    assert.equal(validateReadOnlyQuery(q).ok, true, `false positive on: ${q}`);
  }
});
