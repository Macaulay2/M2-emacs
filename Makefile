M2 = M2

all: M2-symbols.el.gz

M2-symbols.el.gz: M2-symbols.el
	gzip -nkf9 $<

M2-symbols.el: generate-grammar.m2 M2-symbols.el.in
	$(M2) --script generate-grammar.m2

clean:
	rm -f M2-symbols.el

.PHONY: all clean
