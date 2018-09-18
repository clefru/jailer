function pwdnix_jail_enter() {
    if [ -n "$TRUSTED_KEY" ]; then
      JAIL_NIX=$(findup jail.nix)
      if [ -n "$JAIL_NIX" ]; then
	  # The protocol between this helper and the shell spawned is that
	  # this shell will chdir to a dir written to file descriptor 3
	  # by nix-shell or its subprocesses.
	  CAGEFILE=$(mktemp /tmp/cage.XXXXXX)
	  exec 3> $CAGEFILE

	  nix-shell $JAIL_NIX
	  NEWDIR=$(cat $CAGEFILE)
	  rm $CAGEFILE
	  if [ -n "$NEWDIR" ]; then
	      cd $NEWDIR
	  else
	      echo "pwdjail-nix: Sub-shell quit without giving a target directory. Returning you to $OLDPWD."
	      cd $OLDPWD
	  fi
      fi
   fi
}

chpwd_functions=(${chpwd_functions[@]} "pwdnix_jail_enter")
