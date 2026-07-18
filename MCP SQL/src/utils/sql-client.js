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
