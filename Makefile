###-----------------------------------------------------------------------------
### Application info
###-----------------------------------------------------------------------------

VERSION := 0.12

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

###-----------------------------------------------------------------------------
### Targets
###-----------------------------------------------------------------------------

VERSION_HRL=src/concuerror_version.hrl

###-----------------------------------------------------------------------------

.PHONY: default dev
default dev: concuerror

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

.PHONY: version
version:

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

.PHONY: clean
clean:
	rm -f concuerror
	rm -f tests/scenarios.beam
	rm -rf ebin cover-data

.PHONY: distclean
distclean: clean
	rm -f $(VERSION_HRL) .concuerror_plt concuerror_report.txt
	rm -rf deps/*
	git checkout -- deps

###-----------------------------------------------------------------------------

DIALYZER_APPS = erts kernel stdlib compiler crypto
DIALYZER_FLAGS = -Wunmatched_returns -Wunderspecs

DIALYZER_DEPS=$(DEPS:%=deps/%.beam)

.PHONY: dialyze
dialyze: .concuerror_plt default $(DIALYZER_DEPS)
	dialyzer --add_to_plt --plt $< $(DIALYZER_DEPS)
	dialyzer --plt $< $(DIALYZER_FLAGS) ebin/*.beam

.concuerror_plt:
	dialyzer --build_plt --output_plt $@ --apps $(DIALYZER_APPS) $^

###-----------------------------------------------------------------------------
### Testing
###-----------------------------------------------------------------------------

%/scenarios.beam: %/scenarios.erl
	erlc -o $(@D) $<

SUITES = {advanced_tests,dpor_tests,basic_tests}

.PHONY: tests
tests: default tests/scenarios.beam
	@rm -f $@/thediff
	@(cd $@; bash -c "./runtests.py suites/$(SUITES)/src/*")

.PHONY: tests-long
tests-long: default
	@rm -f $@/thediff
	$(MAKE) -C $@ \
		CONCUERROR=$(abspath concuerror) \
		DIFFER=$(abspath tests/differ) \
		DIFFPRINTER=$(abspath $@/thediff)

###-----------------------------------------------------------------------------

.PHONY: cover
cover: cover-data
	export CONCUERROR_COVER=true; $(MAKE) tests tests-long
	tests/cover-report

###-----------------------------------------------------------------------------

.PHONY: travis_has_latest_otp_version
travis_has_latest_otp_version:
	./travis/$@
