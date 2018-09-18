all: jailer linker shell-support/findup

install:
	install -d $(DESTDIR)/lib/jailer $(DESTDIR)/bin
	install jailer $(DESTDIR)/bin/jailer
	install linker $(DESTDIR)/bin/linker
	install shell-support/findup $(DESTDIR)/bin/findup
	install shell-support/shell-trigger.sh $(DESTDIR)/lib/jailer
	install nix-helpers/jail-adapter.nix $(DESTDIR)/lib/jailer
	ln -s . $(DESTDIR)/lib/jailer/nix-helpers
# FIXME the seds are too crude
	sed -i -e 's#findup jail.nix#$(DESTDIR)/bin/findup jail.nix#' $(DESTDIR)/lib/jailer/shell-trigger.sh
	sed -i -e 's#import ../default.nix#$(DESTDIR)#' $(DESTDIR)/lib/jailer/jail-adapter.nix
