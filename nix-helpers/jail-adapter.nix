let pkgs = import <nixpkgs> {};
    jailer = import ../default.nix;
    setShellHook = prepare: dir: drv:
      # FIXME: The following kills the shell executing the run hook with an exec.
      # See if we can be more cooperative in fiddling with the $cmd variables and
      # potentially support --run, and --cmd args for nix-shell.
      pkgs.stdenv.lib.overrideDerivation drv (oldAttrs: {
        shellHook = ''exec ${jailer}/bin/jailer ${builtins.toString dir} ${prepare}'';
      });
in {
  dirLockedSandbox = dir: drv:
    let zshrc = pkgs.writeText "zshrc" ''
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
	prepare = pkgs.writeScript "prepare" ''#!/bin/sh
	   export CAGEFILE=$(mktemp -u /tmp/cage.XXXXXXX)
	   mknod $CAGEFILE p
	   mknod /dev/null c 1 3
	   (cat $CAGEFILE 1>&3) &
	   exec 3>&-
	   export CAGE=${builtins.toString dir}

	   export ZDOTDIR=$(mktemp -d /tmp/zroot.XXXXX)
	   ln -s ${zshrc} $ZDOTDIR/.zshrc

	   exec /run/current-system/sw/bin/zsh'';
     in setShellHook prepare dir drv;

   simpleSandbox = dir: drv:
     let prepare = pkgs.writeScript "prepare" ''#!/bin/sh
	   exec 3>&-

	   export ZDOTDIR=$(mktemp -d /tmp/zroot.XXXXX)
	   touch $ZDOTDIR/.zshrc

	   exec /run/current-system/sw/bin/zsh'';
     in setShellHook prepare dir drv;
}