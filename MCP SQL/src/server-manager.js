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
