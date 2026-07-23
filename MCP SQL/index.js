#!/usr/bin/env node
// index.js — MCP SQL Server (stdio transport, untuk Claude Code lokal)

import { Server } from '@modelcontextprotocol/sdk/server/index.js';
import { StdioServerTransport } from '@modelcontextprotocol/sdk/server/stdio.js';
import { CallToolRequestSchema, ListToolsRequestSchema } from '@modelcontextprotocol/sdk/types.js';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';
import { registerToolHandlers } from './src/tool-registry.js';

// An MCP client launches this file directly (`node index.js`), so a
// --env-file flag never applies. Load .env here so the SQL_PWD_* vars that
// config/sql-servers.json refers to via password_env actually reach
// server-manager. A missing .env is not fatal: the parent process may supply
// those vars itself.
const __dirname = dirname(fileURLToPath(import.meta.url));
try {
  process.loadEnvFile(join(__dirname, '.env'));
} catch {
  // No .env file — fall back to the ambient environment.
}

const server = new Server(
  { name: 'mcp-sql', version: '1.0.0' },
  { capabilities: { tools: {} } }
);

// stdio serves exactly one client, so a single fixed session id is correct
// here. The HTTP transport derives a per-caller id instead.
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
