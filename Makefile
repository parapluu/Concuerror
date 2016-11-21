###-----------------------------------------------------------------------------
### Application info
###-----------------------------------------------------------------------------

NAME := concuerror
VERSION := 0.17

.PHONY: default dev
default dev: $(NAME)

###-----------------------------------------------------------------------------
### Files
###-----------------------------------------------------------------------------

DEPS = getopt/ebin/getopt
DEPS_BEAMS=$(DEPS:%=deps/%.beam)

SOURCES = $(wildcard src/*.erl)
MODULES = $(SOURCES:src/%.erl=%)
BEAMS = $(MODULES:%=ebin/%.beam)

VERSION_HRL=src/concuerror_version.hrl

###-----------------------------------------------------------------------------
### Compile
###-----------------------------------------------------------------------------

ERL_COMPILE_FLAGS := \
	+debug_info \
	+warn_export_vars \
	+warn_unused_import \
	+warn_missing_spec \
	+warn_untyped_record \
	+warnings_as_errors

dev: ERL_COMPILE_FLAGS += -DDEV=true
dev: VERSION := $(VERSION)-dev

$(NAME): $(DEPS_BEAMS) $(BEAMS)
	@$(RM) $@
	@printf " GEN  $@\n"
	@ln -s src/$(NAME) $@

###-----------------------------------------------------------------------------

-include $(MODULES:%=ebin/%.Pbeam)

ebin/%.beam: src/%.erl Makefile | ebin $(VERSION_HRL)
	@printf " DEPS $<\n"
	@erlc -o ebin -MD -MG $<
	@printf " ERLC $<\n"
	@erlc $(ERL_COMPILE_FLAGS) -o ebin $<

###-----------------------------------------------------------------------------

$(VERSION_HRL): version
	@printf " GEN  $@\n"
	@printf -- "-define(GIT_SHA, " > $@.tmp
	@git rev-parse --short --sq HEAD >> $@.tmp
	@printf ").\n" >> $@.tmp
	@src/versions $(VERSION) >> $@.tmp
	@cmp -s $@.tmp $@ > /dev/null || cp $@.tmp $@
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

DIALYZER_APPS = erts kernel stdlib compiler crypto
DIALYZER_FLAGS = -Wunmatched_returns -Wunderspecs

.PHONY: dialyze
dialyze: default $(PLT) $(DEPS_BEAMS)
	dialyzer --add_to_plt --plt $(PLT) $(DEPS_BEAMS)
	dialyzer --plt $(PLT) $(DIALYZER_FLAGS) ebin/*.beam

$(PLT):
	dialyzer --build_plt --output_plt $@ --apps $(DIALYZER_APPS) $^

###-----------------------------------------------------------------------------
### Testing
###-----------------------------------------------------------------------------

.PHONY: tests
tests:
	@$(RM) $@/thediff
	@(cd $@; bash -c "./runtests.py suites/*/src/*")

.PHONY: tests-real
tests-real: default
	@$(RM) $@/thediff
	$(MAKE) -C $@ \
		CONCUERROR=$(abspath concuerror) \
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
	export CONCUERROR_COVER=cover/data; $(MAKE) tests tests-real
	cd cover; ./cover-report data

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
	$(RM) $(NAME) $(VERSION_HRL) concuerror_report.txt
	$(RM) -r ebin cover-data

.PHONY: distclean
distclean: clean
	$(RM) $(PLT)
	$(RM) -r deps/*
	git checkout -- deps
