###-----------------------------------------------------------------------------
### Application info
###-----------------------------------------------------------------------------

NAME := concuerror

REBAR=$(shell which rebar3 || echo "./rebar3")

.PHONY: default
default bin/$(NAME): $(REBAR)
	$(REBAR) escriptize

MAKEFLAGS += --no-builtin-rules
.SUFFIXES:

###-----------------------------------------------------------------------------
### Rebar
###-----------------------------------------------------------------------------

REBAR_URL="https://s3.amazonaws.com/rebar3/rebar3"

./$(REBAR):
	wget $(REBAR_URL) && chmod +x rebar3

###-----------------------------------------------------------------------------
### Compile
###-----------------------------------------------------------------------------

.PHONY: dev native pedantic
dev native pedantic: $(REBAR)
	$(REBAR) as $@ escriptize

###-----------------------------------------------------------------------------
### Dialyzer
###-----------------------------------------------------------------------------

dialyzer: $(REBAR)
	$(REBAR) dialyzer

###-----------------------------------------------------------------------------
### Test
###-----------------------------------------------------------------------------

CONCUERROR?=$(abspath bin/$(NAME))

.PHONY: tests
tests: bin/$(NAME)
	@$(RM) $@/thediff
	@(cd $@; ./runtests.py)

## -j 1: ensure that the outputs of different suites are not interleaved
.PHONY: tests-real
tests-real: bin/$(NAME)
	@$(RM) $@/thediff
	$(MAKE) -j 1 -C $@ \
		TOP_DIR=$(abspath .) \
		CONCUERROR=$(CONCUERROR) \
		DIFFER=$(abspath tests/differ) \
		DIFFPRINTER=$(abspath $@/thediff)

###-----------------------------------------------------------------------------
### Cover
###-----------------------------------------------------------------------------

.PHONY: cover
cover: cover/data bin/$(NAME)
	$(RM) $</*
	$(MAKE) tests tests-real \
		CONCUERROR=$(abspath priv/concuerror) \
		CONCUERROR_COVER=$(abspath cover/data)
	cd cover; ./cover-report data

cover/data:
	@printf " MKDIR $@\n"
	@mkdir -p $@

###-----------------------------------------------------------------------------
### Clean
###-----------------------------------------------------------------------------

.PHONY: clean
clean: $(REBAR)
	$(REBAR) clean --all

.PHONY: distclean
distclean:
	$(RM) bin/$(NAME)
	$(RM) -r _build
	$(RM) ./$(REBAR)

.PHONY: cover-clean
cover-clean:
	$(RM) -r cover/data
	$(RM) cover/*.COVER.html

.PHONY: maintainer-clean
maintainer-clean: distclean cover-clean
