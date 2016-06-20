/*
 * Copyright 2016, Clemens Fruhwirth <clemens@endorphin.org>
 * Recursively symlinks the content of a source dir into a target dir.
 *
 */

#define _GNU_SOURCE
#include <dirent.h>
#include <unistd.h>
#include <stdio.h>
#include <stdarg.h>
#include <string.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <errno.h>
#include <stdlib.h>

int is_dir(char *path) {
  struct stat buf;
  int rc = stat(path, &buf);
  if(rc == 0) {
    if(S_ISDIR(buf.st_mode)) {
      return 1;
    } else {
      return 0;
    }
  } else if(errno == ENOENT) {
    return 0;
  } else {
    perror("stat error");
    exit(-1);
  }
}

int exists(char *path) {
  struct stat buf;
  int rc = stat(path, &buf);
  if(rc == 0) {
    return 1;
  } else if(errno == ENOENT) {
    return 0;
  } else {
    perror("stat error");
    exit(-1);
  }
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

void symlinkx(char *sourcePath, char *targetPath) {
  int rc;
  printf("%s -> %s\n", sourcePath, targetPath);
  rc = symlink(sourcePath, targetPath);
  if(rc < 0) {
    perror("symlink");
  }
}

void link_source(char *source, char *target) {
  DIR *dp;
  struct dirent *ep;
  dp = opendir(source);

  if(dp != NULL) {
    while(ep = readdir(dp)) {
      if(!strcmp(ep->d_name, ".") || !strcmp(ep->d_name, ".."))
	continue;

      char *sourcePath = aasprintf("%s/%s", source, ep->d_name);
      char *targetPath = aasprintf("%s/%s", target, ep->d_name);

      if(is_dir(sourcePath)) {
	if(exists(targetPath)) {
	  if(is_dir(targetPath)) {
	    link_source(sourcePath, targetPath);
	  } else {
	    printf("%s exists but isn't a directory as %s.\n", targetPath, sourcePath);
	  }
	} else {
	  symlinkx(sourcePath, targetPath);
	}
      } else {
	symlinkx(sourcePath, targetPath);
      }
      free(sourcePath);
      free(targetPath);
    }
    closedir(dp);
  } else perror ("Couldn't open the directory");
}

void main(int argc, char **argv) {
  if(argc < 3) {
    fprintf(stderr, "Usage: linker <sourcedir> <targetdir>\n");
    exit(-1);
  }
  link_source(argv[1], argv[2]);
}
