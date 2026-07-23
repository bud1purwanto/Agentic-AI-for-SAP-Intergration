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

// Every tool must be reachable through CallTool and receive ctx. With no
// active server and no arguments, each handler short-circuits to a structured
// error before touching the network — so this runs fully offline while still
// proving ctx threading (a handler called without ctx throws on ctx.sessionId)
// and that each schema's property names line up with what the handler reads.
test('every registered tool is reachable and receives ctx without throwing', async () => {
  const server = createStubServer();
  registerToolHandlers(server, { CallToolRequestSchema, ListToolsRequestSchema }, { sessionId: 'reach-check' });

  for (const { name } of TOOLS) {
    const result = await server.callTool(name, {});
    const parsed = JSON.parse(result.content[0].text);

    // A handler that threw (e.g. TypeError on ctx.sessionId) surfaces as
    // isError with a JS error message rather than a tool-level response.
    assert.notEqual(result.isError, true, `${name} threw instead of returning a response`);
    assert.equal(typeof parsed, 'object', `${name} did not return a JSON object`);
    assert.doesNotMatch(
      JSON.stringify(parsed),
      /Cannot read propert|undefined is not|is not a function/,
      `${name} looks like it hit a JS error rather than a handled path`
    );
  }
});

test('each tool inputSchema declares its required fields as properties', () => {
  for (const { name, inputSchema } of TOOLS) {
    for (const field of inputSchema.required || []) {
      assert.ok(
        inputSchema.properties && field in inputSchema.properties,
        `${name}: required field "${field}" is not declared in properties`
      );
    }
  }
});
