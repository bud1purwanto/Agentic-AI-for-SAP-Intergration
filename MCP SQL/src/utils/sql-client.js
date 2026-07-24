// sql-client.js
// Thin wrapper around the `mssql` driver: pool creation, query execution
// with an execution timeout, TOP-N row limiting, and error translation.

import sql from 'mssql';

// Splicing `TOP (n)` after the leading SELECT is only safe for a simple
// single-block query. Two shapes must be left alone:
//   - set operators: in `SELECT a FROM x UNION SELECT a FROM y`, TOP binds to
//     the FIRST arm only, so injecting silently returns a different result set
//     than the user asked for — worse than returning too many rows.
//   - OFFSET/FETCH paging: T-SQL rejects TOP in the same query as OFFSET.
// In both cases we skip injection; run_query still truncates client-side, so
// the row cap holds either way.
const ROW_LIMIT_UNSAFE = /\b(UNION|EXCEPT|INTERSECT)\b|\bOFFSET\b[\s\S]*\bFETCH\b/i;

export function applyRowLimit(sqlText, limit) {
  const match = sqlText.match(/^\s*SELECT\s+(DISTINCT\s+)?/i);
  if (!match) {
    return { sql: sqlText, injected: false };
  }
  if (ROW_LIMIT_UNSAFE.test(sqlText)) {
    return { sql: sqlText, injected: false };
  }
  const insertPos = match[0].length;
  const remainder = sqlText.slice(insertPos);
  if (/^TOP\b/i.test(remainder)) {
    return { sql: sqlText, injected: false };
  }
  return {
    sql: sqlText.slice(0, insertPos) + `TOP (${limit}) ` + remainder,
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
  const startedAt = Date.now();

  const queryPromise = request.query(sqlText);
  // If the timeout wins the race, queryPromise still eventually settles;
  // swallow its rejection so it never surfaces as an unhandled rejection.
  queryPromise.catch(() => {});

  let timer;
  const timeoutPromise = new Promise((_, reject) => {
    timer = setTimeout(() => {
      request.cancel();
      const err = new Error(`Query timeout after ${timeoutMs}ms`);
      err.code = 'ETIMEOUT';
      reject(err);
    }, timeoutMs);
  });

  try {
    const result = await Promise.race([queryPromise, timeoutPromise]);
    return {
      recordset: result.recordset || [],
      elapsedMs: Date.now() - startedAt
    };
  } finally {
    clearTimeout(timer);
  }
}

export function describeConnectionError(err, server) {
  const msg = err.message || String(err);
  const code = err.code || '';
  if (code === 'ELOGIN' || /login failed/i.test(msg)) {
    return `Login gagal untuk user "${server.user}" di server "${server.name}". Cek password di .env (var: ${server.password_env}).`;
  }
  const unreachableCodes = ['ETIMEOUT', 'ESOCKET', 'ECONNREFUSED', 'EHOSTUNREACH'];
  if (unreachableCodes.includes(code) || /ETIMEOUT|ESOCKET|ECONNREFUSED|EHOSTUNREACH|failed to connect/i.test(msg)) {
    return `Tidak bisa menjangkau server "${server.name}" (${server.host}:${server.port || 1433}). Cek jaringan/VPN atau firewall.`;
  }
  return msg;
}

export { sql };
