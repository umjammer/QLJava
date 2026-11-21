.PHONY: all build install uninstall status

all: install

build:
	xcodebuild -project QLJava.xcodeproj -target QLJavaApp -configuration Release SYMROOT=$(CURDIR)/build build -quiet

install:
	./install.sh install

uninstall:
	./install.sh uninstall

status:
	./install.sh status
