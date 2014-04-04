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

VSN = 0.10

###----------------------------------------------------------------------
### Flags
###----------------------------------------------------------------------

ERL_COMPILE_FLAGS = \
	+debug_info \
	+warn_export_vars \
	+warn_unused_import \
	+warn_missing_spec \
	+warn_untyped_record

DIALYZER_FLAGS = -Wunmatched_returns

###----------------------------------------------------------------------
### Targets
###----------------------------------------------------------------------

MODULES = \
	concuerror_callback \
	concuerror_common \
	concuerror_dependencies \
	concuerror_inspect \
	concuerror_instrumenter \
	concuerror_loader \
	concuerror_logger \
	concuerror_options \
	concuerror_printer \
	concuerror_scheduler \
	concuerror

vpath %.erl src

.PHONY: compile clean dialyze test submodules

compile: $(MODULES:%=ebin/%.beam) getopt concuerror

include $(MODULES:%=ebin/%.Pbeam)

ebin/%.Pbeam: %.erl | ebin
	erlc -o ebin -I include -MD $<

ebin/%.beam: %.erl Makefile | ebin
	erlc $(ERL_COMPILE_FLAGS) -I include -DVSN="\"$(VSN)\"" -o ebin $<

ebin:
	mkdir ebin

concuerror:
	ln -s src/concuerror $@

getopt: submodules
	make -C deps/getopt

submodules:
	git submodule update --init

clean:
	rm -f concuerror
	rm -rf ebin

dialyze: all .concuerror_plt
	dialyzer --plt .concuerror_plt $(DIALYZER_FLAGS) ebin/*.beam

.concuerror_plt: | getopt
	dialyzer --build_plt --output_plt $@ --apps erts kernel stdlib compiler \
	deps/*/ebin/*.beam

###----------------------------------------------------------------------
### Testing
###----------------------------------------------------------------------

SUITES = advanced_tests,dpor_tests,basic_tests

test: all
	@(cd tests; bash -c "./runtests.py suites/{$(SUITES)}/src/*")
