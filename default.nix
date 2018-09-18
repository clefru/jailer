let pkgs = import <nixpkgs> {};
in pkgs.stdenv.mkDerivation {
  name = "jailer";
  src = ./.;
  installFlags = "DESTDIR=\${out}";
}
