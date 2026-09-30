"""Runs Moru's chroot helper (android/app/src/main/cpp/moru_chroot.c) for real.

The helper needs root: the test runs it directly as root, or through
`sudo -n` (GitHub's Ubuntu runners allow it). It is built for the host with
gcc; the rootfs holds small static programs instead of a distribution.
"""
import os
from pathlib import Path
import subprocess
import tempfile
import time
import unittest
import uuid

SOURCE = Path(__file__).resolve().parents[1] / 'android/app/src/main/cpp/moru_chroot.c'
APP_UID = 10538

PROGRAMS = {
    # Prints what it sees, writes into the binds, exits 3.
    'report': r'''
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <sys/stat.h>
#include <unistd.h>
int main(void) {
  char cwd[256];
  if (!getcwd(cwd, sizeof cwd)) return 1;
  struct stat info;
  printf("uid=%d cwd=%s proc=%d work=%d\n", getuid(), cwd,
         stat("/proc/self", &info) == 0, stat("/work/hello", &info) == 0);
  int fd = open("/work/created", O_CREAT | O_WRONLY, 0600);
  if (fd < 0 || write(fd, "x", 1) != 1) return 1;
  close(fd);
  mkdir("/work/dir", 0755);
  printf("ro_write=%d\n", open("/ro/x", O_CREAT | O_WRONLY, 0644) >= 0);
  return 3;
}
''',
    # Uses /dev/fd and /dev/shm like shells and runtimes do.
    'devices': r'''
#include <fcntl.h>
#include <stdio.h>
#include <unistd.h>
int main(void) {
  int fd = open("/dev/shm/moru-shm", O_CREAT | O_WRONLY, 0600);
  printf("fd=%d stdout=%d shm=%d\n", access("/dev/fd/0", F_OK) == 0,
         access("/dev/stdout", F_OK) == 0, fd >= 0);
  return 0;
}
''',
    # Leaves a child in its own session behind and exits 5.
    'orphan': r'''
#include <unistd.h>
int main(void) {
  if (fork() == 0) { setsid(); sleep(100); return 0; }
  return 5;
}
''',
    # Runs until killed, with a child.
    'wait': r'''
#include <unistd.h>
int main(void) { if (fork() == 0) sleep(100); sleep(100); return 0; }
''',
}


# Counts processes with MORU_RUN=<argv[1]>. The run's processes are root's:
# their environment is readable only by root, so this runs like the helper.
COUNT_TAGGED = r'''
import sys
from pathlib import Path
wanted = f"MORU_RUN={sys.argv[1]}".encode()
count = 0
for environ in Path("/proc").glob("[0-9]*/environ"):
    try:
        if wanted in environ.read_bytes().split(b"\0"):
            count += 1
    except OSError:
        pass
print(count)
'''


class MoruChrootTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.temp = Path(tempfile.mkdtemp(prefix='moru-chroot-'))
        cls.helper = cls.temp / 'moru_chroot'
        subprocess.run(['gcc', '-Wall', '-Wextra', '-Werror', '-O2', '-o', cls.helper, SOURCE],
                       check=True)
        cls.root = [] if os.geteuid() == 0 else ['sudo', '-n']
        rootfs = cls.temp / 'rootfs'
        (rootfs / 'bin').mkdir(parents=True)
        (rootfs / 'bin/sh').write_bytes(b'')
        (rootfs / 'bin/sh').chmod(0o755)
        for name, code in PROGRAMS.items():
            source = cls.temp / f'{name}.c'
            source.write_text(code)
            subprocess.run(['gcc', '-static', '-O2', '-o', rootfs / 'bin' / name, source],
                           check=True)
        (cls.temp / 'work').mkdir()
        (cls.temp / 'work/hello').write_text('hi')
        (cls.temp / 'ro').mkdir()
        cls.sudo('chown', '-R', f'{APP_UID}:{APP_UID}', rootfs, cls.temp / 'work')
        cls.rootfs = rootfs

    @classmethod
    def tearDownClass(cls):
        cls.sudo('rm', '-rf', cls.temp)

    @classmethod
    def sudo(cls, *args, env=None, check=True):
        return subprocess.run([*cls.root, *map(str, args)], capture_output=True, text=True,
                              env=env, check=check)

    def helper_run(self, tag, *program, extra=()):
        return self.sudo(
            self.helper, 'run', '--rootfs', self.rootfs, '--uid', APP_UID, '--gid', APP_UID,
            '--tag', tag, *extra, '--', *program, check=False)

    def test_runs_as_root_in_a_private_namespace_and_returns_files(self):
        mounts_before = Path('/proc/self/mountinfo').read_text()
        result = self.helper_run(
            'report', '/bin/report',
            extra=['--cwd', '/work', '--bind', self.temp / 'work', '/work',
                   '--bind-ro', self.temp / 'ro', '/ro', '--fix', self.temp / 'work'])
        self.assertEqual(result.returncode, 3, result.stderr)
        self.assertIn('uid=0 cwd=/work proc=1 work=1', result.stdout)
        self.assertIn('ro_write=0', result.stdout)
        # Nothing mounted outside the command.
        self.assertEqual(Path('/proc/self/mountinfo').read_text(), mounts_before)
        for name in ('created', 'dir', 'hello'):
            info = (self.temp / 'work' / name).stat()
            self.assertEqual((info.st_uid, info.st_gid), (APP_UID, APP_UID), name)
        # Mount points made in the rootfs belong to the app too.
        for name in ('proc', 'dev', 'sys', 'work', 'ro'):
            self.assertEqual((self.rootfs / name).stat().st_uid, APP_UID, name)

    def setUp(self):
        # A fresh tag per test: processes of an earlier, interrupted run
        # cannot be counted.
        self.tag = uuid.uuid4().hex

    def tagged(self, tag):
        result = self.sudo('python3', '-c', COUNT_TAGGED, tag)
        return int(result.stdout)

    def tagged_command(self, tag, program):
        return [*self.root, str(self.helper), 'run', '--rootfs', str(self.rootfs),
                '--uid', str(APP_UID), '--gid', str(APP_UID), '--tag', tag, '--', program]

    def test_processes_left_behind_are_killed_on_exit(self):
        result = subprocess.run(self.tagged_command(self.tag, '/bin/orphan'),
                                capture_output=True, text=True)
        self.assertEqual(result.returncode, 5, result.stderr)
        self.assertEqual(self.tagged(self.tag), 0)

    def test_kill_stops_every_process_of_the_run(self):
        # The program and its child carry the tag; the helper does not, so it
        # lives to clean up and reports the program's death.
        with subprocess.Popen(self.tagged_command(self.tag, '/bin/wait'),
                              stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL) as process:
            for _ in range(200):
                if self.tagged(self.tag) == 2:
                    break
                time.sleep(0.05)
            self.assertEqual(self.tagged(self.tag), 2)
            killed = self.sudo(self.helper, 'kill', '--tag', self.tag)
            self.assertEqual(int(killed.stdout), 2)
            self.assertEqual(process.wait(timeout=10), 128 + 9)
        self.assertEqual(self.tagged(self.tag), 0)

    def test_fixown_returns_root_files_under_a_folder(self):
        folder = self.temp / 'fix'
        self.sudo('mkdir', '-p', folder / 'sub')
        self.sudo('touch', folder / 'sub/file')
        self.sudo('chown', f'{APP_UID}:{APP_UID}', folder)
        self.sudo(self.helper, 'fixown', '--uid', APP_UID, '--gid', APP_UID, folder)
        for path in (folder / 'sub', folder / 'sub/file'):
            self.assertEqual(path.stat().st_uid, APP_UID, path)

    def test_bad_arguments_and_missing_programs_are_reported(self):
        bad = self.helper_run('bad', '/bin/report', extra=['--bind', self.temp, '../x'])
        self.assertEqual(bad.returncode, 125)
        self.assertIn('absolute paths', bad.stderr)
        missing = self.helper_run('missing', '/bin/none')
        self.assertEqual(missing.returncode, 127)
        self.assertEqual(self.sudo(self.helper, 'probe', '--rootfs', self.rootfs).stdout,
                         'moru_chroot ok\n')

    def test_standard_devices_exist_and_shm_is_the_rootfs_tmp(self):
        result = self.helper_run('devices', '/bin/devices')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout, 'fd=1 stdout=1 shm=1\n')
        self.assertTrue((self.rootfs / 'tmp/moru-shm').exists())

    def test_probe_resolves_the_shell_inside_the_rootfs(self):
        # Alpine: /bin/sh -> /bin/busybox, an absolute link that only
        # resolves inside the guest.
        alpine = self.temp / 'alpine'
        (alpine / 'bin').mkdir(parents=True)
        (alpine / 'bin/moru-busybox').write_bytes(b'')
        (alpine / 'bin/moru-busybox').chmod(0o755)
        (alpine / 'bin/sh').symlink_to('/bin/moru-busybox')
        self.assertFalse(Path('/bin/moru-busybox').exists())
        result = self.sudo(self.helper, 'probe', '--rootfs', alpine, check=False)
        self.assertEqual((result.returncode, result.stdout), (0, 'moru_chroot ok\n'),
                         result.stderr)
        (alpine / 'bin/moru-busybox').unlink()
        result = self.sudo(self.helper, 'probe', '--rootfs', alpine, check=False)
        self.assertEqual(result.returncode, 125)
        self.assertIn('/bin/sh', result.stderr)

    def test_needs_root(self):
        if os.geteuid() == 0:
            result = subprocess.run(
                ['setpriv', f'--reuid={APP_UID}', f'--regid={APP_UID}', '--clear-groups',
                 str(self.helper), 'probe', '--rootfs', str(self.rootfs)],
                capture_output=True, text=True)
        else:
            result = subprocess.run([str(self.helper), 'probe', '--rootfs', str(self.rootfs)],
                                    capture_output=True, text=True)
        self.assertEqual(result.returncode, 125)
        self.assertIn('needs root', result.stderr)


if __name__ == '__main__':
    unittest.main()
