{ pkgs ? import <nixpkgs> {} }:

pkgs.stdenv.mkDerivation {
  name = "jailer";
  src = ./.;
  installFlags = "DESTDIR=\${out}";
}
