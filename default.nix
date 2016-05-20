let pkgs = import <nixpkgs> {};
in pkgs.stdenv.mkDerivation {
  name = "jailer";
  srcs = [./Makefile ./jailer.c];
  unpackCmd = "mkdir -p src; cp -a $curSrc src/$\{curSrc#*-\}";
  installFlags = "DESTDIR=\${out}";
}