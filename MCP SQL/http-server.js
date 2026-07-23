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
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';
import { registerToolHandlers } from './src/tool-registry.js';

// Load .env so MCP_HTTP_TOKEN and the SQL_PWD_* vars are available even when
// this file is started without a --env-file flag. Missing .env is not fatal.
const __dirname = dirname(fileURLToPath(import.meta.url));
try {
  process.loadEnvFile(join(__dirname, '.env'));
} catch {
  // No .env file — fall back to the ambient environment.
}

const PORT = process.env.MCP_HTTP_PORT || 8092;
const HOST = process.env.MCP_HTTP_HOST || '0.0.0.0';
const AUTH_TOKEN = process.env.MCP_HTTP_TOKEN;

if (!AUTH_TOKEN) {
  console.error(
    'MCP_HTTP_TOKEN belum di-set. Set variabel ini di .env (atau di environment) ' +
      'sebelum menjalankan HTTP server — tanpa token, server tidak boleh dibuka ke jaringan.'
  );
  process.exit(1);
}

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

// Health check tanpa auth — hanya status proses, tidak membocorkan data apa pun.
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
