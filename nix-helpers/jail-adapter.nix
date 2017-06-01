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

      mkdir -p nix/store; echo /nix/store:/nix/store:bind:$(($MS_BIND | $MS_RDONLY | $MS_REC)) >> .fstab
      mkdir -p nix/var; echo /nix/var:/nix/var:bind:$(($MS_BIND | $MS_RDONLY | $MS_REC)) >> .fstab
      mkdir -p host;
      mkdir -p host/etc; echo /etc:/host/etc:bind:$(($MS_BIND | $MS_RDONLY | $MS_REC)) >> .fstab
      mkdir -p host/bin; echo /bin:/host/bin:bind:$(($MS_BIND | $MS_RDONLY | $MS_REC)) >> .fstab
      mkdir -p host/usr; echo /usr:/host/usr:bind:$(($MS_BIND | $MS_RDONLY | $MS_REC)) >> .fstab

      mkdir -p tmp; echo tmp:/tmp:tmpfs:$(($MS_NOSUID | $MS_STRICTATIME)) >> .fstab

      # We can't effectively mkdir sandbox/tmp/.X11-unix, as its
      # parent sandbox/tmp will be covered by the tmpfs mount
      # point. That's why we mount to /host/tmp/.X11-unix and link it
      # in the jail script.
      mkdir -p host/tmp/.X11-unix; echo /tmp:/host/tmp/.X11-unix:bind:$(($MS_BIND | $MS_REC)) >> .fstab

      # We can't mount devtmpfs. We can't even mount /dev without
      # MS_REC. Best we can do is shadow out sensitive parts like
      # /dev/shm, /dev/mqueue, /dev/hugepages. The jail can't unmount
      # those to recover the original mount point.
      #mkdir -p dev; echo dev:/dev:devtmpfs:$(($MS_NOSUID | $MS_STRICTATIME)) >> .fstab
      mkdir -p dev; echo /dev:/dev:bind:$(($MS_BIND | $MS_REC | $MS_RDONLY)) >> .fstab
      mkdir -p dev/shm; echo tmp:/dev/shm:tmpfs:$(($MS_NOSUID | $MS_STRICTATIME)) >> .fstab
      mkdir -p dev/mqueue; echo tmp:/dev/mqueue:tmpfs:$(($MS_NOSUID | $MS_STRICTATIME)) >> .fstab
      mkdir -p dev/hugepages; echo tmp:/dev/hugepages:tmpfs:$(($MS_NOSUID | $MS_STRICTATIME)) >> .fstab

      mkdir -p proc; echo proc:/proc:proc:$(($MS_NOSUID | $MS_NOEXEC | $MS_NODEV)) >> .fstab
      mkdir -p ./$1; echo $1:$1:bind:$(($MS_BIND | $MS_REC)) >> .fstab

      cp $HOME/.Xauthority .)

      exec ${jailer}/bin/jailer $SANDBOX_ROOT $2 $PWD
    '';
    setShellHook = enterJail: inJail: dir: drv:
      # FIXME: The following kills the shell executing the run hook with an exec.
      # See if we can be more cooperative in fiddling with the $cmd variables and
      # potentially support --run, and --cmd args for nix-shell.
      pkgs.stdenv.lib.overrideDerivation drv (oldAttrs: {
	shellHook = ''exec ${enterJail} ${builtins.toString dir} ${inJail}'';
      });
    zshrcDirLocked = pkgs.writeText "zshrc" ''
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
       '';
    inJail = opt: pkgs.writeScript "in-jail" ''#!${shell}
      ${if opt.cage
           then ''export CAGEFILE=$(mktemp -u /tmp/cage.XXXXXXX)
                  mknod $CAGEFILE p
                  (cat $CAGEFILE 1>&3) &''
           else ""}
      exec 3>&-
      export ZDOTDIR=$(mktemp -d /tmp/zroot.XXXXX)
      export CAGE=${builtins.toString opt.dir}
      ln -s ${zshrcDirLocked} $ZDOTDIR/.zshrc
      ${if opt.fhs != {}
           then ''${jailer}/bin/linker ${opt.fhs} /
                ''
           else ""}
      [ -e /etc ] || ln -s /host/etc /etc
      [ -e /bin ] || ln -s /host/bin /bin
      [ -e /usr ] || ln -s /host/usr /usr
      source /etc/profile
      ln -s /host/tmp/.X11-unix /tmp/.X11-unix
      ${if opt.X11
           then ''export XAUTHORITY=/.Xauthority''
           else ''rm /.Xauthority''}

      # chdir into the directory handed over to us by enterJail
      cd $1
      exec /run/current-system/sw/bin/zsh'';
in {
  # A simple sandbox is one where we can freely navigate around in. The jail should be left by exiting the shell. Entry should happen with just nix-shell jail.nix.
  simpleSandbox = dir: drv: (
    setShellHook
      enterJail
      (inJail { dir = dir; cage = false; X11 = false; fhs = {}; })
      dir
      drv);

  # A directory locked sandbox spawns a shell, which will exit if dir is not a prefix of $PWD. This is meant to be activated with shell-supported.
  dirLockedSandbox = dir: drv: setShellHook enterJail (inJail { dir = dir; cage = true; X11 = false; fhs = {}; } ) dir drv;

  # Same as dir locked sandbox but also creates an FHS environment. This is meant to be activated with shell-supported.
  fhsSandbox = dir: drv: setShellHook enterJail (inJail { dir = dir; fhs = drv; cage = true; X11 = false; }) dir drv;
  fhsSandboxUnlocked = dir: drv: setShellHook enterJail (inJail { dir = dir; fhs = drv; cage = false; X11 = false; }) dir drv;
}
