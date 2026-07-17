# MCP SQL Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a read-only MCP server that connects to any number of SQL Server instances/databases, configured entirely through `config/sql-servers.json` + `.env` (no code changes to add a server), runnable first over stdio and later over HTTP for coworkers.

**Architecture:** Mirrors `MCP SAP/sap-leader-mcp`'s separation of concerns: `tool-registry.js` holds tool definitions and is shared by two transport entry points (`index.js` stdio, `http-server.js` HTTP). `server-manager.js` owns config loading, server resolution, a shared connection-pool cache keyed by `server+database`, and a **per-session** active-server map (keyed by `sessionId`) so concurrent HTTP callers never see each other's active server. A text-based read-only validator gates every `run_query`/`explain_query` call before it touches the network.

**Tech Stack:** Node.js (ESM, `"type": "module"`), `@modelcontextprotocol/sdk`, `mssql` (Tedious driver), `express` (HTTP transport only), Node's built-in `node:test` + `node:assert/strict` for unit tests (no new test dependency).

## Global Constraints

- Read-only, always: no INSERT/UPDATE/DELETE/MERGE/DROP/ALTER/TRUNCATE/EXEC/CREATE/GRANT/REVOKE/`SELECT ... INTO` may ever execute — enforced by `query-validator.js` on every `run_query` and `explain_query` call.
- `config/sql-servers.json` never contains a password — only `password_env` naming a `.env` variable. `.env` is gitignored.
- SQL Server Authentication only (no Windows Authentication) — matches the existing `DEVELOPER` login setup.
- Default `max_rows` = 1000, default `timeout_ms` = 30000, both sourced from `config/sql-servers.json` (`default_max_rows`, `default_query_timeout_ms`) and overridable per tool call.
- Built directly under `MCP SQL/` (flat — no nested project folder, unlike `MCP SAP/sap-leader-mcp`).
- `MCP SAP/sap-leader-mcp` is reference-only. Never modify files under `MCP SAP/`.
- Node.js >= 18 (required for the stable `node:test` runner).
- All new source files use ESM `import`/`export` syntax.

---

## File Structure

```
MCP SQL/
  .gitignore
  .env.example
  package.json
  config/
    sql-servers.json
  src/
    server-manager.js
    tool-registry.js
    utils/
      query-validator.js
      sql-client.js
    tools/
      server-tools.js
      query-tools.js
      schema-tools.js
  index.js
  http-server.js
  tests/
    fixtures/
      sql-servers.fixture.json
    query-validator.test.js
    sql-client.test.js
    server-manager.test.js
    tool-registry.test.js
```

---

### Task 1: Project scaffolding

**Files:**
- Create: `MCP SQL/package.json`
- Create: `MCP SQL/.gitignore`
- Create: `MCP SQL/.env.example`
- Create: `MCP SQL/config/sql-servers.json`

**Interfaces:**
- Produces: `config/sql-servers.json` shape consumed by `server-manager.js` in Task 4 — `{ default_server, default_query_timeout_ms, default_max_rows, servers: [{ name, host, port, environment, aliases, user, password_env, encrypt, trust_server_certificate, allowed_databases }] }`.

- [ ] **Step 1: Create `package.json`**

```json
{
  "name": "mcp-sql",
  "version": "1.0.0",
  "description": "MCP SQL Server connector — dynamic multi-server, multi-database, read-only access configured via config/sql-servers.json + .env",
  "type": "module",
  "main": "index.js",
  "engines": {
    "node": ">=18"
  },
  "scripts": {
    "start": "node index.js",
    "start:http": "node http-server.js",
    "test": "node --test tests/"
  },
  "keywords": [
    "mcp",
    "sql-server",
    "mssql",
    "claude-code"
  ],
  "author": "",
  "license": "MIT",
  "dependencies": {
    "@modelcontextprotocol/sdk": "^1.0.0",
    "mssql": "^10.0.1",
    "express": "^4.19.2"
  }
}
```

- [ ] **Step 2: Create `.gitignore`**

```
node_modules/
.env
*.log
```

- [ ] **Step 3: Create `.env.example`**

```
# Salin ke .env lalu isi nilainya — JANGAN commit .env ke git
SQL_PWD_DEV_224=ganti-dengan-password-asli
MCP_HTTP_TOKEN=ganti-dengan-token-rahasia-yang-panjang
MCP_HTTP_PORT=8092
```

- [ ] **Step 4: Create `config/sql-servers.json`**

```json
{
  "default_server": "dev-224",
  "default_query_timeout_ms": 30000,
  "default_max_rows": 1000,
  "servers": [
    {
      "name": "dev-224",
      "host": "192.168.1.224",
      "port": 1433,
      "environment": "development",
      "aliases": ["dev", "developer"],
      "user": "DEVELOPER",
      "password_env": "SQL_PWD_DEV_224",
      "encrypt": false,
      "trust_server_certificate": true,
      "allowed_databases": null
    }
  ]
}
```

- [ ] **Step 5: Install dependencies**

Run: `cd "MCP SQL" && npm install`
Expected: exits 0, creates `node_modules/` and `package-lock.json`, no `ERESOLVE`/peer-dependency errors printed.

- [ ] **Step 6: Verify the packages actually load under ESM**

Run:
```bash
cd "MCP SQL" && node -e "import('mssql').then(() => console.log('mssql OK')); import('@modelcontextprotocol/sdk/server/index.js').then(() => console.log('sdk OK')); import('express').then(() => console.log('express OK'));"
```
Expected output (order may vary): `mssql OK`, `sdk OK`, `express OK` — no import errors.

- [ ] **Step 7: Commit**

```bash
cd "MCP SQL" && git add package.json .gitignore .env.example config/sql-servers.json package-lock.json
git commit -m "chore: scaffold mcp-sql project (package.json, config, gitignore)"
```

---

### Task 2: Read-only query validator (TDD)

**Files:**
- Create: `MCP SQL/src/utils/query-validator.js`
- Test: `MCP SQL/tests/query-validator.test.js`

**Interfaces:**
- Produces: `validateReadOnlyQuery(rawSql: string) -> { ok: true } | { ok: false, reason: string }` — consumed by `query-tools.js` (Task 6) and `schema-tools.js`'s `explain_query` (Task 7).

- [ ] **Step 1: Write the failing tests**

Create `MCP SQL/tests/query-validator.test.js`:

```js
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
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd "MCP SQL" && node --test tests/query-validator.test.js`
Expected: FAIL — `Cannot find module '../src/utils/query-validator.js'` (file doesn't exist yet).

- [ ] **Step 3: Implement `src/utils/query-validator.js`**

```js
// query-validator.js
// Text-based read-only enforcement for run_query / explain_query.
// This is a defense-in-depth layer, not the sole guarantee — the SQL Server
// login used by this MCP should also be restricted to db_datareader.

function stripCommentsAndStrings(sqlText) {
  let result = '';
  let i = 0;
  const n = sqlText.length;
  while (i < n) {
    const ch = sqlText[i];
    const two = sqlText.slice(i, i + 2);

    if (ch === "'") {
      let j = i + 1;
      while (j < n) {
        if (sqlText[j] === "'" && sqlText[j + 1] === "'") {
          j += 2;
          continue;
        }
        if (sqlText[j] === "'") {
          j++;
          break;
        }
        j++;
      }
      result += ' STR ';
      i = j;
      continue;
    }

    if (two === '--') {
      let j = i + 2;
      while (j < n && sqlText[j] !== '\n') j++;
      i = j;
      continue;
    }

    if (two === '/*') {
      let j = i + 2;
      while (j < n && sqlText.slice(j, j + 2) !== '*/') j++;
      i = j + 2;
      continue;
    }

    result += ch;
    i++;
  }
  return result;
}

const FORBIDDEN_KEYWORDS = [
  'INSERT', 'UPDATE', 'DELETE', 'MERGE', 'DROP', 'ALTER',
  'TRUNCATE', 'EXEC', 'EXECUTE', 'INTO', 'GRANT', 'REVOKE', 'CREATE'
];

export function validateReadOnlyQuery(rawSql) {
  if (!rawSql || !rawSql.trim()) {
    return { ok: false, reason: 'Query kosong.' };
  }

  const cleaned = stripCommentsAndStrings(rawSql).trim();

  if (!/^(SELECT|WITH)\b/i.test(cleaned)) {
    return { ok: false, reason: 'Hanya statement SELECT atau WITH...SELECT yang diizinkan.' };
  }

  const withoutTrailingSemicolon = cleaned.replace(/;\s*$/, '');
  if (withoutTrailingSemicolon.includes(';')) {
    return { ok: false, reason: 'Multi-statement (dipisah ";") tidak diizinkan.' };
  }

  for (const kw of FORBIDDEN_KEYWORDS) {
    const re = new RegExp(`\\b${kw}\\b`, 'i');
    if (re.test(cleaned)) {
      return { ok: false, reason: `Kata kunci terlarang terdeteksi: ${kw}.` };
    }
  }

  return { ok: true };
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd "MCP SQL" && node --test tests/query-validator.test.js`
Expected: PASS — all 13 tests green, 0 failures.

- [ ] **Step 5: Commit**

```bash
cd "MCP SQL" && git add src/utils/query-validator.js tests/query-validator.test.js
git commit -m "feat: add read-only query validator with unit tests"
```

---

### Task 3: SQL client — row limiting (TDD) + connection wrapper

**Files:**
- Create: `MCP SQL/src/utils/sql-client.js`
- Test: `MCP SQL/tests/sql-client.test.js`

**Interfaces:**
- Consumes: nothing from earlier tasks.
- Produces:
  - `applyRowLimit(sqlText: string, limit: number) -> { sql: string, injected: boolean }` — consumed by `query-tools.js` (Task 6).
  - `createPool(server: object, password: string, database: string|null) -> Promise<mssql.ConnectionPool>` — consumed by `server-manager.js` (Task 4).
  - `executeQuery(pool, sqlText: string, { timeoutMs: number }) -> Promise<{ recordset: object[], elapsedMs: number }>` — consumed by `query-tools.js` (Task 6) and `server-tools.js` (Task 5).
  - `describeConnectionError(err: Error, server: object) -> string` — consumed by `server-manager.js`, `query-tools.js`, `server-tools.js`.

- [ ] **Step 1: Write the failing tests for `applyRowLimit` (pure function, no DB needed)**

Create `MCP SQL/tests/sql-client.test.js`:

```js
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
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd "MCP SQL" && node --test tests/sql-client.test.js`
Expected: FAIL — `Cannot find module '../src/utils/sql-client.js'`.

- [ ] **Step 3: Implement `src/utils/sql-client.js`**

```js
// sql-client.js
// Thin wrapper around the `mssql` driver: pool creation, query execution
// with an execution timeout, TOP-N row limiting, and error translation.

import sql from 'mssql';

export function applyRowLimit(sqlText, limit) {
  const match = sqlText.match(/^\s*SELECT\s+(DISTINCT\s+)?(?!TOP\b)/i);
  if (!match) {
    return { sql: sqlText, injected: false };
  }
  const insertPos = match[0].length;
  return {
    sql: sqlText.slice(0, insertPos) + `TOP (${limit}) ` + sqlText.slice(insertPos),
    injected: true
  };
}

export async function createPool(server, password, database) {
  const config = {
    server: server.host,
    port: server.port || 1433,
    user: server.user,
    password,
    database: database || undefined,
    connectionTimeout: 15000,
    requestTimeout: 30000,
    options: {
      encrypt: server.encrypt ?? true,
      trustServerCertificate: server.trust_server_certificate ?? false,
      enableArithAbort: true
    },
    pool: { max: 10, min: 0, idleTimeoutMillis: 30000 }
  };

  const pool = new sql.ConnectionPool(config);
  pool.on('error', (err) => {
    console.error(`[sql-client] Pool error for ${server.name}:`, err.message);
  });
  return pool.connect();
}

export async function executeQuery(pool, sqlText, { timeoutMs = 30000 } = {}) {
  const request = pool.request();
  request.timeout = timeoutMs;
  const startedAt = Date.now();
  const result = await request.query(sqlText);
  return {
    recordset: result.recordset || [],
    elapsedMs: Date.now() - startedAt
  };
}

export function describeConnectionError(err, server) {
  const msg = err.message || String(err);
  if (/login failed/i.test(msg)) {
    return `Login gagal untuk user "${server.user}" di server "${server.name}". Cek password di .env (var: ${server.password_env}).`;
  }
  if (/ETIMEOUT|ESOCKET|ECONNREFUSED|EHOSTUNREACH/i.test(msg)) {
    return `Tidak bisa menjangkau server "${server.name}" (${server.host}:${server.port || 1433}). Cek jaringan/VPN atau firewall.`;
  }
  return msg;
}

export { sql };
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd "MCP SQL" && node --test tests/sql-client.test.js`
Expected: PASS — all 5 tests green.

- [ ] **Step 5: Manual verification of `createPool` / `executeQuery` against a real server**

This part needs a live SQL Server and cannot be unit-tested offline. Defer the actual run to Task 11 (end-to-end verification), where `SQL_PWD_DEV_224` will be set in `.env`. For now, confirm the file has no syntax errors:

Run: `cd "MCP SQL" && node --check src/utils/sql-client.js`
Expected: no output, exit code 0.

- [ ] **Step 6: Commit**

```bash
cd "MCP SQL" && git add src/utils/sql-client.js tests/sql-client.test.js
git commit -m "feat: add sql-client wrapper with row-limit injection and unit tests"
```

---

### Task 4: Server manager — config, resolution, session state, pool cache

**Files:**
- Create: `MCP SQL/src/server-manager.js`
- Create: `MCP SQL/tests/fixtures/sql-servers.fixture.json`
- Test: `MCP SQL/tests/server-manager.test.js`

**Interfaces:**
- Consumes: `createPool` and `describeConnectionError` from `src/utils/sql-client.js` (Task 3).
- Produces (consumed by `server-tools.js`, `query-tools.js`, `schema-tools.js` in Tasks 5–7):
  - `export class ServerManager` — constructor `new ServerManager(configPath?: string)`.
  - `serverManager.getServers() -> object[]`
  - `serverManager.resolveServer(ref: string) -> object | null`
  - `serverManager.getActiveServerName(sessionId: string) -> string | null`
  - `serverManager.resolveTarget(sessionId: string, overrideServerRef?: string, overrideDatabase?: string) -> { ok: true, server: object, database: string|null } | { ok: false, error: string }`
  - `serverManager.setActiveServer(sessionId: string, ref: string) -> Promise<{ success: true, server, connected, connect_error, production } | { success: false, error }>`
  - `serverManager.getPool(serverName: string, database: string|null) -> Promise<mssql.ConnectionPool>`
  - `serverManager.isProduction(server: object) -> boolean`
  - `serverManager.config` — parsed `sql-servers.json`.
  - `export const serverManager` — singleton instance used by all tool files.

- [ ] **Step 1: Create the test fixture**

Create `MCP SQL/tests/fixtures/sql-servers.fixture.json`:

```json
{
  "default_server": "srv-a",
  "default_query_timeout_ms": 30000,
  "default_max_rows": 1000,
  "servers": [
    {
      "name": "srv-a",
      "host": "10.0.0.1",
      "port": 1433,
      "environment": "development",
      "aliases": ["dev", "a"],
      "user": "test_user",
      "password_env": "TEST_PWD_A",
      "encrypt": false,
      "trust_server_certificate": true,
      "allowed_databases": null
    },
    {
      "name": "srv-b",
      "host": "10.0.0.2",
      "port": 1433,
      "environment": "production",
      "aliases": ["prod", "b"],
      "user": "test_user2",
      "password_env": "TEST_PWD_B",
      "encrypt": false,
      "trust_server_certificate": true,
      "allowed_databases": ["ERP"]
    }
  ]
}
```

- [ ] **Step 2: Write the failing tests**

Create `MCP SQL/tests/server-manager.test.js`:

```js
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
```

- [ ] **Step 3: Run tests to verify they fail**

Run: `cd "MCP SQL" && node --test tests/server-manager.test.js`
Expected: FAIL — `Cannot find module '../src/server-manager.js'`.

- [ ] **Step 4: Implement `src/server-manager.js`**

```js
// server-manager.js
// Loads config/sql-servers.json, resolves server references, keeps a
// per-session record of which server is "active", and caches connection
// pools keyed by server+database so repeated queries reuse connections.

import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';
import { createPool, describeConnectionError } from './utils/sql-client.js';

const __dirname = dirname(fileURLToPath(import.meta.url));
const DEFAULT_CONFIG_PATH = join(__dirname, '..', 'config', 'sql-servers.json');

export class ServerManager {
  constructor(configPath = DEFAULT_CONFIG_PATH) {
    this.configPath = configPath;
    this.config = null;
    this.poolCache = new Map();
    this.sessionActiveServer = new Map();
    this.loadConfig();
  }

  loadConfig() {
    const raw = readFileSync(this.configPath, 'utf-8');
    this.config = JSON.parse(raw);
    return this.config;
  }

  getServers() {
    if (!this.config) this.loadConfig();
    return this.config.servers;
  }

  resolveServer(ref) {
    if (ref === undefined || ref === null) return null;
    const servers = this.getServers();
    const needle = String(ref).trim().toLowerCase();

    if (/^\d+$/.test(needle)) {
      const idx = parseInt(needle, 10) - 1;
      if (idx >= 0 && idx < servers.length) return servers[idx];
    }

    for (const s of servers) {
      if (s.name.toLowerCase() === needle) return s;
      if (s.host.toLowerCase() === needle) return s;
      if ((s.aliases || []).some((a) => a.toLowerCase() === needle)) return s;
    }

    return null;
  }

  getActiveServerName(sessionId) {
    return this.sessionActiveServer.get(sessionId) || null;
  }

  resolveTarget(sessionId, overrideServerRef, overrideDatabase) {
    let server;
    if (overrideServerRef) {
      server = this.resolveServer(overrideServerRef);
      if (!server) {
        return { ok: false, error: `Server "${overrideServerRef}" tidak ditemukan. Gunakan list_servers untuk melihat daftar server.` };
      }
    } else {
      const activeName = this.getActiveServerName(sessionId);
      if (!activeName) {
        return { ok: false, error: 'Belum ada server aktif. Gunakan set_active_server dulu, atau berikan parameter "server".' };
      }
      server = this.resolveServer(activeName);
    }
    return { ok: true, server, database: overrideDatabase || null };
  }

  async setActiveServer(sessionId, ref) {
    const server = this.resolveServer(ref);
    if (!server) {
      return { success: false, error: `Server "${ref}" tidak ditemukan. Gunakan list_servers untuk melihat daftar server.` };
    }

    let connected = false;
    let connectError = null;
    try {
      const pool = await this.getPool(server.name, null);
      connected = pool.connected;
    } catch (err) {
      connectError = describeConnectionError(err, server);
    }

    this.sessionActiveServer.set(sessionId, server.name);

    return {
      success: true,
      server,
      connected,
      connect_error: connectError,
      production: server.environment === 'production'
    };
  }

  async getPool(serverName, database) {
    const key = `${serverName}::${database || ''}`;
    if (this.poolCache.has(key)) {
      const cached = this.poolCache.get(key);
      if (cached.connected) return cached;
      this.poolCache.delete(key);
    }

    const server = this.getServers().find((s) => s.name === serverName);
    if (!server) {
      throw new Error(`Server "${serverName}" tidak ada di config.`);
    }

    const password = process.env[server.password_env];
    if (!password) {
      throw new Error(`Password untuk server "${serverName}" tidak ditemukan. Set env var "${server.password_env}" di .env.`);
    }

    const pool = await createPool(server, password, database);
    this.poolCache.set(key, pool);
    return pool;
  }

  isProduction(server) {
    return !!(server && server.environment === 'production');
  }
}

export const serverManager = new ServerManager();
export default serverManager;
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `cd "MCP SQL" && node --test tests/server-manager.test.js`
Expected: PASS — all 11 tests green.

- [ ] **Step 6: Commit**

```bash
cd "MCP SQL" && git add src/server-manager.js tests/server-manager.test.js tests/fixtures/sql-servers.fixture.json
git commit -m "feat: add server-manager with per-session active server and pool cache"
```

---

### Task 5: Server tools — `list_servers`, `set_active_server`, `list_databases`

**Files:**
- Create: `MCP SQL/src/tools/server-tools.js`

**Interfaces:**
- Consumes: `serverManager` from `src/server-manager.js` (Task 4), `describeConnectionError` from `src/utils/sql-client.js` (Task 3).
- Produces (consumed by `tool-registry.js` in Task 8):
  - `list_servers(args: object, ctx: { sessionId: string }) -> Promise<object>`
  - `set_active_server({ server_ref: string }, ctx) -> Promise<object>`
  - `list_databases(args: object, ctx) -> Promise<object>`

This task touches a real SQL Server (`set_active_server` opens a connection, `list_databases` runs a query), so it has no offline unit test — it is verified manually here against the real dev server, and again end-to-end in Task 11.

- [ ] **Step 1: Implement `src/tools/server-tools.js`**

```js
// server-tools.js
// list_servers, set_active_server, list_databases

import { serverManager } from '../server-manager.js';
import { describeConnectionError } from '../utils/sql-client.js';

export async function list_servers(_args, ctx) {
  const servers = serverManager.getServers();
  const activeName = serverManager.getActiveServerName(ctx.sessionId);

  return {
    active_server: activeName,
    count: servers.length,
    servers: servers.map((s, i) => ({
      number: i + 1,
      name: s.name,
      host: s.host,
      port: s.port || 1433,
      environment: s.environment,
      aliases: s.aliases || [],
      production_warning: s.environment === 'production',
      active: activeName === s.name
    }))
  };
}

export async function set_active_server({ server_ref }, ctx) {
  if (!server_ref) {
    return { success: false, error: 'Parameter "server_ref" wajib diisi.' };
  }

  const result = await serverManager.setActiveServer(ctx.sessionId, server_ref);
  if (!result.success) {
    return { success: false, error: result.error };
  }

  const response = {
    success: true,
    active_server: result.server.name,
    host: result.server.host,
    environment: result.server.environment,
    connected: result.connected
  };

  if (result.connect_error) {
    response.connect_error = result.connect_error;
  }
  if (result.production) {
    response.warning = '⚠️ PRODUCTION SERVER aktif (akses tetap read-only).';
  }

  return response;
}

export async function list_databases({ server }, ctx) {
  const target = serverManager.resolveTarget(ctx.sessionId, server, undefined);
  if (!target.ok) {
    return { error: target.error };
  }

  let pool;
  try {
    pool = await serverManager.getPool(target.server.name, null);
  } catch (err) {
    return { error: describeConnectionError(err, target.server) };
  }

  const result = await pool
    .request()
    .query('SELECT name AS database_name, state_desc AS state FROM sys.databases ORDER BY name');

  let databases = result.recordset;
  const allowed = target.server.allowed_databases;
  if (Array.isArray(allowed) && allowed.length > 0) {
    const allowedSet = new Set(allowed.map((d) => d.toLowerCase()));
    databases = databases.filter((d) => allowedSet.has(d.database_name.toLowerCase()));
  }

  return {
    server: target.server.name,
    count: databases.length,
    databases
  };
}
```

- [ ] **Step 2: Verify no syntax errors**

Run: `cd "MCP SQL" && node --check src/tools/server-tools.js`
Expected: no output, exit code 0.

- [ ] **Step 3: Manual verification against the real dev server**

This requires `.env` to contain a real `SQL_PWD_DEV_224` value (copy `.env.example` to `.env` and fill it in if not done yet).

Run:
```bash
cd "MCP SQL" && node -e "
import('./src/tools/server-tools.js').then(async (m) => {
  const ctx = { sessionId: 'manual-test' };
  console.log(JSON.stringify(await m.list_servers({}, ctx), null, 2));
  console.log(JSON.stringify(await m.set_active_server({ server_ref: 'dev' }, ctx), null, 2));
  console.log(JSON.stringify(await m.list_databases({}, ctx), null, 2));
});
"
```
Expected: `list_servers` shows `dev-224` with `active: false`; `set_active_server` returns `success: true, connected: true`; `list_databases` returns a non-empty `databases` array including at least `master`.

If `connected: false` with a login-failed message, double check `SQL_PWD_DEV_224` in `.env` matches the password shown in the SSMS connection dialog for `192.168.1.224` / `DEVELOPER`.

- [ ] **Step 4: Commit**

```bash
cd "MCP SQL" && git add src/tools/server-tools.js
git commit -m "feat: add server-tools (list_servers, set_active_server, list_databases)"
```

---

### Task 6: Query tool — `run_query`

**Files:**
- Create: `MCP SQL/src/tools/query-tools.js`

**Interfaces:**
- Consumes: `serverManager` (Task 4), `validateReadOnlyQuery` (Task 2), `applyRowLimit` / `executeQuery` / `describeConnectionError` (Task 3).
- Produces (consumed by `tool-registry.js` in Task 8): `run_query({ sql, server, database, max_rows, timeout_ms }, ctx) -> Promise<object>`.

- [ ] **Step 1: Implement `src/tools/query-tools.js`**

```js
// query-tools.js
// run_query — the only tool that executes arbitrary (validated) SQL.

import { serverManager } from '../server-manager.js';
import { validateReadOnlyQuery } from '../utils/query-validator.js';
import { applyRowLimit, executeQuery, describeConnectionError } from '../utils/sql-client.js';

export async function run_query({ sql, server, database, max_rows, timeout_ms }, ctx) {
  if (!sql || !sql.trim()) {
    return { error: 'Parameter "sql" wajib diisi.' };
  }

  const validation = validateReadOnlyQuery(sql);
  if (!validation.ok) {
    return { error: 'Query ditolak oleh validator read-only.', rejected_reason: validation.reason };
  }

  const target = serverManager.resolveTarget(ctx.sessionId, server, database);
  if (!target.ok) {
    return { error: target.error };
  }

  const maxRows = max_rows || serverManager.config.default_max_rows || 1000;
  const timeoutMs = timeout_ms || serverManager.config.default_query_timeout_ms || 30000;

  let pool;
  try {
    pool = await serverManager.getPool(target.server.name, target.database);
  } catch (err) {
    return { error: describeConnectionError(err, target.server) };
  }

  const trimmedSql = sql.trim();
  const { sql: limitedSql, injected } = applyRowLimit(trimmedSql, maxRows + 1);
  const queryToRun = injected ? limitedSql : trimmedSql;

  let result;
  try {
    result = await executeQuery(pool, queryToRun, { timeoutMs });
  } catch (err) {
    if (/timeout/i.test(err.message || '')) {
      return {
        error: `Query timeout setelah ${timeoutMs}ms.`,
        suggestion: 'Tambahkan filter WHERE atau naikkan timeout_ms.'
      };
    }
    return { error: err.message };
  }

  let rows = result.recordset;
  let truncated = false;
  if (rows.length > maxRows) {
    rows = rows.slice(0, maxRows);
    truncated = true;
  }

  const out = {
    server: target.server.name,
    database: target.database || '(default)',
    row_count: rows.length,
    columns: rows.length > 0 ? Object.keys(rows[0]) : [],
    truncated,
    elapsed_ms: result.elapsedMs,
    rows
  };

  if (serverManager.isProduction(target.server)) {
    out.production_warning = '⚠️ Response dari PRODUCTION server.';
  }

  return out;
}
```

- [ ] **Step 2: Verify no syntax errors**

Run: `cd "MCP SQL" && node --check src/tools/query-tools.js`
Expected: no output, exit code 0.

- [ ] **Step 3: Manual verification against the real dev server**

```bash
cd "MCP SQL" && node -e "
import('./src/tools/query-tools.js').then(async (m) => {
  import('./src/server-manager.js').then(async (sm) => {
    const ctx = { sessionId: 'manual-test' };
    await sm.serverManager.setActiveServer(ctx.sessionId, 'dev');
    console.log('-- valid query --');
    console.log(JSON.stringify(await m.run_query({ sql: 'SELECT name FROM sys.tables', max_rows: 3 }, ctx), null, 2));
    console.log('-- rejected query --');
    console.log(JSON.stringify(await m.run_query({ sql: 'DELETE FROM sys.tables' }, ctx), null, 2));
  });
});
"
```
Expected: the first call returns `row_count` <= 3, `truncated` reflecting whether the table has more than 3 tables, and real table names; the second call returns `{ error: "Query ditolak oleh validator read-only.", rejected_reason: "..." }` without ever touching the database.

- [ ] **Step 4: Commit**

```bash
cd "MCP SQL" && git add src/tools/query-tools.js
git commit -m "feat: add run_query tool with row limiting and timeout handling"
```

---

### Task 7: Schema tools — exploration & introspection

**Files:**
- Create: `MCP SQL/src/tools/schema-tools.js`

**Interfaces:**
- Consumes: `serverManager` (Task 4), `validateReadOnlyQuery` (Task 2), `sql` (named export from `src/utils/sql-client.js`, Task 3).
- Produces (consumed by `tool-registry.js` in Task 8):
  - `list_tables({ schema, server, database }, ctx) -> Promise<object>`
  - `describe_table({ table, server, database }, ctx) -> Promise<object>`
  - `search_objects({ pattern, type, server, database }, ctx) -> Promise<object>`
  - `get_object_definition({ object_name, server, database }, ctx) -> Promise<object>`
  - `explain_query({ sql, server, database }, ctx) -> Promise<object>`

- [ ] **Step 1: Implement `src/tools/schema-tools.js`**

```js
// schema-tools.js
// list_tables, describe_table, search_objects, get_object_definition, explain_query

import { serverManager } from '../server-manager.js';
import { validateReadOnlyQuery } from '../utils/query-validator.js';
import { sql } from '../utils/sql-client.js';

function splitSchemaAndName(name) {
  const parts = name.split('.');
  if (parts.length === 2) return { schema: parts[0], name: parts[1] };
  return { schema: 'dbo', name };
}

async function connect(ctx, server, database) {
  const target = serverManager.resolveTarget(ctx.sessionId, server, database);
  if (!target.ok) return { ok: false, error: target.error };
  try {
    const pool = await serverManager.getPool(target.server.name, target.database);
    return { ok: true, pool, target };
  } catch (err) {
    return { ok: false, error: err.message };
  }
}

export async function list_tables({ schema, server, database }, ctx) {
  const conn = await connect(ctx, server, database);
  if (!conn.ok) return { error: conn.error };

  const request = conn.pool.request();
  request.input('schema', sql.NVarChar, schema || null);
  const result = await request.query(`
    SELECT
      t.TABLE_SCHEMA AS schema_name,
      t.TABLE_NAME AS table_name,
      t.TABLE_TYPE AS table_type,
      ISNULL(p.row_count, 0) AS estimated_rows
    FROM INFORMATION_SCHEMA.TABLES t
    LEFT JOIN (
      SELECT
        SCHEMA_NAME(o.schema_id) AS schema_name,
        o.name AS table_name,
        SUM(ps.row_count) AS row_count
      FROM sys.dm_db_partition_stats ps
      JOIN sys.objects o ON ps.object_id = o.object_id
      WHERE ps.index_id IN (0, 1)
      GROUP BY SCHEMA_NAME(o.schema_id), o.name
    ) p ON p.schema_name = t.TABLE_SCHEMA AND p.table_name = t.TABLE_NAME
    WHERE (@schema IS NULL OR t.TABLE_SCHEMA = @schema)
    ORDER BY t.TABLE_SCHEMA, t.TABLE_NAME
  `);

  return {
    server: conn.target.server.name,
    database: conn.target.database || '(default)',
    count: result.recordset.length,
    tables: result.recordset
  };
}

export async function describe_table({ table, server, database }, ctx) {
  if (!table) return { error: 'Parameter "table" wajib diisi.' };
  const conn = await connect(ctx, server, database);
  if (!conn.ok) return { error: conn.error };

  const { schema, name } = splitSchemaAndName(table);
  const fullName = `${schema}.${name}`;

  const columnsResult = await conn.pool.request()
    .input('schema', sql.NVarChar, schema)
    .input('table', sql.NVarChar, name)
    .query(`
      SELECT COLUMN_NAME AS column_name, DATA_TYPE AS data_type,
             CHARACTER_MAXIMUM_LENGTH AS max_length, IS_NULLABLE AS is_nullable,
             COLUMN_DEFAULT AS default_value
      FROM INFORMATION_SCHEMA.COLUMNS
      WHERE TABLE_SCHEMA = @schema AND TABLE_NAME = @table
      ORDER BY ORDINAL_POSITION
    `);

  if (columnsResult.recordset.length === 0) {
    return { error: `Tabel "${fullName}" tidak ditemukan.` };
  }

  const pkResult = await conn.pool.request()
    .input('schema', sql.NVarChar, schema)
    .input('table', sql.NVarChar, name)
    .query(`
      SELECT ku.COLUMN_NAME AS column_name
      FROM INFORMATION_SCHEMA.TABLE_CONSTRAINTS tc
      JOIN INFORMATION_SCHEMA.KEY_COLUMN_USAGE ku ON tc.CONSTRAINT_NAME = ku.CONSTRAINT_NAME
      WHERE tc.CONSTRAINT_TYPE = 'PRIMARY KEY' AND tc.TABLE_SCHEMA = @schema AND tc.TABLE_NAME = @table
    `);

  const fkResult = await conn.pool.request()
    .input('schema', sql.NVarChar, schema)
    .input('table', sql.NVarChar, name)
    .query(`
      SELECT
        fk.name AS constraint_name,
        COL_NAME(fkc.parent_object_id, fkc.parent_column_id) AS column_name,
        OBJECT_SCHEMA_NAME(fkc.referenced_object_id) AS referenced_schema,
        OBJECT_NAME(fkc.referenced_object_id) AS referenced_table,
        COL_NAME(fkc.referenced_object_id, fkc.referenced_column_id) AS referenced_column
      FROM sys.foreign_keys fk
      JOIN sys.foreign_key_columns fkc ON fk.object_id = fkc.constraint_object_id
      WHERE OBJECT_SCHEMA_NAME(fk.parent_object_id) = @schema AND OBJECT_NAME(fk.parent_object_id) = @table
    `);

  const indexResult = await conn.pool.request()
    .input('full_name', sql.NVarChar, fullName)
    .query(`
      SELECT i.name AS index_name, i.is_unique, i.is_primary_key,
             STRING_AGG(c.name, ', ') WITHIN GROUP (ORDER BY ic.key_ordinal) AS columns
      FROM sys.indexes i
      JOIN sys.index_columns ic ON i.object_id = ic.object_id AND i.index_id = ic.index_id
      JOIN sys.columns c ON ic.object_id = c.object_id AND ic.column_id = c.column_id
      WHERE i.object_id = OBJECT_ID(@full_name)
      GROUP BY i.name, i.is_unique, i.is_primary_key
    `);

  return {
    server: conn.target.server.name,
    database: conn.target.database || '(default)',
    table: fullName,
    columns: columnsResult.recordset,
    primary_key: pkResult.recordset.map((r) => r.column_name),
    foreign_keys: fkResult.recordset,
    indexes: indexResult.recordset
  };
}

export async function search_objects({ pattern, type, server, database }, ctx) {
  if (!pattern) return { error: 'Parameter "pattern" wajib diisi (T-SQL LIKE, gunakan % sebagai wildcard).' };
  const conn = await connect(ctx, server, database);
  if (!conn.ok) return { error: conn.error };

  const result = await conn.pool.request()
    .input('pattern', sql.NVarChar, pattern)
    .input('type', sql.NVarChar, type || null)
    .query(`
      SELECT o.name AS object_name, SCHEMA_NAME(o.schema_id) AS schema_name, o.type_desc AS object_type
      FROM sys.objects o
      WHERE o.name LIKE @pattern
        AND (@type IS NULL OR o.type_desc LIKE @type + '%')
        AND o.is_ms_shipped = 0
      ORDER BY o.type_desc, o.name
    `);

  return {
    server: conn.target.server.name,
    database: conn.target.database || '(default)',
    count: result.recordset.length,
    objects: result.recordset
  };
}

export async function get_object_definition({ object_name, server, database }, ctx) {
  if (!object_name) return { error: 'Parameter "object_name" wajib diisi.' };
  const conn = await connect(ctx, server, database);
  if (!conn.ok) return { error: conn.error };

  const result = await conn.pool.request()
    .input('object_name', sql.NVarChar, object_name)
    .query(`
      SELECT OBJECT_SCHEMA_NAME(m.object_id) AS schema_name, OBJECT_NAME(m.object_id) AS object_name, m.definition
      FROM sys.sql_modules m
      WHERE m.object_id = OBJECT_ID(@object_name)
    `);

  if (result.recordset.length === 0) {
    return { error: `Definisi untuk objek "${object_name}" tidak ditemukan (bukan view/procedure/function, atau tidak ada).` };
  }

  return {
    server: conn.target.server.name,
    database: conn.target.database || '(default)',
    ...result.recordset[0]
  };
}

export async function explain_query({ sql: sqlText, server, database }, ctx) {
  if (!sqlText || !sqlText.trim()) return { error: 'Parameter "sql" wajib diisi.' };

  const validation = validateReadOnlyQuery(sqlText);
  if (!validation.ok) {
    return { error: 'Query ditolak oleh validator read-only.', rejected_reason: validation.reason };
  }

  const conn = await connect(ctx, server, database);
  if (!conn.ok) return { error: conn.error };

  const transaction = new sql.Transaction(conn.pool);
  await transaction.begin();
  try {
    await new sql.Request(transaction).batch('SET SHOWPLAN_XML ON');
    const planResult = await new sql.Request(transaction).batch(sqlText.trim());
    await new sql.Request(transaction).batch('SET SHOWPLAN_XML OFF');
    await transaction.rollback();

    const xml = planResult.recordset && planResult.recordset[0]
      ? Object.values(planResult.recordset[0])[0]
      : null;

    return {
      server: conn.target.server.name,
      database: conn.target.database || '(default)',
      execution_plan_xml: xml
    };
  } catch (err) {
    await transaction.rollback().catch(() => {});
    if (/permission/i.test(err.message || '')) {
      return { error: `Login tidak punya izin SHOWPLAN di server "${conn.target.server.name}". Minta admin DB memberi GRANT SHOWPLAN.` };
    }
    return { error: err.message };
  }
}
```

- [ ] **Step 2: Verify no syntax errors**

Run: `cd "MCP SQL" && node --check src/tools/schema-tools.js`
Expected: no output, exit code 0.

- [ ] **Step 3: Manual verification against the real dev server**

```bash
cd "MCP SQL" && node -e "
import('./src/tools/schema-tools.js').then(async (schemaTools) => {
  import('./src/server-manager.js').then(async (sm) => {
    const ctx = { sessionId: 'manual-test' };
    await sm.serverManager.setActiveServer(ctx.sessionId, 'dev');
    const tables = await schemaTools.list_tables({}, ctx);
    console.log(JSON.stringify(tables, null, 2));
    if (tables.tables && tables.tables.length > 0) {
      const first = tables.tables[0];
      console.log(JSON.stringify(await schemaTools.describe_table({ table: \`\${first.schema_name}.\${first.table_name}\` }, ctx), null, 2));
    }
    console.log(JSON.stringify(await schemaTools.search_objects({ pattern: '%' }, ctx), null, 2));
  });
});
"
```
Expected: `list_tables` returns at least one table; `describe_table` returns non-empty `columns` for that table; `search_objects` returns a non-empty `objects` list. If the database has views/procedures, also spot-check `get_object_definition` and `explain_query` manually against one of them.

- [ ] **Step 4: Commit**

```bash
cd "MCP SQL" && git add src/tools/schema-tools.js
git commit -m "feat: add schema exploration tools (list_tables, describe_table, search_objects, get_object_definition, explain_query)"
```

---

### Task 8: Tool registry — assemble tools, thread session context

**Files:**
- Create: `MCP SQL/src/tool-registry.js`
- Test: `MCP SQL/tests/tool-registry.test.js`

**Interfaces:**
- Consumes: all tool functions from `server-tools.js` (Task 5), `query-tools.js` (Task 6), `schema-tools.js` (Task 7).
- Produces (consumed by `index.js` Task 9 and `http-server.js` Task 10):
  - `export const TOOLS: { name, description, inputSchema, handler }[]`
  - `export const HANDLERS: Record<string, Function>`
  - `export function registerToolHandlers(server, { CallToolRequestSchema, ListToolsRequestSchema }, ctx: { sessionId })`

- [ ] **Step 1: Write the failing test (uses a stub MCP server, no network)**

Create `MCP SQL/tests/tool-registry.test.js`:

```js
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { TOOLS, registerToolHandlers } from '../src/tool-registry.js';

const CallToolRequestSchema = Symbol('CallToolRequestSchema');
const ListToolsRequestSchema = Symbol('ListToolsRequestSchema');

function createStubServer() {
  const handlers = new Map();
  return {
    setRequestHandler(schema, fn) {
      handlers.set(schema, fn);
    },
    async callList() {
      return handlers.get(ListToolsRequestSchema)();
    },
    async callTool(name, args) {
      return handlers.get(CallToolRequestSchema)({ params: { name, arguments: args } });
    }
  };
}

test('TOOLS contains exactly the 9 expected tool names', () => {
  const names = TOOLS.map((t) => t.name).sort();
  assert.deepEqual(names, [
    'describe_table',
    'explain_query',
    'get_object_definition',
    'list_databases',
    'list_servers',
    'list_tables',
    'run_query',
    'search_objects',
    'set_active_server'
  ]);
});

test('ListTools handler returns name/description/inputSchema for every tool', async () => {
  const server = createStubServer();
  registerToolHandlers(server, { CallToolRequestSchema, ListToolsRequestSchema }, { sessionId: 'test' });
  const { tools } = await server.callList();
  assert.equal(tools.length, TOOLS.length);
  for (const t of tools) {
    assert.ok(t.name);
    assert.ok(t.description);
    assert.ok(t.inputSchema);
  }
});

test('CallTool handler returns an isError response for an unknown tool', async () => {
  const server = createStubServer();
  registerToolHandlers(server, { CallToolRequestSchema, ListToolsRequestSchema }, { sessionId: 'test' });
  const result = await server.callTool('does_not_exist', {});
  assert.equal(result.isError, true);
  const parsed = JSON.parse(result.content[0].text);
  assert.match(parsed.error, /Unknown tool/);
});

test('CallTool handler routes list_servers to its handler and injects ctx', async () => {
  const server = createStubServer();
  registerToolHandlers(server, { CallToolRequestSchema, ListToolsRequestSchema }, { sessionId: 'ctx-check' });
  const result = await server.callTool('list_servers', {});
  const parsed = JSON.parse(result.content[0].text);
  assert.ok('active_server' in parsed);
  assert.ok(Array.isArray(parsed.servers));
});
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd "MCP SQL" && node --test tests/tool-registry.test.js`
Expected: FAIL — `Cannot find module '../src/tool-registry.js'`.

- [ ] **Step 3: Implement `src/tool-registry.js`**

```js
// tool-registry.js — single source of tool definitions, shared by stdio
// (index.js) and HTTP (http-server.js) transports.

import * as serverTools from './tools/server-tools.js';
import * as queryTools from './tools/query-tools.js';
import * as schemaTools from './tools/schema-tools.js';

export const TOOLS = [
  {
    name: 'list_servers',
    description: 'Tampilkan semua SQL Server dari config/sql-servers.json beserta host, environment, alias, dan status aktif.',
    inputSchema: { type: 'object', properties: {} },
    handler: serverTools.list_servers
  },
  {
    name: 'set_active_server',
    description: 'Pilih/ganti server SQL Server aktif untuk sesi ini. Terima nama, nomor urut, alias, atau host/IP.',
    inputSchema: {
      type: 'object',
      properties: {
        server_ref: { type: 'string', description: 'Referensi server: nama, nomor, alias, atau IP.' }
      },
      required: ['server_ref']
    },
    handler: serverTools.set_active_server
  },
  {
    name: 'list_databases',
    description: 'Daftar database di server aktif (atau server override), dari sys.databases.',
    inputSchema: {
      type: 'object',
      properties: {
        server: { type: 'string', description: 'Override server (opsional).' }
      }
    },
    handler: serverTools.list_databases
  },
  {
    name: 'run_query',
    description: 'Jalankan query SELECT read-only. INSERT/UPDATE/DELETE/DDL/EXEC ditolak otomatis.',
    inputSchema: {
      type: 'object',
      properties: {
        sql: { type: 'string', description: 'Query SQL (SELECT atau WITH...SELECT).' },
        server: { type: 'string', description: 'Override server (opsional).' },
        database: { type: 'string', description: 'Override database (opsional).' },
        max_rows: { type: 'number', description: 'Maksimum baris dikembalikan (default 1000).' },
        timeout_ms: { type: 'number', description: 'Timeout eksekusi dalam ms (default 30000).' }
      },
      required: ['sql']
    },
    handler: queryTools.run_query
  },
  {
    name: 'list_tables',
    description: 'Daftar tabel & view di database aktif, dengan estimasi jumlah baris.',
    inputSchema: {
      type: 'object',
      properties: {
        schema: { type: 'string', description: 'Filter schema, mis. "dbo" (opsional).' },
        server: { type: 'string' },
        database: { type: 'string' }
      }
    },
    handler: schemaTools.list_tables
  },
  {
    name: 'describe_table',
    description: 'Kolom, tipe data, primary key, foreign key, dan index dari sebuah tabel.',
    inputSchema: {
      type: 'object',
      properties: {
        table: { type: 'string', description: 'Nama tabel, boleh diawali schema mis. "dbo.Orders".' },
        server: { type: 'string' },
        database: { type: 'string' }
      },
      required: ['table']
    },
    handler: schemaTools.describe_table
  },
  {
    name: 'search_objects',
    description: 'Cari tabel/view/stored procedure berdasarkan pattern nama (T-SQL LIKE, gunakan % sebagai wildcard).',
    inputSchema: {
      type: 'object',
      properties: {
        pattern: { type: 'string', description: "Pattern LIKE, mis. '%Order%'." },
        type: { type: 'string', description: 'Filter tipe objek, mis. "USER_TABLE", "SQL_STORED_PROCEDURE" (opsional).' },
        server: { type: 'string' },
        database: { type: 'string' }
      },
      required: ['pattern']
    },
    handler: schemaTools.search_objects
  },
  {
    name: 'get_object_definition',
    description: 'Ambil source T-SQL dari view, stored procedure, atau function.',
    inputSchema: {
      type: 'object',
      properties: {
        object_name: { type: 'string', description: 'Nama objek, boleh diawali schema.' },
        server: { type: 'string' },
        database: { type: 'string' }
      },
      required: ['object_name']
    },
    handler: schemaTools.get_object_definition
  },
  {
    name: 'explain_query',
    description: 'Tampilkan estimated execution plan (XML) dari sebuah query SELECT, tanpa mengeksekusinya.',
    inputSchema: {
      type: 'object',
      properties: {
        sql: { type: 'string', description: 'Query SELECT yang ingin dianalisa.' },
        server: { type: 'string' },
        database: { type: 'string' }
      },
      required: ['sql']
    },
    handler: schemaTools.explain_query
  }
];

export const HANDLERS = Object.fromEntries(TOOLS.map((t) => [t.name, t.handler]));

export function registerToolHandlers(server, { CallToolRequestSchema, ListToolsRequestSchema }, ctx) {
  server.setRequestHandler(ListToolsRequestSchema, async () => ({
    tools: TOOLS.map(({ name, description, inputSchema }) => ({ name, description, inputSchema }))
  }));

  server.setRequestHandler(CallToolRequestSchema, async (request) => {
    const { name, arguments: args } = request.params;
    const handler = HANDLERS[name];
    if (!handler) {
      return {
        content: [{ type: 'text', text: JSON.stringify({ error: `Unknown tool: ${name}` }) }],
        isError: true
      };
    }
    try {
      const result = await handler(args || {}, ctx);
      return { content: [{ type: 'text', text: JSON.stringify(result, null, 2) }] };
    } catch (err) {
      return {
        content: [{ type: 'text', text: JSON.stringify({ error: err.message, tool: name }, null, 2) }],
        isError: true
      };
    }
  });
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd "MCP SQL" && node --test tests/tool-registry.test.js`
Expected: PASS — all 4 tests green. (`list_servers` reads `config/sql-servers.json` from Task 1, which requires no network access, so this test runs fully offline.)

- [ ] **Step 5: Run the full test suite together**

Run: `cd "MCP SQL" && npm test`
Expected: PASS — all tests across `query-validator.test.js`, `sql-client.test.js`, `server-manager.test.js`, `tool-registry.test.js` green, 0 failures.

- [ ] **Step 6: Commit**

```bash
cd "MCP SQL" && git add src/tool-registry.js tests/tool-registry.test.js
git commit -m "feat: add tool-registry assembling all 9 tools with session context"
```

---

### Task 9: stdio entry point

**Files:**
- Create: `MCP SQL/index.js`

**Interfaces:**
- Consumes: `registerToolHandlers` from `src/tool-registry.js` (Task 8).

- [ ] **Step 1: Implement `index.js`**

```js
#!/usr/bin/env node
// index.js — MCP SQL Server (stdio transport, untuk Claude Code lokal)

import { Server } from '@modelcontextprotocol/sdk/server/index.js';
import { StdioServerTransport } from '@modelcontextprotocol/sdk/server/stdio.js';
import { CallToolRequestSchema, ListToolsRequestSchema } from '@modelcontextprotocol/sdk/types.js';
import { registerToolHandlers } from './src/tool-registry.js';

const server = new Server(
  { name: 'mcp-sql', version: '1.0.0' },
  { capabilities: { tools: {} } }
);

const ctx = { sessionId: 'stdio' };
registerToolHandlers(server, { CallToolRequestSchema, ListToolsRequestSchema }, ctx);

async function main() {
  const transport = new StdioServerTransport();
  await server.connect(transport);
  console.error('MCP SQL Server running on stdio.');
}

main().catch((err) => {
  console.error('Fatal error starting MCP SQL Server:', err);
  process.exit(1);
});
```

- [ ] **Step 2: Smoke-test the stdio server starts and exits cleanly**

Run (bash):
```bash
cd "MCP SQL" && timeout 3 node index.js 2>&1 | head -n 1 || true
```
Expected: prints `MCP SQL Server running on stdio.` (the process then waits for stdio input; `timeout 3` kills it after 3 seconds, which is expected and not a failure).

If `timeout` isn't available (Windows without Git Bash), use PowerShell instead:
```powershell
cd "MCP SQL"; $p = Start-Process node -ArgumentList "index.js" -PassThru -RedirectStandardError "stderr.log" -NoNewWindow; Start-Sleep -Seconds 2; Stop-Process -Id $p.Id -Force; Get-Content stderr.log; Remove-Item stderr.log
```
Expected: `stderr.log` contains `MCP SQL Server running on stdio.`

- [ ] **Step 3: Commit**

```bash
cd "MCP SQL" && git add index.js
git commit -m "feat: add stdio entry point"
```

---

### Task 10: HTTP entry point

**Files:**
- Create: `MCP SQL/http-server.js`

**Interfaces:**
- Consumes: `registerToolHandlers` from `src/tool-registry.js` (Task 8).

Each HTTP request builds a fresh `Server` + `StreamableHTTPServerTransport` (stateless, matching `sap-leader-mcp`'s pattern), but the **Bearer token is used as the session id** passed into `registerToolHandlers`. This means `set_active_server` state in `server-manager.js` is keyed per-token: today one shared `MCP_HTTP_TOKEN` means all callers share one active-server state (same as today's single-user usage), but the seam is already in place so that issuing distinct tokens per coworker later (deferred work, see design spec) automatically isolates their active-server choices without touching this file again.

- [ ] **Step 1: Implement `http-server.js`**

```js
#!/usr/bin/env node
// http-server.js — MCP SQL Server via HTTP (Streamable HTTP transport)
// Untuk akses jarak jauh dalam jaringan lokal/VPN. Wajib Bearer token.
// Setiap request membuat instance Server + transport baru (stateless);
// Bearer token dipakai sebagai sessionId agar active-server tetap
// terpisah per token begitu tiap coworker punya token sendiri.

import express from 'express';
import { Server } from '@modelcontextprotocol/sdk/server/index.js';
import { StreamableHTTPServerTransport } from '@modelcontextprotocol/sdk/server/streamableHttp.js';
import { CallToolRequestSchema, ListToolsRequestSchema } from '@modelcontextprotocol/sdk/types.js';
import { registerToolHandlers } from './src/tool-registry.js';

const PORT = process.env.MCP_HTTP_PORT || 8092;
const HOST = process.env.MCP_HTTP_HOST || '0.0.0.0';
const AUTH_TOKEN = process.env.MCP_HTTP_TOKEN || 'change-me-token';

const app = express();
app.use(express.json());

function requireAuth(req, res, next) {
  const header = req.headers['authorization'] || '';
  const token = header.startsWith('Bearer ') ? header.slice(7) : null;
  if (!token || token !== AUTH_TOKEN) {
    return res.status(401).json({
      jsonrpc: '2.0',
      error: { code: -32001, message: 'Unauthorized: missing or invalid Bearer token' },
      id: null
    });
  }
  req.mcpSessionId = token;
  next();
}

function buildServer(sessionId) {
  const server = new Server({ name: 'mcp-sql', version: '1.0.0' }, { capabilities: { tools: {} } });
  registerToolHandlers(server, { CallToolRequestSchema, ListToolsRequestSchema }, { sessionId });
  return server;
}

app.get('/health', (req, res) => res.json({ status: 'ok', server: 'mcp-sql', transport: 'http' }));

app.post('/mcp', requireAuth, async (req, res) => {
  const server = buildServer(req.mcpSessionId);
  const transport = new StreamableHTTPServerTransport({
    sessionIdGenerator: undefined,
    enableJsonResponse: true
  });

  res.on('close', () => {
    transport.close();
    server.close();
  });

  try {
    await server.connect(transport);
    await transport.handleRequest(req, res, req.body);
  } catch (err) {
    if (!res.headersSent) {
      res.status(500).json({
        jsonrpc: '2.0',
        error: { code: -32000, message: err.message },
        id: req.body?.id ?? null
      });
    }
  }
});

app.listen(PORT, HOST, () => {
  console.error(`MCP SQL HTTP Server listening on http://${HOST}:${PORT}/mcp`);
  console.error('Auth: Bearer token required (set via MCP_HTTP_TOKEN env var).');
});
```

- [ ] **Step 2: Manual verification — health check and auth gate**

Ensure `.env` has `MCP_HTTP_TOKEN` set, then in one terminal:
```bash
cd "MCP SQL" && node --env-file=.env http-server.js
```
Expected stderr: `MCP SQL HTTP Server listening on http://0.0.0.0:8092/mcp`.

In a second terminal:
```bash
curl -s http://localhost:8092/health
```
Expected: `{"status":"ok","server":"mcp-sql","transport":"http"}`

```bash
curl -s -o /dev/null -w "%{http_code}\n" -X POST http://localhost:8092/mcp -H "Content-Type: application/json" -d '{"jsonrpc":"2.0","id":1,"method":"tools/list"}'
```
Expected: `401` (no Authorization header).

```bash
curl -s -X POST http://localhost:8092/mcp -H "Content-Type: application/json" -H "Authorization: Bearer $MCP_HTTP_TOKEN" -d '{"jsonrpc":"2.0","id":1,"method":"tools/list"}'
```
Expected: `200`-style JSON-RPC response listing all 9 tools.

Stop the server (`Ctrl+C` in the first terminal) once verified.

- [ ] **Step 3: Commit**

```bash
cd "MCP SQL" && git add http-server.js
git commit -m "feat: add HTTP entry point with Bearer auth and per-token session isolation"
```

---

### Task 11: End-to-end verification against the real dev server

**Files:** none created — this task only runs and confirms behavior.

This is the final gate from the design spec's Testing section: everything above was either unit-tested offline or spot-checked per file; this task exercises the whole stack together through the actual MCP stdio entry point against `192.168.1.224` (`DEVELOPER`), the way Claude will actually use it once wired into Claude Code.

- [ ] **Step 1: Confirm `.env` is filled in**

Run: `cd "MCP SQL" && cat .env`
Expected: `SQL_PWD_DEV_224=<real password>` is present (not the placeholder from `.env.example`).

- [ ] **Step 2: Run the automated test suite one more time**

Run: `cd "MCP SQL" && npm test`
Expected: PASS — every test from Tasks 2, 3, 4, 8 still green.

- [ ] **Step 3: Register the server with Claude Code and drive it manually**

Run: `claude mcp add mcp-sql -- node "C:\Users\Lenovo\Documents\Claude\MCP SQL\index.js"`
Expected: confirmation that `mcp-sql` was added.

In a Claude Code session, ask Claude to, in order: `list_servers`, `set_active_server` to `dev`, `list_databases`, `list_tables`, `describe_table` on one real table, `run_query` with a real small `SELECT ... WHERE ...`, then `run_query` with a `DELETE` statement to confirm it is rejected, and finally `search_objects` with a `%` pattern.

Expected: every call returns real data from `192.168.1.224`, the `DELETE` call is rejected with `rejected_reason` before touching the network, and no tool ever throws an unhandled/raw stack trace.

- [ ] **Step 4: Record the outcome**

If every check in Step 3 passes, the MCP SQL server is functionally complete for local (stdio) use. No commit needed for this task — it is a verification checkpoint, not a code change.

---

## Execution Handoff Note

After all 11 tasks are complete and Task 11's manual checklist passes, `MCP SQL` is ready for local use. HTTP multi-user auth (distinct tokens per coworker) and any write-access-per-database work are explicitly out of scope here (see the design spec's "Rencana Setelah Ini") and should be planned separately when the user is ready to share the server with coworkers.
