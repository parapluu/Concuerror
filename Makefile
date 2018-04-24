###-----------------------------------------------------------------------------
### Application info
###-----------------------------------------------------------------------------

NAME := concuerror
VERSION := $(shell git describe --abbrev=6 --always --tags)

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

OTP_VERSION_HRL = src/concuerror_otp_version.hrl

GENERATED_HRLS = $(OTP_VERSION_HRL)

###-----------------------------------------------------------------------------
### Compile
###-----------------------------------------------------------------------------

MAKEFLAGS += --no-builtin-rules
.SUFFIXES:

.PHONY: all dev native pedantic
all dev native pedantic: $(DEPS_BEAMS) $(BEAMS) $(NAME)

dev: VERSION := $(VERSION)-dev
dev: ERL_COMPILE_FLAGS += -DDEV=true

native: VERSION := $(VERSION)-native
native: ERL_COMPILE_FLAGS += +native

pedantic: ERL_COMPILE_FLAGS += +warnings_as_errors

ERL_COMPILE_FLAGS += \
	-DVSN="\"$(VERSION)\"" \
	+debug_info \
	+warn_export_vars \
	+warn_unused_import \
	+warn_missing_spec \
	+warn_untyped_record

$(NAME): Makefile
	@$(RM) $@
	@printf " GEN   $@\n"
	@printf -- "#!/usr/bin/env sh\n" >> $@
	@printf -- "SCRIPTPATH=\"\$$( cd \"\$$(dirname \"\$$0\")\" ; pwd -P )\"\n" >> $@
	@printf -- "printf \"\nWARNING! Concuerror/concuerror will be removed in next version. Use Concuerror/bin/concuerror instead!\n\"\n" >> $@
	@printf -- "\$$SCRIPTPATH/bin/concuerror \$$@" >> $@
	@chmod u+x $@

###-----------------------------------------------------------------------------

-include $(MODULES:%=ebin/%.Pbeam)

ebin/%.Pbeam: src/%.erl | ebin $(GENERATED_HRLS)
	@printf " DEPS  $<\n"
	@erlc -o ebin -MD -MG $<

ebin/%.beam: src/%.erl | ebin
	@printf " ERLC  $<\n"
	@erlc -o ebin $(ERL_COMPILE_FLAGS) $<

###-----------------------------------------------------------------------------

$(OTP_VERSION_HRL):
	@printf " GEN   $@\n"
	@src/generate_otp_version_hrl $$(./.travis/get_latest_travis ./.travis.yml) > $@

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
	@printf " CO    $(@D)\n"
	@git submodule update --init

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
	cd cover; ./cover-report data

###-----------------------------------------------------------------------------
### Clean
###-----------------------------------------------------------------------------

.PHONY: clean
clean:
	$(RM) $(NAME)
	$(RM) -r ebin

.PHONY: distclean
distclean: clean
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
