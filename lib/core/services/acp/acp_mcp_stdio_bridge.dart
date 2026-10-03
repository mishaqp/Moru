import 'acp_agent_catalog.dart';

/// Built-in Node modules only. Credentials are supplied by ACP through env.
class AcpMcpStdioBridge {
  static const file = AcpConfigFile('$acpConfigDir/moru-mcp.cjs', r'''
const http = require('node:http');
const readline = require('node:readline');
const endpoint = new URL(process.env.MORU_MCP_URL);
const token = process.env.MORU_MCP_TOKEN;
const active = new Set();
let closed = false;
let version;
function write(value) {
  if (!closed) process.stdout.write(JSON.stringify(value) + '\n');
}
function error(message, request) {
  if (request && Object.hasOwn(request, 'id')) {
    write({jsonrpc: '2.0', id: request.id, error: {code: -32000, message}});
  }
}
const input = readline.createInterface({input: process.stdin});
input.on('line', line => {
  let message;
  try { message = JSON.parse(line); }
  catch (_) {
    write({jsonrpc: '2.0', id: null, error: {code: -32700, message: 'Invalid JSON'}});
    return;
  }
  const headers = {
    'Authorization': 'Bearer ' + token,
    'Content-Type': 'application/json',
    'Accept': 'application/json, text/event-stream'
  };
  if (version) headers['MCP-Protocol-Version'] = version;
  const request = http.request(endpoint, {method: 'POST', headers}, response => {
    let body = '';
    response.setEncoding('utf8');
    response.on('data', data => { body += data; });
    response.on('error', () => error('Moru MCP response interrupted', message));
    response.on('end', () => {
      active.delete(request);
      if (response.statusCode === 202) return;
      if (response.statusCode !== 200) {
        error('Moru MCP HTTP ' + response.statusCode, message);
        return;
      }
      try {
        const result = JSON.parse(body);
        if (message.method === 'initialize' && result.result) {
          version = result.result.protocolVersion;
        }
        if (Object.hasOwn(message, 'id')) write(result);
      } catch (_) { error('Invalid Moru MCP response', message); }
    });
  });
  active.add(request);
  request.on('error', () => {
    active.delete(request);
    error('Moru MCP is unavailable', message);
  });
  request.end(JSON.stringify(message));
});
input.on('close', () => {
  closed = true;
  for (const request of active) request.destroy();
});
''');
}
