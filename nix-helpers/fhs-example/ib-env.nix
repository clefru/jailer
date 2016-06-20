let nixpkgs = import <nixpkgs> {};
    userFHSEnv = nixpkgs.callPackage <nixpkgs/pkgs/build-support/build-fhs-userenv> {
     ruby = nixpkgs.ruby_2_1_3;
    };

    buildFHSEnv = nixpkgs.callPackage <nixpkgs/pkgs/build-support/build-fhs-chrootenv/env.nix> {
      nixpkgs      = nixpkgs;
      nixpkgs_i686 = nixpkgs.pkgsi686Linux;
    };
    buildFHSUserEnv = args: userFHSEnv {
      env = buildFHSEnv (removeAttrs args [ "runScript" "extraBindMounts" "extraInstallCommands" "meta" ]);
      runScript = args.runScript or "bash";
      extraBindMounts = args.extraBindMounts or [];
      extraInstallCommands = args.extraInstallCommands or "";
      importMeta = args.meta or {};
    };
in buildFHSEnv {
    name = "ib";
    targetPkgs = pkgs: (with pkgs;
    [ 
      openjdk
      which
      firefox
    ]) ++ (with pkgs.xorg;
    [ libX11
      libXcursor
      libXrandr
      libXext
      libXtst
      libXi
      libXrender
    ]) ++ [
      pkgs.acl
      pkgs.attr
      pkgs.bashInteractive # bash with ncurses support
      pkgs.bzip2
      pkgs.coreutils
      pkgs.cpio
      pkgs.curl
      pkgs.diffutils
      pkgs.findutils
      pkgs.gawk
      pkgs.glibc # for ldd, getent
      pkgs.gnugrep
      pkgs.gnupatch
      pkgs.gnused
      pkgs.gnutar
      pkgs.gzip
      pkgs.xz
      pkgs.less
      pkgs.libcap
      pkgs.nano
      pkgs.ncurses
      pkgs.netcat
      pkgs.perl
      pkgs.procps
      pkgs.rsync
      pkgs.strace
      pkgs.su
      pkgs.time
      pkgs.texinfoInteractive
      pkgs.utillinux
      pkgs.xterm
    ];
    multiPkgs = pkgs: [ ];
}
