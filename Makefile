ALL: jailer linker

install:
	mkdir $(DESTDIR)/bin
	install jailer $(DESTDIR)/bin/jailer
	install linker $(DESTDIR)/bin/linker
