###-----------------------------------------------------------------------------
### Application info
###-----------------------------------------------------------------------------

VERSION := 0.11

###-----------------------------------------------------------------------------
### Modules
###-----------------------------------------------------------------------------

DEPS = getopt/ebin/getopt

MODULES = \
	concuerror_callback \
	concuerror_dependencies \
	concuerror_inspect \
	concuerror_instrumenter \
	concuerror_loader \
	concuerror_logger \
	concuerror_options \
	concuerror_printer \
	concuerror_scheduler \
	concuerror

###-----------------------------------------------------------------------------
### Flags
###-----------------------------------------------------------------------------

ERL_COMPILE_FLAGS := \
	+debug_info \
	+warn_export_vars \
	+warn_unused_import \
	+warn_missing_spec \
	+warn_untyped_record \
	+warnings_as_errors

DIALYZER_APPS = erts kernel stdlib compiler crypto
DIALYZER_FLAGS = -Wunmatched_returns -Wunderspecs

###-----------------------------------------------------------------------------
### Targets
###-----------------------------------------------------------------------------

VERSION_HRL=src/concuerror_version.hrl

.PHONY: clean cover dev default dialyze distclean tests tests-long version

###-----------------------------------------------------------------------------

default dev: concuerror

default: ERL_COMPILE_FLAGS += +native

dev: ERL_COMPILE_FLAGS += -DDEV=true
dev: VERSION := $(VERSION)-dev

concuerror: $(DEPS:%=deps/%.beam) $(MODULES:%=ebin/%.beam)
	@echo " GEN  $@"
	@ln -s src/concuerror $@

###-----------------------------------------------------------------------------

-include $(MODULES:%=ebin/%.Pbeam)

ebin/%.beam: src/%.erl Makefile | ebin $(VERSION_HRL)
	@echo " DEPS $<"
	@erlc -o ebin -MD -MG $<
	@echo " ERLC $<"
	@erlc $(ERL_COMPILE_FLAGS) -o ebin $<

$(VERSION_HRL): version
	@rm -f concuerror
	@echo " GEN  $@"
	@src/versions $(VERSION) > $@.tmp
	@cmp -s $@.tmp $@ > /dev/null || cp $@.tmp $@
	@rm $@.tmp

ebin cover-data:
	@echo " MKDIR $@"
	@mkdir $@

###-----------------------------------------------------------------------------

%/ebin/getopt.beam: %/.git
	$(MAKE) -C $(dir $<)
	rm -rf $(dir $<).rebar

deps/%/.git:
	git submodule update --init

###-----------------------------------------------------------------------------

clean:
	rm -f concuerror
	rm -f tests/scenarios.beam
	rm -rf ebin cover-data

distclean: clean
	rm -f $(VERSION_HRL) .concuerror_plt concuerror_report.txt
	rm -rf deps/*
	git checkout -- deps

###-----------------------------------------------------------------------------

dialyze: default .concuerror_plt
	dialyzer --plt .concuerror_plt $(DIALYZER_FLAGS) ebin/*.beam

.concuerror_plt: $(DEPS:%=deps/%.beam)
	dialyzer --build_plt --output_plt $@ --apps $(DIALYZER_APPS) $^

###-----------------------------------------------------------------------------
### Testing
###-----------------------------------------------------------------------------

%/scenarios.beam: %/scenarios.erl
	erlc -o $(@D) $<

SUITES = {advanced_tests,dpor_tests,basic_tests}

tests: default tests/scenarios.beam
	@(cd tests; bash -c "./runtests.py suites/$(SUITES)/src/*")

tests-long: default
	$(MAKE) -C $@ CONCUERROR=$(abspath concuerror) DIFFER=$(abspath tests/differ)

###-----------------------------------------------------------------------------

cover: cover-data
	export CONCUERROR_COVER=true; $(MAKE) tests tests-long
	tests/cover-report
