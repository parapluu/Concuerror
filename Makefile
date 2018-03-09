###-----------------------------------------------------------------------------
### Application info
###-----------------------------------------------------------------------------

NAME := concuerror
VERSION := 0.19

.PHONY: default
default: all

###-----------------------------------------------------------------------------
### Files
###-----------------------------------------------------------------------------

DEPS = getopt/ebin/getopt
DEPS_BEAMS=$(DEPS:%=deps/%.beam)

SOURCES = $(wildcard src/*.erl)
MODULES = $(SOURCES:src/%.erl=%)
BEAMS = $(MODULES:%=ebin/%.beam)

SHA_HRL = src/concuerror_sha.hrl
VERSION_HRL = src/concuerror_version.hrl

GENERATED_HRLS = $(SHA_HRL) $(VERSION_HRL)

###-----------------------------------------------------------------------------
### Compile
###-----------------------------------------------------------------------------

.PHONY: all dev native
all dev native: $(DEPS_BEAMS) $(BEAMS) $(NAME)

ERL_COMPILE_FLAGS := \
	+debug_info \
	+warn_export_vars \
	+warn_unused_import \
	+warn_missing_spec \
	+warn_untyped_record \
	+warnings_as_errors

dev: ERL_COMPILE_FLAGS += -DDEV=true
dev: VERSION := $(VERSION)-dev

native: ERL_COMPILE_FLAGS += +native
native: VERSION := $(VERSION)-native

$(NAME): Makefile
	@$(RM) $@
	@printf " GEN  $@\n"
	@printf -- "#!/usr/bin/env sh\n" >> $@
	@printf -- "SCRIPTPATH=\"\$$( cd \"\$$(dirname \"\$$0\")\" ; pwd -P )\"\n" >> $@
	@printf -- "printf \"\nWARNING! Concuerror/concuerror will be removed in next version. Use Concuerror/bin/concuerror instead!\n\"\n" >> $@
	@printf -- "\$$SCRIPTPATH/bin/concuerror \$$@" >> $@
	@chmod u+x $@

###-----------------------------------------------------------------------------

-include $(MODULES:%=ebin/%.Pbeam)

ebin/%.Pbeam: src/%.erl $(GENERATED_HRLS) | ebin
	@erlc -o ebin -MF $@.tmp -MG $<
	@cmp -s $@.tmp $@ > /dev/null || (printf " DEPS  $<\n" && cp $@.tmp $@)
	@$(RM) $@.tmp

ebin/%.beam: src/%.erl | ebin
	@printf " ERLC  $<\n"
	@erlc $(ERL_COMPILE_FLAGS) -o ebin $<

###-----------------------------------------------------------------------------

$(SHA_HRL): version
	@printf -- "-define(GIT_SHA, " > $@.tmp
	@git rev-parse --short --sq HEAD >> $@.tmp
	@printf ").\n" >> $@.tmp
	@cmp -s $@.tmp $@ > /dev/null || (printf " GEN  $@\n" && cp $@.tmp $@)
	@$(RM) $@.tmp

$(VERSION_HRL): version
	@src/versions $(VERSION) >> $@.tmp
	@cmp -s $@.tmp $@ > /dev/null || (printf " GEN  $@\n" && cp $@.tmp $@)
	@$(RM) $@.tmp

.PHONY: version
version:

###-----------------------------------------------------------------------------

ebin cover/data:
	@printf " MKDIR $@\n"
	@mkdir -p $@

###-----------------------------------------------------------------------------
### Dependencies
###-----------------------------------------------------------------------------

%/ebin/getopt.beam: %/.git
	$(MAKE) -C $(dir $<)
	$(RM) -r $(dir $<).rebar

deps/%/.git:
	git submodule update --init

###-----------------------------------------------------------------------------
### Dialyzer
###-----------------------------------------------------------------------------

PLT=.$(NAME)_plt

DIALYZER_APPS = erts kernel stdlib compiler crypto tools
DIALYZER_FLAGS = -Wunmatched_returns -Wunderspecs

.PHONY: dialyze
dialyze: all $(PLT)
	dialyzer --add_to_plt --plt $(PLT) $(DEPS_BEAMS)
	dialyzer --plt $(PLT) $(DIALYZER_FLAGS) ebin/*.beam

$(PLT):
	dialyzer --build_plt --output_plt $@ --apps $(DIALYZER_APPS) $^

###-----------------------------------------------------------------------------
### Testing
###-----------------------------------------------------------------------------

.PHONY: tests
tests: all
	@$(RM) $@/thediff
	@(cd $@; ./runtests.py)

## the -j 1 below is so that the outputs of tests are not shown interleaved
.PHONY: tests-real
tests-real: all
	@$(RM) $@/thediff
	$(MAKE) -j 1 -C $@ \
		CONCUERROR=$(abspath bin/concuerror) \
		DIFFER=$(abspath tests/differ) \
		DIFFPRINTER=$(abspath $@/thediff)

%/scenarios.beam: %/scenarios.erl
	erlc -o $(@D) $<

###-----------------------------------------------------------------------------
### Cover
###-----------------------------------------------------------------------------

.PHONY: cover
cover: cover/data
	$(RM) $</*
	export CONCUERROR_COVER=$(abspath cover/data); $(MAKE) tests tests-real
	cd cover; ./get-coveralls; ./cover-report data > /dev/null

###-----------------------------------------------------------------------------
### Travis
###-----------------------------------------------------------------------------

.PHONY: travis_has_latest_otp_version
travis_has_latest_otp_version:
	./.travis/$@

###-----------------------------------------------------------------------------
### Clean
###-----------------------------------------------------------------------------

.PHONY: clean
clean:
	$(RM) $(NAME)
	$(RM) -r ebin

.PHONY: distclean
distclean: clean dialyzer-clean
	$(RM) $(GENERATED_HRLS)
	$(RM) -r deps/*
	git checkout -- deps

.PHONE: dialyzer-clean
dialyzer-clean:
	$(RM) $(PLT)

cover-clean:
	$(RM) -r cover/data
	$(RM) cover/*.COVER.html

.PHONY: maintainer-clean
maintainer-clean: distclean dialyzer-clean cover-clean
