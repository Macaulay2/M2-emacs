M2 = M2
VERSION := $(shell sed -n 's/^;; Version: //p' M2.el | awk -F. '{printf "%d.%d.%d", $$1, $$2, $$3}')
PACKAGE = M2-$(VERSION)
PACKAGE_FILES = M2.el M2-mode.el M2-init.el M2-symbols.el M2-emacs-help.txt M2-emacs.m2 README.md LICENSE

all: dist

dist: dist/$(PACKAGE).tar

dist/$(PACKAGE).tar: $(PACKAGE_FILES) Makefile
	mkdir -p dist/$(PACKAGE)
	cp $(PACKAGE_FILES) dist/$(PACKAGE)/
	printf '%s\n' '(define-package "M2" "$(VERSION)" "Macaulay2 editing and interactive sessions" '\''((emacs "24.4")))' > dist/$(PACKAGE)/M2-pkg.el
	tar -cf $@ -C dist $(addprefix $(PACKAGE)/,$(PACKAGE_FILES) M2-pkg.el)

update-symbols:
	$(M2) --script generate-symbols.m2

.PHONY: all dist update-symbols
