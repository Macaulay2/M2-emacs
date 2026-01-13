M2 = M2

all:

update-symbols:
	$(M2) --script generate-symbols.m2

.PHONY: all update-symbols
