###-----------------------------------------------------------------------------
### Application info
###-----------------------------------------------------------------------------

NAME := concuerror
VERSION := $(shell git describe --abbrev=6 --always --tags)
LATEST_MAJOR_OTP_VERSION := 20

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
all dev native pedantic: $(DEPS_BEAMS) $(BEAMS)

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
	@src/generate_otp_version_hrl $(LATEST_MAJOR_OTP_VERSION) > $@

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

## -j 1: ensure that the outputs of different suites are not interleaved
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
