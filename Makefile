PREFIX = $(HOME)/.local/bin

install:
	mkdir -vp $(PREFIX)
	install -m 700 jackett_cli.sh $(PREFIX)/jackett_cli
	@echo "*** Installed"
	@echo "*** Now check if $(PREFIX) is in your \$$PATH"

uninstall: uninstall
	rm -vf $(PREFIX)/jackett_cli
