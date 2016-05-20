/*
 * Copyright 2016, Clemens Fruhwirth <clemens@endorphin.org>
 * An ad-hoc sandboxer using unpriviliged user space containers
 *
 */

#define _GNU_SOURCE
#include <sched.h>
#include <stdlib.h>
#include <unistd.h>
#include <stdio.h>
#include <sys/mount.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <fcntl.h>
#include <sys/wait.h>
#include <stdarg.h>
#include <linux/limits.h>
#include <errno.h>
 
int pivot_root(const char *new_root, const char *put_old);

// FIXME write a perror+exit(errno) helper.

/* Helpers */

static int check(const char *pstr, int rc) {
  if (rc < 0) {
    perror(pstr);
    exit(rc);
  }
  return rc;
}

/**
 * Same as asprintf(buf, ..) except that buf is returned.
 */ 
char *aasprintf(const char *fmt, ...) {
  va_list args; char *buf;
  va_start(args, fmt);
  vasprintf(&buf, fmt, args);
  va_end(args);
  return buf;
}

/**
 * Write a string to a file
 */ 
void write_file(char *path, char *str) {
  int fd = check("open", open(path, O_RDWR));
  write(fd, str, strlen(str));   // FIXME return code check
  check("close", close(fd));
}

/**
 * Lazy mkdir does no work if the directory exist. Otherwise, panic.
 */
void lazy_mkdir(char *dir) {
  struct stat buf;
  int rc = stat(dir, &buf);
  if(rc == 0) {
    if(!S_ISDIR(buf.st_mode)) {
      printf("%s already exists but is no directory.\n"); // FIXME, print to stderr
      exit(-1);
    }
  } else if(errno == ENOENT) {
    check(aasprintf("mkdir %s", dir), mkdir(dir, S_IRWXU));
  } else {
    perror("lazy_mkdir");
    exit(-1);
  }
}

/**
 * Recursive mkdir. Like mkdir -p
 */
void mkdir_p(char *dir) {
  char *ptr = dir;
  if(dir[0] != '/') {
    printf("dir must start with /"); // FIXME, print to stderr and label internal error
    exit(-1);
  }
  // Skip /
  ptr +=1;
  while(ptr = strstr(ptr, "/")) {
    ptr[0] = 0;
    lazy_mkdir(dir);
    ptr[0] = '/';
    ptr += 1;    
  }
  lazy_mkdir(dir);
}

/**
 * Mounts after creating the mountpoint.
 */ 
void mkmount(const char *src, char *dst, const char *fs, unsigned long flags, const void *data) {
  mkdir_p(dst);
  check("mount1", mount(src, dst, fs, flags, data));
}

/**
 * Bind mount with read-only remount support, FIXME link kernel bug here.
 */
void bind_mount(char *src, char *dst, int read_only) {
  // FIXME consider dropping dst, as dst is always jail_dir(src+1)
  mkmount(src, dst, "bind", MS_BIND | MS_REC, NULL);
  // FIXME security check whether we can steal a read-only mount into rw with another unprivileged container inside.
  if(read_only) {
    check(aasprintf("bind_mount: %s -> %s", src, dst), mount(src, dst, "bind", MS_BIND|MS_REMOUNT|MS_RDONLY, NULL));
  }
}

/**
 * areadlink returns a mallocated buffer with link target. 
 */
char *areadlink(const char *pathname) {
  char *buf = (char *)malloc(PATH_MAX);
  ssize_t len;
  bzero(buf, PATH_MAX);
  len = readlink(pathname, buf, PATH_MAX);
  if(len == PATH_MAX) {
    perror("link name too long");
    exit(-1);
  }
  return buf;
};


char *new_root = "jail/";
char *jail_dir(const char *subdir) {
  return aasprintf("%s/%s", new_root, subdir);
}  

void fork_once() {
  pid_t pid;
  pid = fork();
  
  if(pid < 0) {
    perror("fork");
    exit(pid); // exit errno?
  };
  if(pid > 0) {
    int status;
    waitpid(pid, &status, 0);
    exit(status);
  }
};

void pivot() {
  // Bind root to itself so it becomes a pivotable mount.
  char *pivot = jail_dir(".pivot_root");

  mount(new_root, new_root, "bind", MS_BIND | MS_REC, NULL);
  mkdir_p(pivot);
  check("pivot_root", pivot_root(new_root, pivot));
  check("chdir_root", chdir("/"));
  check("umount_pivot_root", umount2("/.pivot_root", MNT_DETACH));
  check("rmdir_pivot_root", rmdir("/.pivot_root"));
};


// FIXME not sure whether to retain this struct.
struct mnt {
  char *src;
  int flags;
} mnts[] = {
  { "/nix/store", 0},
  { "/nix/var", 0},
  { "/bin", 0},
  { "/usr", 0},
  { "/etc", 0},
  { NULL }
};

void main(int argc, char **argv) {
  uid_t uid = getuid();
  uid_t gid = getgid();
  char *cwd = getcwd(NULL, 0);
  
  if(argc < 3) {
    printf("Usage: dir command...\n"); //FIXME stderr print
    exit(-1);
  }
 
  new_root = mkdtemp(strdup("/tmp/sandbox.XXXXXX"));

  /* 1. Unshare. From here onwards, we have most root-equiv capabilities until we execve, FIXME LWN article here. */
  // FIXME try clone here, just to see if that works too.
  check("unshare", unshare(CLONE_NEWNS | CLONE_NEWUSER | CLONE_NEWPID | CLONE_NEWUTS));
  /* 2. Fork once, so we become the parent of the new process id space and can mount proc */
  fork_once();

  /* 3. Set UID/GID maps, FIXME LWN article here */
  write_file("/proc/self/setgroups", "deny");
  write_file("/proc/self/uid_map", aasprintf("%d %d 1", uid, uid));
  write_file("/proc/self/gid_map", aasprintf("%d %d 1", gid, gid));

  /* 4. Setup dev/tmp/proc */
  mkmount("tmp", jail_dir("tmp"), "tmpfs", MS_NOSUID | MS_STRICTATIME, NULL);
  mkmount("dev", jail_dir("dev"), "tmpfs", MS_NOSUID | MS_STRICTATIME, NULL);
  mkmount("proc", jail_dir("proc"), "proc", MS_NOEXEC | MS_NOSUID | MS_NODEV, NULL);

  // Expose hosts /nix/var, /nix/store, /etc
  for(struct mnt *m = mnts; m->src != NULL; m+=1) {
    bind_mount(m->src, jail_dir((m->src)+1), 1);
  }
  // Expose current working dir from which the sameboxer was invoked.
  bind_mount(argv[1], jail_dir(argv[1]+1), 0);
  // Expose only /run/current-system
  mkdir_p(jail_dir("run"));
  symlink(areadlink("/run/current-system"), jail_dir("run/current-system"));

  /* 6. Pivot into the new root */
  pivot();
  check("chdir_cwd", chdir(cwd));

  /* 7. Exec */  
  check("execve", execv(argv[2], argv + 2));
}
