import { test } from 'node:test';
import assert from 'node:assert/strict';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';
import { ServerManager } from '../src/server-manager.js';

const __dirname = dirname(fileURLToPath(import.meta.url));
const FIXTURE_PATH = join(__dirname, 'fixtures', 'sql-servers.fixture.json');

function freshManager() {
  return new ServerManager(FIXTURE_PATH);
}

test('resolveServer matches by exact name', () => {
  const sm = freshManager();
  const s = sm.resolveServer('srv-a');
  assert.equal(s.host, '10.0.0.1');
});

test('resolveServer matches by 1-based index', () => {
  const sm = freshManager();
  const s = sm.resolveServer('2');
  assert.equal(s.name, 'srv-b');
});

test('resolveServer matches by alias', () => {
  const sm = freshManager();
  const s = sm.resolveServer('prod');
  assert.equal(s.name, 'srv-b');
});

test('resolveServer matches by host', () => {
  const sm = freshManager();
  const s = sm.resolveServer('10.0.0.1');
  assert.equal(s.name, 'srv-a');
});

test('resolveServer returns null for unknown reference', () => {
  const sm = freshManager();
  assert.equal(sm.resolveServer('nonexistent'), null);
});

test('resolveTarget fails when no override and no active server', () => {
  const sm = freshManager();
  const result = sm.resolveTarget('session-1', undefined, undefined);
  assert.equal(result.ok, false);
  assert.match(result.error, /set_active_server/i);
});

test('resolveTarget uses the session active server when set', () => {
  const sm = freshManager();
  sm.sessionActiveServer.set('session-1', 'srv-a');
  const result = sm.resolveTarget('session-1', undefined, undefined);
  assert.equal(result.ok, true);
  assert.equal(result.server.name, 'srv-a');
  assert.equal(result.database, null);
});

test('resolveTarget override server takes precedence over session active server', () => {
  const sm = freshManager();
  sm.sessionActiveServer.set('session-1', 'srv-a');
  const result = sm.resolveTarget('session-1', 'srv-b', 'ERP');
  assert.equal(result.ok, true);
  assert.equal(result.server.name, 'srv-b');
  assert.equal(result.database, 'ERP');
});

test('resolveTarget fails on an unknown override server', () => {
  const sm = freshManager();
  const result = sm.resolveTarget('session-1', 'does-not-exist', undefined);
  assert.equal(result.ok, false);
});

test('sessions are isolated from each other', () => {
  const sm = freshManager();
  sm.sessionActiveServer.set('session-1', 'srv-a');
  sm.sessionActiveServer.set('session-2', 'srv-b');
  assert.equal(sm.getActiveServerName('session-1'), 'srv-a');
  assert.equal(sm.getActiveServerName('session-2'), 'srv-b');
});

test('isProduction reflects the server environment field', () => {
  const sm = freshManager();
  assert.equal(sm.isProduction(sm.resolveServer('srv-a')), false);
  assert.equal(sm.isProduction(sm.resolveServer('srv-b')), true);
});
