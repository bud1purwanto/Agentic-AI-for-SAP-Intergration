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

  // STRING_AGG requires SQL Server 2017+ (compat level 140). The actual
  // servers this project targets run SQL Server 2016, so the column list is
  // built with the older FOR XML PATH concatenation trick (works since 2005)
  // instead.
  const indexResult = await conn.pool.request()
    .input('full_name', sql.NVarChar, fullName)
    .query(`
      SELECT i.name AS index_name, i.is_unique, i.is_primary_key,
             STUFF((
               SELECT ', ' + c2.name
               FROM sys.index_columns ic2
               JOIN sys.columns c2 ON ic2.object_id = c2.object_id AND ic2.column_id = c2.column_id
               WHERE ic2.object_id = i.object_id AND ic2.index_id = i.index_id
               ORDER BY ic2.key_ordinal
               FOR XML PATH('')
             ), 1, 2, '') AS columns
      FROM sys.indexes i
      WHERE i.object_id = OBJECT_ID(@full_name)
        AND i.index_id > 0
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

  // The transaction exists only to pin one pooled connection for all three
  // batches below — SHOWPLAN_XML compiles without executing, so there is
  // nothing for a rollback to undo.
  //
  // Ordering here is load-bearing: while SHOWPLAN_XML is ON, SQL Server
  // compiles but does NOT execute subsequent statements, and that includes
  // ROLLBACK. Turning SHOWPLAN off must therefore happen BEFORE the rollback
  // on every path, or the connection goes back into the shared pool with an
  // open transaction and SHOWPLAN still on — and the next caller (possibly a
  // different session) silently gets plan XML instead of their rows.
  const transaction = new sql.Transaction(conn.pool);
  await transaction.begin();

  let planResult;
  let planError;
  let showplanOn = false;
  let connectionSuspect = false;

  try {
    await new sql.Request(transaction).batch('SET SHOWPLAN_XML ON');
    showplanOn = true;
    planResult = await new sql.Request(transaction).batch(sqlText.trim());
  } catch (err) {
    planError = err;
  } finally {
    if (showplanOn) {
      try {
        await new sql.Request(transaction).batch('SET SHOWPLAN_XML OFF');
        showplanOn = false;
      } catch {
        // Could not restore the connection; it must not be reused.
        connectionSuspect = true;
      }
    }
    try {
      await transaction.rollback();
    } catch {
      connectionSuspect = true;
    }
  }

  if (connectionSuspect) {
    await serverManager.evictPool(conn.target.server.name, conn.target.database);
    return {
      error:
        `Gagal memulihkan state koneksi setelah explain_query di server "${conn.target.server.name}". ` +
        'Koneksi sudah dibuang agar tidak dipakai ulang. Coba lagi.'
    };
  }

  if (planError) {
    if (/permission/i.test(planError.message || '')) {
      return { error: `Login tidak punya izin SHOWPLAN di server "${conn.target.server.name}". Minta admin DB memberi GRANT SHOWPLAN.` };
    }
    return { error: planError.message };
  }

  const xml = planResult.recordset && planResult.recordset[0]
    ? Object.values(planResult.recordset[0])[0]
    : null;

  return {
    server: conn.target.server.name,
    database: conn.target.database || '(default)',
    execution_plan_xml: xml
  };
}
