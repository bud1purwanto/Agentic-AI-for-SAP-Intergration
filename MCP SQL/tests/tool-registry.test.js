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
