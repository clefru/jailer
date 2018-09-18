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

char *new_root = NULL; // used by jail_dir, set by main()

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
  check("vasprintf", vasprintf(&buf, fmt, args));
  va_end(args);
  return buf;
}

/**
 * Write a string to a file
 */
void write_file(char *path, char *str) {
  int fd = check("open", open(path, O_RDWR));
  int bytes = strlen(str);
  int rc;

  rc = write(fd, str, bytes);
  if(rc != bytes) {
    perror("write");
    exit(-1);
  }
  check("close", close(fd));
}

/**
 * Bind mount with read-only remount support, FIXME link kernel bug here.
 */
void bind_mount(char *src, char *dst, int flags) {
  check(aasprintf("bind_mount: %s -> %s", src, dst), mount(src, dst, "bind", flags & ~MS_RDONLY, NULL));

  if(flags & MS_RDONLY) {
    check(aasprintf("bind_mount_remount: %s -> %s", src, dst), mount(src, dst, "bind", flags, NULL));
  }
}

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
  char *pivot = jail_dir(".pivot_root");

  // Bind root to itself so it becomes a pivotable mount.
  mount(new_root, new_root, "bind", MS_BIND | MS_REC, NULL);
  mkdir(pivot, S_IRWXU);
  check("pivot_root", pivot_root(new_root, pivot));
  check("chdir_root", chdir("/"));
  check("umount_pivot_root", umount2("/.pivot_root", MNT_DETACH));
  check("rmdir_pivot_root", rmdir("/.pivot_root"));
};

void mount_fstab() {
    FILE *fstab = fopen(jail_dir(".fstab"), "r");
    size_t line_len = 0;
    char *line = NULL;
    size_t read_len;

    if(fstab == NULL) {
      perror("Can't open fstab");
      exit(-1);
    }

    while((read_len = getline(&line, &line_len, fstab)) != -1) {
      char *buf = line;
      char *src = strsep(&buf, ":");
      char *target = strsep(&buf, ":");
      char *fs = strsep(&buf, ":");
      int flags = atoi(strsep(&buf, ":"));
      if(flags & MS_BIND) {
	bind_mount(src, jail_dir(target), flags);
      } else {
        check(aasprintf("mount: %s -> %s (%s) %d %s", src, jail_dir(target), fs, flags, buf), mount(src, jail_dir(target), fs, flags, buf));
      }
    }

    fclose(fstab);
    if(line)
      free(line);
}

void main(int argc, char **argv) {
  uid_t uid = getuid();
  uid_t gid = getgid();
  char *sandbox_root;
  char **cmd_args;

  if(argc < 3) {
    fprintf(stderr, "Usage: sandbox_root command...\n");
    exit(-1);
  }

  new_root = argv[1];
  cmd_args = argv+2;

  /* 1. Unshare. From here onwards, we have most root-equiv capabilities until we execve-ed, FIXME LWN article here. */
  // FIXME try clone here, just to see if that works too.
  check("unshare", unshare(CLONE_NEWNS | CLONE_NEWUSER | CLONE_NEWPID | CLONE_NEWUTS));
  /* 2. Fork once, so we become the parent of the new process id space and can mount proc */
  fork_once();

  /* 3. Set UID/GID maps, FIXME LWN article here */
  write_file("/proc/self/setgroups", "deny");
  write_file("/proc/self/uid_map", aasprintf("%d %d 1", uid, uid));
  write_file("/proc/self/gid_map", aasprintf("%d %d 1", gid, gid));

  /* 4. Mount minimal fstab */
  mount_fstab();

  /* 5. Pivot into the new root */
  pivot();

  /* 6. Exec */
  check("execve", execv(cmd_args[0], cmd_args));
}
