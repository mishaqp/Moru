// Moru's fast Linux mode: runs a command of the Linux environment in a real
// chroot instead of PRoot. Started as root through `su`; the command runs as
// root inside the rootfs.
//
//   run --rootfs R --uid U --gid G --tag T [--cwd DIR]
//       [--bind HOST GUEST]... [--bind-ro HOST GUEST]... [--fix HOST]...
//       -- PROGRAM [ARG]...
//     A private mount namespace (nothing leaks to Android, everything goes
//     away with the command), /proc, /dev and /sys, the binds, chroot, then
//     PROGRAM with MORU_RUN=T in its environment. When PROGRAM exits, every
//     process with MORU_RUN=T is killed (like PRoot's --kill-on-exit), and files the
//     run left owned by root under each --fix directory go back to U:G with
//     that directory's SELinux label, so the app can use them.
//   kill --tag T      kills every process with MORU_RUN=T.
//   fixown --uid U --gid G DIR...
//                     gives root-owned files under DIR back to U:G.
//   probe --rootfs R  checks root, a private mount namespace and the rootfs.
//
// Exit codes: PROGRAM's, 128+signal when it was killed, 125 when the chroot
// could not be set up (the reason is on stderr).

#define _GNU_SOURCE
#include <dirent.h>
#include <errno.h>
#include <fcntl.h>
#include <ftw.h>
#include <limits.h>
#include <sched.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mount.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <sys/xattr.h>
#include <unistd.h>

#define SETUP_FAILED 125
#define MAX_BINDS 64
#define MAX_FIX 64
#define SELINUX_XATTR "security.selinux"

struct bind {
  const char *host;
  const char *guest;
  int read_only;
};

static void fail(const char *what) {
  fprintf(stderr, "moru_chroot: %s: %s\n", what, strerror(errno));
  exit(SETUP_FAILED);
}

static void usage(const char *message) {
  fprintf(stderr, "moru_chroot: %s\n", message);
  exit(SETUP_FAILED);
}

// An absolute path without "." or ".." segments.
static int clean_absolute(const char *path) {
  if (path == NULL || path[0] != '/') return 0;
  const char *segment = path;
  while (*segment) {
    while (*segment == '/') segment++;
    const char *end = strchr(segment, '/');
    size_t length = end ? (size_t)(end - segment) : strlen(segment);
    if ((length == 1 && segment[0] == '.') ||
        (length == 2 && segment[0] == '.' && segment[1] == '.')) {
      return 0;
    }
    segment += length;
  }
  return 1;
}

static void join(char *out, const char *root, const char *guest) {
  if (snprintf(out, PATH_MAX, "%s%s", root, guest) >= PATH_MAX) {
    errno = ENAMETOOLONG;
    fail(guest);
  }
}

// mkdir -p for the path inside the rootfs; new directories belong to uid:gid.
static void make_dirs(const char *path, uid_t uid, gid_t gid) {
  char buffer[PATH_MAX];
  snprintf(buffer, sizeof(buffer), "%s", path);
  for (char *slash = buffer + 1; ; slash++) {
    if (*slash != '/' && *slash != '\0') continue;
    char saved = *slash;
    *slash = '\0';
    if (mkdir(buffer, 0755) == 0) {
      if (lchown(buffer, uid, gid) != 0) fail(buffer);
    } else if (errno != EEXIST) {
      fail(buffer);
    }
    *slash = saved;
    if (saved == '\0') break;
  }
}

static void bind_mount(const char *host, const char *target, int read_only,
                       uid_t uid, gid_t gid) {
  struct stat info;
  if (stat(host, &info) != 0) fail(host);
  if (S_ISDIR(info.st_mode)) {
    make_dirs(target, uid, gid);
  } else {
    char parent[PATH_MAX];
    snprintf(parent, sizeof(parent), "%s", target);
    char *slash = strrchr(parent, '/');
    if (slash && slash != parent) {
      *slash = '\0';
      make_dirs(parent, uid, gid);
    }
    int fd = open(target, O_CREAT | O_WRONLY | O_CLOEXEC, 0644);
    if (fd < 0) fail(target);
    close(fd);
  }
  if (mount(host, target, NULL, MS_BIND | MS_REC, NULL) != 0) fail(target);
  if (read_only &&
      mount(NULL, target, NULL, MS_BIND | MS_REMOUNT | MS_RDONLY, NULL) != 0) {
    fail(target);
  }
}

// Shorter guest paths first, so a bind inside another bind is mounted on top.
static int by_depth(const void *a, const void *b) {
  const struct bind *left = a;
  const struct bind *right = b;
  size_t l = strlen(left->guest);
  size_t r = strlen(right->guest);
  return l < r ? -1 : l > r ? 1 : 0;
}

// Whether /proc/PID/environ holds MORU_RUN=TAG.
static int has_tag(const char *pid, const char *tag) {
  char path[64];
  snprintf(path, sizeof(path), "/proc/%s/environ", pid);
  int fd = open(path, O_RDONLY | O_CLOEXEC);
  if (fd < 0) return 0;
  char wanted[256];
  int wanted_length = snprintf(wanted, sizeof(wanted), "MORU_RUN=%s", tag);
  static char buffer[65536];
  ssize_t total = 0;
  ssize_t read_now;
  while (total < (ssize_t)sizeof(buffer) - 1 &&
         (read_now = read(fd, buffer + total, sizeof(buffer) - 1 - total)) > 0) {
    total += read_now;
  }
  close(fd);
  for (ssize_t start = 0; start < total;) {
    size_t length = strnlen(buffer + start, total - start);
    if ((int)length == wanted_length &&
        memcmp(buffer + start, wanted, length) == 0) {
      return 1;
    }
    start += length + 1;
  }
  return 0;
}

// SIGKILLs every process with MORU_RUN=TAG, until none is left (a process
// can fork while the list is read). Returns how many were killed.
static int kill_tagged(const char *tag) {
  int total = 0;
  for (int round = 0; round < 20; round++) {
    int killed = 0;
    DIR *proc = opendir("/proc");
    if (proc == NULL) return total;
    struct dirent *entry;
    pid_t self = getpid();
    while ((entry = readdir(proc)) != NULL) {
      char *end;
      long pid = strtol(entry->d_name, &end, 10);
      if (*end != '\0' || pid <= 1 || pid == self) continue;
      if (has_tag(entry->d_name, tag) && kill((pid_t)pid, SIGKILL) == 0) {
        killed++;
      }
    }
    closedir(proc);
    total += killed;
    if (killed == 0) break;
    usleep(20000);
  }
  return total;
}

static uid_t fix_uid;
static gid_t fix_gid;
static char fix_label[256];
static ssize_t fix_label_length;

static int fix_entry(const char *path, const struct stat *info, int type,
                     struct FTW *walk) {
  (void)type;
  (void)walk;
  if (info->st_uid != 0 && info->st_gid != 0) return 0;
  if (lchown(path, fix_uid, fix_gid) != 0) {
    fprintf(stderr, "moru_chroot: chown %s: %s\n", path, strerror(errno));
    return 0;
  }
  if (fix_label_length > 0) {
    char current[256];
    ssize_t length = lgetxattr(path, SELINUX_XATTR, current, sizeof(current));
    if (length != fix_label_length ||
        memcmp(current, fix_label, (size_t)length) != 0) {
      lsetxattr(path, SELINUX_XATTR, fix_label, (size_t)fix_label_length, 0);
    }
  }
  return 0;
}

// Root-owned files under DIR go back to uid:gid with DIR's SELinux label.
// Stays on DIR's file system: another mount below it is not the app's.
static void fix_owner(const char *dir, uid_t uid, gid_t gid) {
  fix_uid = uid;
  fix_gid = gid;
  fix_label_length = lgetxattr(dir, SELINUX_XATTR, fix_label, sizeof(fix_label));
  if (fix_label_length < 0) fix_label_length = 0;
  nftw(dir, fix_entry, 32, FTW_PHYS | FTW_MOUNT);
}

static long number(const char *text, const char *name) {
  char *end;
  errno = 0;
  long value = strtol(text, &end, 10);
  if (errno != 0 || *end != '\0' || value < 0) usage(name);
  return value;
}

static void require_root(void) {
  if (geteuid() != 0) {
    errno = EPERM;
    fail("needs root (run through su)");
  }
}

// The private mount namespace and the mounts of the rootfs.
static void prepare(const char *rootfs, struct bind *binds, int bind_count,
                    uid_t uid, gid_t gid) {
  if (unshare(CLONE_NEWNS) != 0) fail("unshare mount namespace");
  if (mount(NULL, "/", NULL, MS_REC | MS_PRIVATE, NULL) != 0) {
    fail("make mounts private");
  }
  char target[PATH_MAX];
  join(target, rootfs, "/proc");
  make_dirs(target, uid, gid);
  if (mount("proc", target, "proc", MS_NOSUID | MS_NODEV | MS_NOEXEC, NULL) != 0) {
    fail(target);
  }
  join(target, rootfs, "/dev");
  make_dirs(target, uid, gid);
  if (mount("/dev", target, NULL, MS_BIND | MS_REC, NULL) != 0) fail(target);
  join(target, rootfs, "/sys");
  make_dirs(target, uid, gid);
  if (mount("/sys", target, NULL, MS_BIND | MS_REC, NULL) != 0) fail(target);
  qsort(binds, (size_t)bind_count, sizeof(*binds), by_depth);
  for (int i = 0; i < bind_count; i++) {
    join(target, rootfs, binds[i].guest);
    bind_mount(binds[i].host, target, binds[i].read_only, uid, gid);
  }
}

static int run(int argc, char **argv) {
  const char *rootfs = NULL;
  const char *tag = NULL;
  const char *cwd = "/";
  long uid = -1;
  long gid = -1;
  struct bind binds[MAX_BINDS];
  int bind_count = 0;
  const char *fix[MAX_FIX];
  int fix_count = 0;
  int i = 0;
  for (; i < argc; i++) {
    const char *option = argv[i];
    if (strcmp(option, "--") == 0) {
      i++;
      break;
    }
    if (i + 1 >= argc) usage(option);
    if (strcmp(option, "--rootfs") == 0) {
      rootfs = argv[++i];
    } else if (strcmp(option, "--tag") == 0) {
      tag = argv[++i];
    } else if (strcmp(option, "--cwd") == 0) {
      cwd = argv[++i];
    } else if (strcmp(option, "--uid") == 0) {
      uid = number(argv[++i], "--uid");
    } else if (strcmp(option, "--gid") == 0) {
      gid = number(argv[++i], "--gid");
    } else if (strcmp(option, "--fix") == 0) {
      if (fix_count == MAX_FIX) usage("too many --fix");
      fix[fix_count++] = argv[++i];
    } else if (strcmp(option, "--bind") == 0 ||
               strcmp(option, "--bind-ro") == 0) {
      if (i + 2 >= argc) usage(option);
      if (bind_count == MAX_BINDS) usage("too many binds");
      binds[bind_count].read_only = strcmp(option, "--bind-ro") == 0;
      binds[bind_count].host = argv[++i];
      binds[bind_count].guest = argv[++i];
      if (!clean_absolute(binds[bind_count].host) ||
          !clean_absolute(binds[bind_count].guest) ||
          strcmp(binds[bind_count].guest, "/") == 0) {
        usage("a bind needs absolute paths without . or ..");
      }
      bind_count++;
    } else {
      usage(option);
    }
  }
  if (!clean_absolute(rootfs) || strcmp(rootfs, "/") == 0) usage("--rootfs");
  if (tag == NULL || tag[0] == '\0' || strlen(tag) > 128) usage("--tag");
  if (uid < 0 || gid < 0) usage("--uid and --gid");
  if (!clean_absolute(cwd)) usage("--cwd");
  if (i >= argc) usage("no program");
  char **program = argv + i;
  for (int f = 0; f < fix_count; f++) {
    if (!clean_absolute(fix[f]) || strcmp(fix[f], "/") == 0) usage("--fix");
  }
  require_root();

  prepare(rootfs, binds, bind_count, (uid_t)uid, (gid_t)gid);

  // Terminal signals reach the whole foreground group; they are the
  // program's, not this process's, which must live to clean up.
  signal(SIGINT, SIG_IGN);
  signal(SIGQUIT, SIG_IGN);
  signal(SIGTSTP, SIG_IGN);
  signal(SIGTTIN, SIG_IGN);
  signal(SIGTTOU, SIG_IGN);
  signal(SIGHUP, SIG_IGN);

  pid_t child = fork();
  if (child < 0) fail("fork");
  if (child == 0) {
    for (int s = 1; s < NSIG; s++) signal(s, SIG_DFL);
    sigset_t none;
    sigemptyset(&none);
    sigprocmask(SIG_SETMASK, &none, NULL);
    // Every process of the run carries the tag; the caller also puts it in
    // the environment of a program that starts from an empty one (env -i).
    if (setenv("MORU_RUN", tag, 1) != 0) fail("setenv");
    if (chroot(rootfs) != 0) fail("chroot");
    if (chdir(cwd) != 0 && chdir("/") != 0) fail("chdir");
    execv(program[0], program);
    fprintf(stderr, "moru_chroot: %s: %s\n", program[0], strerror(errno));
    _exit(127);
  }

  int status = 0;
  while (waitpid(child, &status, 0) < 0) {
    if (errno != EINTR) {
      status = 0;
      break;
    }
  }
  kill_tagged(tag);
  for (int f = 0; f < fix_count; f++) fix_owner(fix[f], (uid_t)uid, (gid_t)gid);
  if (WIFSIGNALED(status)) return 128 + WTERMSIG(status);
  return WIFEXITED(status) ? WEXITSTATUS(status) : SETUP_FAILED;
}

static int probe(int argc, char **argv) {
  if (argc != 2 || strcmp(argv[0], "--rootfs") != 0) usage("probe --rootfs R");
  const char *rootfs = argv[1];
  if (!clean_absolute(rootfs)) usage("--rootfs");
  require_root();
  pid_t child = fork();
  if (child < 0) fail("fork");
  if (child == 0) {
    if (unshare(CLONE_NEWNS) != 0) fail("unshare mount namespace");
    if (mount(NULL, "/", NULL, MS_REC | MS_PRIVATE, NULL) != 0) {
      fail("make mounts private");
    }
    // Look for the shell as the guest will: Alpine's /bin/sh is an absolute
    // link to /bin/busybox, which only resolves inside the rootfs.
    if (chroot(rootfs) != 0) fail("chroot");
    if (access("/bin/sh", X_OK) != 0) fail("/bin/sh");
    _exit(0);
  }
  int status = 0;
  if (waitpid(child, &status, 0) < 0 || !WIFEXITED(status) ||
      WEXITSTATUS(status) != 0) {
    return SETUP_FAILED;
  }
  printf("moru_chroot ok\n");
  return 0;
}

int main(int argc, char **argv) {
  if (argc < 2) usage("run | kill | fixown | probe");
  const char *command = argv[1];
  if (strcmp(command, "run") == 0) return run(argc - 2, argv + 2);
  if (strcmp(command, "probe") == 0) return probe(argc - 2, argv + 2);
  if (strcmp(command, "kill") == 0) {
    if (argc != 4 || strcmp(argv[2], "--tag") != 0 || argv[3][0] == '\0') {
      usage("kill --tag T");
    }
    require_root();
    printf("%d\n", kill_tagged(argv[3]));
    return 0;
  }
  if (strcmp(command, "fixown") == 0) {
    if (argc < 7 || strcmp(argv[2], "--uid") != 0 || strcmp(argv[4], "--gid") != 0) {
      usage("fixown --uid U --gid G DIR...");
    }
    uid_t uid = (uid_t)number(argv[3], "--uid");
    gid_t gid = (gid_t)number(argv[5], "--gid");
    require_root();
    for (int i = 6; i < argc; i++) {
      if (!clean_absolute(argv[i]) || strcmp(argv[i], "/") == 0) usage(argv[i]);
      fix_owner(argv[i], uid, gid);
    }
    return 0;
  }
  usage("run | kill | fixown | probe");
  return SETUP_FAILED;
}
