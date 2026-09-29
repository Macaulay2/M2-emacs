M2 = M2
EMACS = emacs
VERSION := $(shell sed -n 's/^;; Version: //p' M2.el | awk -F. '{printf "%d.%d.%d", $$1, $$2, $$3}')
PACKAGE = M2-$(VERSION)
ARCHIVE_VERSION = $(VERSION).$(shell git rev-list --count HEAD)
PACKAGE_FILES = M2.el M2-mode.el M2-init.el M2-symbols.el M2-emacs-help.txt M2-emacs.m2 M2-session-guide.txt README.md LICENSE

all: package

dist: dist/$(PACKAGE).tar

archive:
	$(MAKE) VERSION=$(ARCHIVE_VERSION) package
	$(EMACS) -Q --batch -l scripts/write-archive.el -- $(ARCHIVE_VERSION) dist

dist/$(PACKAGE).tar: $(PACKAGE_FILES) Makefile
	mkdir -p dist/$(PACKAGE)
	cp $(PACKAGE_FILES) dist/$(PACKAGE)/
	printf '%s\n' '(define-package "M2" "$(VERSION)" "Macaulay2 editing and interactive sessions" '\''((emacs "24.4")))' > dist/$(PACKAGE)/M2-pkg.el
	tar -cf $@ -C dist $(PACKAGE)

check: package
	$(EMACS) -Q --batch -l tests/package-tests.el -- dist/$(PACKAGE).tar

check-archive: archive
	$(EMACS) -Q --batch -l tests/archive-tests.el -- dist

check-lsp: package
	$(EMACS) -Q --batch $(LSP_EMACS_ARGS) -l tests/lsp-tests.el -- dist/$(PACKAGE).tar

update-symbols:
	$(M2) --script generate-symbols.m2

.PHONY: all package archive check check-archive check-lsp update-symbols
