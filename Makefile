ALL: jailer

install:
	mkdir $(DESTDIR)/bin
	install jailer $(DESTDIR)/bin/jailer
