verify_signature() {
    local file=$1 sigfile=$2 trusted=$3 out=
    if out=$(gpg2 --status-fd 1 --verify $sigfile $file 2>/dev/null) &&
       echo "$out" | grep -qs "^\[GNUPG:\] VALIDSIG $trusted " &&
       echo "$out" | grep -qs "^\[GNUPG:\] TRUST_ULTIMATE"; then
	return 0
    else
	echo "$out" >&2
	return 1
    fi
}

chpwd() {
    if [ -n "$TRUSTED_KEY" ]; then
      SHELL_NIX=$(findup shell.nix)
      if [ -n "$SHELL_NIX" ]; then
	  if [ -e "$SHELL_NIX".sig ]; then
	      if verify_signature $SHELL_NIX $SHELL_NIX.sig $TRUSTED_KEY; then
		  echo "good sig found."
		  # The protocol between this helper and the shell spawned is that
		  # this shell will chdir to a dir written to file descriptor 3
		  # by nix-shell or its subprocesses.
		  CAGEFILE=$(mktemp /tmp/cage.XXXXXX)
		  exec 3> $CAGEFILE

		  nix-shell $SHELL_NIX
		  NEWDIR=$(cat $CAGEFILE)
		  rm $CAGEFILE
		  if [ -n "$NEWDIR" ]; then
		     cd $NEWDIR
		  else
		      echo "Returning to original dir."
		      cd $OLDPWD
		  fi
	      else
		  echo "signature verification failed. NOT IN SHELL".
	      fi
	  else
	      echo "shell.nix found but no shell.nix.sig."
	  fi
      fi
   fi
}
