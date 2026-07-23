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
