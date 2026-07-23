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

  let result;
  try {
    result = await pool
      .request()
      .query('SELECT name AS database_name, state_desc AS state FROM sys.databases ORDER BY name');
  } catch (err) {
    return { error: describeConnectionError(err, target.server) };
  }

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
