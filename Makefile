TOPDIR = ../..
include $(TOPDIR)/config.Makefile
include $(TOPDIR)/Makeconf


ELFILES = M2-mode.el M2.el
ALLFILES = makesyms.m2 Makefile $(ELFILES) emacs-hlp.txt emacs.m2

all:: M2-symbols.el

M2-symbols.el : ../cache/Macaulay2-doc makesyms.m2
	../bin/M2 -q -silent makesyms.m2 '-e exit 0'

all:: emacs-hlp.txt
emacs-hlp.txt: ../cache/Macaulay2-doc makehlp.m2
	../bin/M2 -q -silent makehlp.m2 '-e exit 0'

all:: emacs.m2
emacs.m2: ../cache/Macaulay2-doc makem2.m2
	../bin/M2 -q -silent makem2.m2 '-e exit 0'

allfiles : Makefile; 
	echo $(ALLFILES) | tr ' ' '\012' >allfiles

clean:
	rm -f M2-symbols.el emacs-hlp.txt emacs.m2

