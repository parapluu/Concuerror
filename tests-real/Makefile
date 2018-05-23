SUBDIRS=$(patsubst %Makefile,%,$(wildcard suites/output/Makefile))

.PHONY: all $(SUBDIRS)

all: $(SUBDIRS)

$(SUBDIRS):
	$(MAKE) -C $@
