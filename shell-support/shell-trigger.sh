chpwd() {
    SHELL_NIX=$(findup shell.nix)
    if [ -n "$SHELL_NIX" ]; then
	# The protocol between this helper and the shell spawned is that
	# this shell will chdir to a dir written to file descriptor 3
	# by nix-shell or its subprocesses.
	CAGEFILE=$(mktemp /tmp/cage.XXXXXX)
	exec 3> $CAGEFILE

	nix-shell $SHELL_NIX

	NEWDIR=$(cat $CAGEFILE)
	rm $CAGEFILE
	[ -n "$NEWDIR" ] && cd $NEWDIR
    fi
}
