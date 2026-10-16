M2 = M2

all:

update-symbols:
	$(M2) --script generate-symbols.m2

update-operators:
	$(M2) --script generate-operators.m2

update: update-symbols update-operators

.PHONY: all update update-symbols update-operators
