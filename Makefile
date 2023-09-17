PREFIX = $(HOME)/.local/bin

install:
	mkdir -vp $(PREFIX)
	chmod 700 jackett_cli.sh
	ln -vrsf $(PREFIX)/jackett_cli

uninstall: uninstall
	rm -vf $(PREFIX)/jackett_cli
