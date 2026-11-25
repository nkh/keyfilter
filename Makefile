PERL  = perl
PROVE = prove

.PHONY: all check test

all: check

check:
	$(PERL) -c keyfilter

test:
	$(PROVE) t/
