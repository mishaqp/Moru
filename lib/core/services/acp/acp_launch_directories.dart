import 'dart:io';

import '../workspace/workspace_runtime.dart';
import 'acp_agent_catalog.dart';

/// Private scratch directories belong to a prepared launch, not a session.
/// In-memory leases protect simultaneous preparations; guest owner records
/// protect live processes when a new Moru process recovers abandoned runs.
class AcpLaunchDirectories {
  final Map<WorkspaceRuntime, Set<String>> _active = Map.identity();

  Future<void> Function() acquire(
    WorkspaceRuntime runtime,
    String directory,
    Future<void> Function() remove,
  ) {
    final active = _active.putIfAbsent(runtime, () => {});
    active.add(directory);
    Future<void>? released;
    return () => released ??= () async {
      try {
        await remove();
      } finally {
        active.remove(directory);
        if (active.isEmpty) _active.remove(runtime);
      }
    }();
  }

  String prepareScript(WorkspaceRuntime runtime, String directory) =>
      '$_invoke prepare ${quote(directory)} $pid '
      '${(_active[runtime] ?? {}).map(quote).join(' ')} '
      "|| { printf '%s\\n' 'Moru agent temporary directory unavailable' >&2; exit 1; }";

  static String removeScript(String directory) =>
      '$_invoke remove ${quote(directory)}';

  // No shared script is overwritten while another launch is reading it.
  // The inline helper contains no launch credentials or user content.
  static String get _invoke => 'node -e ${quote(script)} -- --moru-inline';

  /// The shell retains its PID through exec. Record that identity before
  /// starting the adapter, so recovery does not mistake a live chat for debris.
  static List<String> arguments(AcpLaunch launch) => [
    '-c',
    'set -e\numask 077\n'
        '${launch.unsetEnvironmentScript}'
        '${launch.isolateCodexDaemon ? '$_invoke codex-target ${quote(launch.temporaryDirectory!)} $pid\nmount --bind ${quote(launch.temporaryDirectory!)} /tmp/codex-daemon-0\n' : ''}'
        '$_invoke claim ${quote(launch.temporaryDirectory!)} "\$\$"\n'
        'exec ${[launch.command, ...launch.arguments].map(quote).join(' ')}',
  ];

  static String quote(String value) => "'${value.replaceAll("'", "'\\''")}'";

  static const script = r'''
'use strict';
const fs = require('node:fs');
const path = require('node:path');
const [action, directory, ownerPid, ...protectedPaths] = process.argv.slice(2);
const root = path.dirname(directory);
const name = path.basename(directory);
const runName = /^[A-Za-z0-9_-]{22}$/;
if (!path.isAbsolute(directory) || !runName.test(name) || path.resolve(directory) !== directory) {
  throw new Error('Invalid Moru launch temporary directory');
}
const noFollow = fs.constants.O_RDONLY | fs.constants.O_NOFOLLOW;
const marker = '.moru-acp-launches-v1';
const magic = 'moru-acp-launches-v1\n';
const pause = ms => Atomics.wait(new Int32Array(new SharedArrayBuffer(4)), 0, 0, ms);
function readFile(file, limit) {
  const fd = fs.openSync(file, noFollow);
  try {
    const stat = fs.fstatSync(fd);
    if (!stat.isFile() || stat.size > limit) throw new Error('Invalid launch owner record');
    return fs.readFileSync(fd, 'utf8');
  } finally { fs.closeSync(fd); }
}
function openDirectory(entry) {
  const fd = fs.openSync(entry, noFollow | fs.constants.O_DIRECTORY);
  const stat = fs.fstatSync(fd);
  const anchor = `/proc/self/fd/${fd}`;
  function unchanged() {
    try {
      const current = fs.lstatSync(entry);
      return current.isDirectory() && current.dev === stat.dev && current.ino === stat.ino;
    } catch (error) { if (error.code === 'ENOENT') return false; throw error; }
  }
  return { fd, stat, anchor, entry, unchanged };
}
function removeDirectory(handle) {
  // Bind each descendant directory before descending. A symlink substituted
  // after a pathname stat must never redirect a recursive rm into user data.
  for (const entry of fs.readdirSync(handle.anchor)) {
    const child = path.join(handle.anchor, entry);
    let nested;
    try { nested = openDirectory(child); }
    catch (error) {
      if (error.code === 'ENOENT') continue;
      if (error.code !== 'ENOTDIR' && error.code !== 'ELOOP') throw error;
      try { fs.unlinkSync(child); }
      catch (error) { if (!['ENOENT', 'EISDIR', 'EPERM'].includes(error.code)) throw error; }
      continue;
    }
    try { removeDirectory(nested); }
    finally { fs.closeSync(nested.fd); }
  }
  if (handle.unchanged()) {
    try { fs.rmdirSync(handle.entry); }
    catch (error) { if (!['ENOENT', 'ENOTEMPTY'].includes(error.code)) throw error; }
  }
}
if (action === 'prepare') {
  const parent = path.dirname(root);
  fs.mkdirSync(parent, { recursive: true, mode: 0o700 });
  const handle = openDirectory(parent);
  try {
    if (fs.realpathSync(parent) !== parent) throw new Error('Moru temporary directory has a symbolic parent');
    const prefix = `.moru-root-${path.basename(root)}-`;
    const appUid = fs.statSync(`/proc/${ownerPid}`).uid;
    for (const entry of fs.readdirSync(handle.anchor, { withFileTypes: true })) {
      if (!entry.isDirectory() || !entry.name.startsWith(prefix)) continue;
      const identity = entry.name.slice(prefix.length).match(/^(\d+)-(\d+)-[A-Za-z0-9_-]{22}$/);
      if (!identity) continue;
      let alive = true;
      try { const info = processInfo(identity[1]); alive = running(info) && info.start === identity[2]; }
      catch (error) { alive = !['ENOENT', 'ESRCH'].includes(error.code); }
      if (alive) continue;
      let stage;
      try { stage = openDirectory(path.join(handle.anchor, entry.name)); }
      catch (error) { if (['ENOENT', 'ENOTDIR', 'ELOOP'].includes(error.code)) continue; throw error; }
      try {
        if ([0, appUid].includes(stage.stat.uid) && (stage.stat.mode & 0o777) === 0o700) removeDirectory(stage);
      } finally { fs.closeSync(stage.fd); }
    }
    const destination = path.join(handle.anchor, path.basename(root));
    let exists = true;
    try { fs.lstatSync(destination); }
    catch (error) { if (error.code === 'ENOENT') exists = false; else throw error; }
    if (!exists) {
      const stageName = `${prefix}${process.pid}-${processInfo(process.pid).start}-${name}`;
      const staging = path.join(handle.anchor, stageName);
      fs.mkdirSync(staging, { mode: 0o700 });
      const staged = openDirectory(staging);
      try {
        fs.writeFileSync(path.join(staged.anchor, marker), magic, { mode: 0o600, flag: 'wx' });
        if (!staged.unchanged()) throw new Error('Moru temporary directory bootstrap changed');
      } finally { fs.closeSync(staged.fd); }
      // Publish only a complete namespace. A crash before rename leaves a
      // staging directory, never an unmarked final root that blocks restart.
      try {
        try { fs.lstatSync(destination); exists = true; }
        catch (error) { if (error.code !== 'ENOENT') throw error; }
        if (!exists) fs.renameSync(staging, destination);
      } catch (error) { if (!['EEXIST', 'ENOTEMPTY'].includes(error.code)) throw error; }
      try {
        const stage = openDirectory(staging);
        try { removeDirectory(stage); } finally { fs.closeSync(stage.fd); }
      } catch (error) { if (error.code !== 'ENOENT') throw error; }
    }
  } finally { fs.closeSync(handle.fd); }
}
let rootFd;
try { rootFd = fs.openSync(root, noFollow | fs.constants.O_DIRECTORY); }
catch (error) {
  if (action === 'remove' && error.code === 'ENOENT') process.exit(0);
  throw error;
}
// Every mutation below stays anchored to this directory descriptor. A rename
// or a symlink substituted at `root` cannot redirect cleanup into user data.
const anchor = `/proc/self/fd/${rootFd}`;
const rootStat = fs.fstatSync(rootFd);
function assertRoot() {
  const current = fs.lstatSync(root);
  if (!current.isDirectory() || current.dev !== rootStat.dev || current.ino !== rootStat.ino ||
      fs.realpathSync(root) !== root) {
    throw new Error('Moru launch temporary directory parent changed or is symbolic');
  }
}
assertRoot();
if ((rootStat.mode & 0o777) !== 0o700) {
  throw new Error('Moru launch temporary directory is not private (mode 0700 required)');
}
if (readFile(path.join(anchor, marker), 128) !== magic) throw new Error('Moru launch temporary directory is not a managed directory');
const here = path.join(anchor, name);
function bootId() {
  try { return fs.readFileSync('/proc/sys/kernel/random/boot_id', 'utf8').trim(); }
  catch { return null; }
}
function processInfo(pid) {
  const stat = fs.readFileSync(`/proc/${pid}/stat`, 'utf8');
  const fields = stat.slice(stat.lastIndexOf(')') + 2).split(' ');
  return { start: fields[19], state: fields[0] };
}
function running(info) { return info.state !== 'Z' && info.state !== 'X'; }
function recordFor(pid, phase) {
  return { pid: Number(pid), boot: bootId(), start: processInfo(pid).start,
    uid: fs.statSync(`/proc/${pid}`).uid, phase };
}
function claim(pid, handle) {
  const temporary = path.join(handle.anchor, `.owner-${process.pid}`);
  fs.writeFileSync(temporary, JSON.stringify(recordFor(pid, 'running')), { mode: 0o600, flag: 'wx' });
  fs.renameSync(temporary, path.join(handle.anchor, '.owner'));
}
function owner(candidate) {
  try {
    const record = JSON.parse(readFile(path.join(candidate, '.owner'), 4096));
    if (!Number.isSafeInteger(record.pid) || record.pid <= 0 || typeof record.start !== 'string') {
      return { unknown: true };
    }
    const boot = bootId();
    if (record.boot && boot && record.boot !== boot) return { record, alive: false };
    try {
      const info = processInfo(record.pid);
      return { record, alive: running(info) && info.start === record.start };
    } catch (error) {
      return { record, alive: false, unknown: error.code !== 'ENOENT' && error.code !== 'ESRCH' };
    }
  } catch (error) {
    // Only a missing record is an orphan. Permission/format errors provide no
    // evidence that the adapter has died, particularly after root -> PRoot.
    return { unknown: error.code !== 'ENOENT' };
  }
}
function liveDirectories() {
  let processes;
  try { processes = fs.readdirSync('/proc').filter(pid => /^\d+$/.test(pid)); }
  catch { return null; }
  for (let attempt = 0; attempt < 5; attempt++) {
    const live = new Set();
    const unreadableOwners = new Set();
    const identities = new Map();
    for (const pid of processes) {
      let uid;
      try {
        const info = processInfo(pid);
        identities.set(pid, info.start);
        if (!running(info)) continue;
        uid = fs.statSync(`/proc/${pid}`).uid;
        const environment = fs.readFileSync(`/proc/${pid}/environ`, 'utf8');
        for (const entry of environment.split('\0')) {
          for (const key of ['MORU_ACP_TEMP_DIR=', 'CLAUDE_CODE_TMPDIR=']) {
            if (entry.startsWith(key)) live.add(entry.slice(key.length));
          }
        }
      } catch (error) {
        if (error.code !== 'ENOENT' && error.code !== 'ESRCH') {
          if (uid === undefined) return null;
          unreadableOwners.add(uid);
        }
      }
    }
    let next;
    try { next = fs.readdirSync('/proc').filter(pid => /^\d+$/.test(pid)); }
    catch { return null; }
    // Never decide death from a cached /proc listing. If an SDK forks after
    // enumeration and its parent exits, inspect the new PID before deleting.
    const previous = new Set(processes);
    let stable = next.length === processes.length && next.every(pid => previous.has(pid));
    if (stable) {
      for (const pid of next) {
        try { if (processInfo(pid).start !== identities.get(pid)) stable = false; }
        catch (error) {
          if (error.code === 'ENOENT' || error.code === 'ESRCH') stable = false;
          else return null;
        }
      }
    }
    if (stable) {
      return { live, unreadableOwners };
    }
    processes = next;
  }
  return null; // A busy or inaccessible process table cannot prove an orphan.
}
function deletable(handle, original, explicit = false) {
  const state = owner(handle.anchor);
  if (state.unknown || (state.alive && (!explicit || state.record.phase !== 'prepared'))) return false;
  const processes = liveDirectories();
  if (!processes || processes.live.has(original)) return false;
  const stat = handle.stat;
  if (!stat.isDirectory() || processes.unreadableOwners.has(stat.uid) ||
      (state.record && processes.unreadableOwners.has(state.record.uid))) return false;
  // Close the race between the process scan and a surviving adapter claim.
  const after = owner(handle.anchor);
  return handle.unchanged() && !after.unknown && (!after.alive || (explicit && after.record.phase === 'prepared'));
}
function sweep() {
  const protectedSet = new Set(protectedPaths);
  for (const entry of fs.readdirSync(anchor, { withFileTypes: true })) {
    if (!entry.isDirectory()) continue;
    const candidate = path.join(anchor, entry.name);
    try {
      if (runName.test(entry.name)) {
        const original = path.join(root, entry.name);
        if (original === directory || protectedSet.has(original)) continue;
        const handle = openDirectory(candidate);
        try { if (deletable(handle, original)) removeDirectory(handle); }
        finally { fs.closeSync(handle.fd); }
      } else if (/^\.preparing-\d+-\d+-[A-Za-z0-9_-]{22}$/.test(entry.name)) {
        // Staging paths are never exposed to an adapter; their encoded helper
        // identity also recovers a crash before the .owner file was written.
        const [, helperPid, start] = entry.name.split('-');
        let alive = true;
        try { const info = processInfo(helperPid); alive = running(info) && info.start === start; }
        catch (error) { alive = error.code !== 'ENOENT' && error.code !== 'ESRCH'; }
        if (!alive) {
          const handle = openDirectory(candidate);
          try { removeDirectory(handle); } finally { fs.closeSync(handle.fd); }
        }
      }
    } catch (error) { if (!['ENOENT', 'ENOTDIR', 'ELOOP'].includes(error.code)) throw error; }
  }
}
if (action === 'prepare') {
  sweep();
  const staging = path.join(anchor, `.preparing-${process.pid}-${processInfo(process.pid).start}-${name}`);
  fs.mkdirSync(staging, { mode: 0o700 });
  const staged = openDirectory(staging);
  try {
    fs.writeFileSync(path.join(staged.anchor, '.owner'), JSON.stringify(recordFor(ownerPid, 'prepared')),
      { mode: 0o600, flag: 'wx' });
    if (!staged.unchanged()) throw new Error('Moru launch temporary directory preparation changed');
  } finally { fs.closeSync(staged.fd); }
  fs.renameSync(staging, here);
  assertRoot();
} else if (action === 'claim') {
  const handle = openDirectory(here);
  try {
    if (!handle.unchanged()) throw new Error('Moru launch temporary directory changed');
    claim(ownerPid, handle);
    if (!handle.unchanged()) throw new Error('Moru launch temporary directory changed');
    assertRoot();
  } finally { fs.closeSync(handle.fd); }
} else if (action === 'remove') {
  // Native root cancellation completes asynchronously. A close notification
  // is insufficient evidence that the adapter and all its SDK children died.
  for (let attempt = 0; attempt < 20; attempt++) {
    try {
      const handle = openDirectory(here);
      try {
        if (deletable(handle, directory, true)) {
          removeDirectory(handle);
          break;
        }
      } finally { fs.closeSync(handle.fd); }
    } catch (error) { if (['ENOENT', 'ENOTDIR', 'ELOOP'].includes(error.code)) break; throw error; }
    pause(50);
  }
  // If still alive/uninspectable, leave it for a subsequent preparation.
} else if (action === 'codex-target') {
  // moru_chroot creates a private mount namespace per run. The bind is local
  // to that namespace; neither the old daemon nor its files are changed.
  const target = '/tmp/codex-daemon-0';
  const appOwner = fs.statSync(`/proc/${ownerPid}`);
  try {
    fs.mkdirSync(target, { mode: 0o700 });
    // Only a new empty mountpoint is returned to the Android app. Never chown
    // an existing daemon directory, which another PRoot chat may be using.
    fs.chownSync(target, appOwner.uid, appOwner.gid);
  } catch (error) { if (error.code !== 'EEXIST') throw error; }
  if (!fs.lstatSync(target).isDirectory()) throw new Error('Codex temporary daemon directory is not a directory');
  assertRoot();
} else {
  throw new Error('Invalid Moru launch directory operation');
}
fs.closeSync(rootFd);
''';
}
