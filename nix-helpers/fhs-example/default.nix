{ pkgs ? import <nixpkgs> {} }:

let ibEnv = import ./ib-env.nix;
in ibEnv
