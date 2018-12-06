DESTDIR ?= /
PREFIX ?= /usr
TARGET ?= $(PREFIX)/share/

all:

install:
	install -m 0755 -d $(DESTDIR)/$(TARGET)/clr-k8s-examples
	cp -r clr-k8s-examples/* $(DESTDIR)/$(TARGET)/clr-k8s-examples/
