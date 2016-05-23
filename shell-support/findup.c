/*
 * Copyright 2016, Clemens Fruhwirth <clemens@endorphin.org>
 * Finds the first file by a given name ascending from the current working dir upwards.
 */
#define _GNU_SOURCE
#include <string.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <sys/stat.h>
#include <sys/types.h>

char *target;

void stater(char *dir)
{
  char *path;
  struct stat sbuf;

  asprintf(&path,"%s/%s", dir, target);
  if(stat(path, &sbuf) == 0) {
    printf("%s\n", path);
    exit(0);
  }
  free(path);
}

void ascend_dir(char *dir) {
  char *ptr;
  if(dir[0] != '/') {
    printf("dir must start with /"); // FIXME, print to stderr and label internal error
    exit(-1);
  }
  ptr = dir + strlen(dir) - 1;
  if(*ptr != '/') {
    stater(dir);
  }
  while(ptr >= dir) {
    if(*ptr == '/') {
      *ptr = '\0';
      stater(dir);
    }
    ptr--;
  }
}

void main(int argc, char **argv)
{
  char *pwd = getcwd(NULL, 0);
  if (argc < 2) {
    fprintf(stderr, "Usage %s FILE\n", argv[0]);
    exit(1);
  }
  target = argv[1];
  ascend_dir(pwd);
  free(pwd);
  exit(1);
}
