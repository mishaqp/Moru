/// Limit the helper's process enumeration to this fixture's registered PIDs.
/// Actual /proc identities, UIDs, environments and disappearing processes stay
/// real. Unrelated host processes must not decide whether fixture cleanup can
/// prove an orphan, especially under root or a CI runner with ptrace limits.
const acpTestProcessTableScript = r'''
'use strict';
const fs = require('node:fs');
const original = fs.readdirSync;
fs.readdirSync = function(p, ...args) {
  const entries = original.call(this, p, ...args);
  if (p !== '/proc') return entries;
  const pids = new Set([
    String(process.pid),
    ...JSON.parse(process.env.MORU_TEST_PROCESS_IDS || '[]').map(String),
  ]);
  for (const file of JSON.parse(process.env.MORU_TEST_PID_FILES || '[]')) {
    try { pids.add(fs.readFileSync(file, 'utf8').trim()); }
    catch (error) { if (error.code !== 'ENOENT') throw error; }
  }
  return entries.filter(entry => pids.has(typeof entry === 'string' ? entry : entry.name));
};
''';
