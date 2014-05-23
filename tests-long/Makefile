SUBDIRS=$(patsubst %Makefile,%,$(wildcard suites/*/Makefile))

.PHONY: all $(SUBDIRS)

all: $(SUBDIRS)

$(SUBDIRS): 
	$(MAKE) -C $@