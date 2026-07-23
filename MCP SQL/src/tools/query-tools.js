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
