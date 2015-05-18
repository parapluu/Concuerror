###----------------------------------------------------------------------
### Copyright (c) 2011-2013, Alkis Gotovos <el3ctrologos@hotmail.com>,
###                          Maria Christakis <mchrista@softlab.ntua.gr>
###                      and Kostis Sagonas <kostis@cs.ntua.gr>.
### All rights reserved.
###
### This file is distributed under the Simplified BSD License.
### Details can be found in the LICENSE file.
###----------------------------------------------------------------------
### Authors     : Alkis Gotovos <el3ctrologos@hotmail.com>
###               Maria Christakis <mchrista@softlab.ntua.gr>
### Description : Main Makefile
###----------------------------------------------------------------------

all: compile

###----------------------------------------------------------------------
### Application info
###----------------------------------------------------------------------

VSN ?= 0.11

###----------------------------------------------------------------------
### Flags
###----------------------------------------------------------------------

ERL_COMPILE_FLAGS ?= \
	+debug_info \
	+warn_export_vars \
	+warn_unused_import \
	+warn_missing_spec \
	+warn_untyped_record \
	+warnings_as_errors

DIALYZER_FLAGS = -Wunmatched_returns

###----------------------------------------------------------------------
### Targets
###----------------------------------------------------------------------

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

.PHONY: clean compile cover dialyze otp_version submodules tests tests-long

compile: $(MODULES:%=ebin/%.beam) getopt concuerror

dev:
	$(MAKE) VSN="$(VSN)d" \
	ERL_COMPILE_FLAGS="$(ERL_COMPILE_FLAGS) -DDEV=true"

ifneq ($(MAKECMDGOALS),clean)
-include $(MODULES:%=ebin/%.Pbeam)
endif

ebin/%.Pbeam: src/%.erl src/*.hrl Makefile | ebin
	@echo " ERLC -MD $<"
	@erlc -o ebin -MD -MG $<

ebin/%.beam: src/%.erl Makefile | ebin otp_version
	@echo " ERLC $<"
	@erlc $(ERL_COMPILE_FLAGS) -DVSN="\"$(VSN)\"" -o ebin $<

otp_version:
	@echo "Checking OTP Version..."
	@src/otp_version > $@.tmp
	@cmp -s $@.tmp src/$@.hrl > /dev/null || cp $@.tmp src/$@.hrl
	@rm $@.tmp

concuerror:
	ln -s src/concuerror $@

getopt: submodules
	$(MAKE) -C deps/getopt

submodules:
	git submodule update --init

clean:
	rm -f concuerror
	rm -rf ebin cover-data
	rm -f tests*/scenarios.beam

dialyze: all .concuerror_plt
	dialyzer --plt .concuerror_plt $(DIALYZER_FLAGS) ebin/*.beam

.concuerror_plt: | getopt
	dialyzer --build_plt --output_plt $@ --apps erts kernel stdlib compiler \
	deps/*/ebin/*.beam

###----------------------------------------------------------------------
### Testing
###----------------------------------------------------------------------

%/scenarios.beam: %/scenarios.erl
	erlc -o $(@D) $<

SUITES = {advanced_tests,dpor_tests,basic_tests}

tests: all tests/scenarios.beam
	@(cd tests; bash -c "./runtests.py suites/$(SUITES)/src/*")

tests-long: all
	$(MAKE) -C $@ CONCUERROR=$(abspath concuerror) DIFFER=$(abspath tests/differ)

###----------------------------------------------------------------------

cover: cover-data
	export CONCUERROR_COVER=true; $(MAKE) tests-all
	tests/cover-report

###----------------------------------------------------------------------

ebin cover-data:
	mkdir $@
