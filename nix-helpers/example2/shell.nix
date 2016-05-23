let pkgs = import <nixpkgs> {};
    drv = pkgs.runCommand "jailed-shell" { } ''exit 1'';
in (import ../jail-adapter.nix).dirLockedSandbox ./. drv
