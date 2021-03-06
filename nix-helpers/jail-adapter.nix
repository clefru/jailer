let pkgs = import <nixpkgs> {};
    jailer = import ../default.nix;
    shell = "/run/current-system/sw/bin/sh";
    mount_flags = ''
      MS_ACTIVE=0x40000000
      MS_ASYNC=0x1
      MS_BIND=0x1000
      MS_DIRSYNC=0x80
      MS_INVALIDATE=0x2
      MS_I_VERSION=0x800000
      MS_KERNMOUNT=0x400000
      MS_MANDLOCK=0x40
      MS_MOVE=0x2000
      MS_NOATIME=0x400
      MS_NODEV=0x4
      MS_NODIRATIME=0x800
      MS_NOEXEC=0x8
      MS_NOSUID=0x2
      MS_NOUSER=0x80000000
      MS_POSIXACL=0x10000
      MS_PRIVATE=0x40000
      MS_RDONLY=0x1
      MS_REC=0x4000
      MS_RELATIME=0x200000
      MS_REMOUNT=0x20
      MS_RMT_MASK=0x800051
      MS_SHARED=0x100000
      MS_SILENT=0x8000
      MS_SLAVE=0x80000
      MS_STRICTATIME=0x1000000
      MS_SYNC=0x4
      MS_SYNCHRONOUS=0x10
      MS_UNBINDABLE=0x20000
    '';
    enterJail = pkgs.writeScript "enter-jail" ''#!${shell}
      SANDBOX_ROOT=$(mktemp -d /tmp/sandbox.XXXXXXX)
      (cd $SANDBOX_ROOT

      ${mount_flags}

      mkdir -p run
      cp -a /run/current-system run
      mkdir -p run/user/$UID

      # Note on security: Only binds mounts and file systems with FS_USERNS_MOUNT
      # set in .fs_flags can be mounted from user-space containers.
      #
      # https://github.com/torvalds/linux/search?utf8=%E2%9C%93&q=FS_USERNS_MOUNT&type=

      mkdir -p nix/store; echo /nix/store:/nix/store:bind:$(($MS_BIND | $MS_RDONLY | $MS_REC)) >> .fstab
      mkdir -p nix/var; echo /nix/var:/nix/var:bind:$(($MS_BIND | $MS_RDONLY | $MS_REC)) >> .fstab

      # Note that
      #   mkdir -p foo;     echo ...:/foo:... >> .fstab
      #   mkdir -p foo/bar; echo ...:/foo/bar:... >> .fstab
      # potentially doesn't work as the second mkdir is ineffective as
      # it gets shadowed when foo gets mounted. Unless foo has a bar
      # subdir, this second mount will fail.

      mkdir -p host/etc; echo /etc:/host/etc:bind:$(($MS_BIND | $MS_RDONLY | $MS_REC)) >> .fstab
      mkdir -p host/bin; echo /bin:/host/bin:bind:$(($MS_BIND | $MS_RDONLY | $MS_REC)) >> .fstab
      mkdir -p host/usr; echo /usr:/host/usr:bind:$(($MS_BIND | $MS_RDONLY | $MS_REC)) >> .fstab
      mkdir -p host/tmp/.X11-unix; echo /tmp/.X11-unix:/host/tmp/.X11-unix:bind:$(($MS_BIND | $MS_REC)) >> .fstab

      mkdir -p tmp; echo tmp:/tmp:tmpfs:$(($MS_NOSUID | $MS_STRICTATIME)) >> .fstab
      mkdir -p proc; echo proc:/proc:proc:$(($MS_NOSUID | $MS_NOEXEC | $MS_NODEV)) >> .fstab

      # /dev: Only selectively include devices. Not exposed /dev.
      mkdir -p dev
      for i in null zero ptmx tty random urandom full; do
        # Bind-mounting a file needs an inode, therefore we create an
        # empty file at the destination. This trick is stolen from
        # nix/src/libstore/build.cc. As bind shadows the complete inode,
        # the empty files turn into device nodes.
        touch dev/$i
        echo /dev/$i:/dev/$i:bind:$(($MS_BIND)) >> .fstab
      done

      # Bind mount the root of the sandbox.
      mkdir -p ./$1; echo $1:$1:bind:$(($MS_BIND | $MS_REC)) >> .fstab

      cp ''${XAUTHORITY:-$HOME/.Xauthority} .Xauthority)

      exec ${jailer}/bin/jailer $SANDBOX_ROOT $2 $PWD
    '';
    setShellHook = enterJailCmd: inJailCmd: dir: drv:
      # FIXME: The following kills the shell executing the run hook with an exec.
      # See if we can be more cooperative in fiddling with the $cmd variables and
      # potentially support --run, and --cmd args for nix-shell.
      pkgs.stdenv.lib.overrideDerivation drv (oldAttrs: {
	      shellHook = ''exec ${enterJailCmd} ${builtins.toString dir} ${inJailCmd}'';
      });
    zshrc = originalShellHook: pkgs.writeText "zshrc" ''
PS1="# "
chpwd() {
	 case $PWD/ in
	   $CAGE/*)
	   ;;
	   *)
	     if [ -n "$CAGEFILE" ]; then
	       echo $PWD > $CAGEFILE
	       exit 0
	     fi
	 esac
}
${originalShellHook}
'';
    inJail = opt: drv: pkgs.writeScript "in-jail" ''#!${shell}
      ${if opt.cage
           then ''export CAGEFILE=$(mktemp -u /tmp/cage.XXXXXXX)
                  mknod $CAGEFILE p
                  (cat $CAGEFILE 1>&3) &''
           else ""}
      exec 3>&-
      export ZDOTDIR=$(mktemp -d /tmp/zroot.XXXXX)
      export CAGE=${builtins.toString opt.sandboxRoot}
      # TODO: Fake passwd entry for home as many programs go for ~$USER instead of $HOME. :/
      # FIXME: Fix the shell prompt to print ~ at the old $HOME.
      ${if opt.sandboxIsHome
           then ''export HOME=$CAGE''
           else ""}
      ln -s ${zshrc (if drv?shellHook then drv.shellHook else "")} $ZDOTDIR/.zshrc
      ${if opt.fhs != {}
           then ''${jailer}/bin/linker ${opt.fhs} /''
           else ''ln -s /host/etc /etc
                  ln -s /host/bin /bin
                  ln -s /host/usr /usr''}
      source /etc/profile
      ln -s /host/tmp/.X11-unix /tmp/.X11-unix
      ${if opt.X11
           then ''export XAUTHORITY=/.Xauthority''
           else ''rm /.Xauthority''}

      # chdir into the directory handed over to us by enterJail
      cd $1
      exec /run/current-system/sw/bin/zsh'';
    defaults = { fhs = {}; sandboxIsHome = false; cage = false; X11 = false; };
    addDefaults = opt: pkgs.stdenv.lib.zipAttrsWith (name: values: builtins.head values) [opt defaults];
in {
  # Call sandbox with the following set:
  # {
  #   sandboxRoot: set this to the root of the sandbox. Best is to use ./. in the calling jail.nix file.
  #   drv: set to the derivation which is used as the basis of the shellHook. This defines the environment of the spanned shell.
  #   fhs: set to a derivation to link into / of the sandbox. Mostly useful for using FHS style setup at /. Otherwise set to {} (default).
  #   cage: set to true, if you want the shell to exit if the users chdir-s outside the sandboxRoot. False (default).
  #   X11: set to true, if you want X11 access. False (default).
  #   sandboxIsHome: set to true, if you want $HOME set to sandboxRoot. False (default).
  # }
  sandbox = opt: setShellHook enterJail (inJail (addDefaults opt) opt.drv) opt.sandboxRoot opt.drv;
}
