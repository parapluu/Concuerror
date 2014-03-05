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

VSN = "0.9"

###----------------------------------------------------------------------
### Orientation information
###----------------------------------------------------------------------

TOP = 	  $(CURDIR)

EBIN = 	  $(TOP)/ebin

INCLUDE = $(TOP)/include

###----------------------------------------------------------------------
### Flags
###----------------------------------------------------------------------

ERL_COMPILE_FLAGS = \
	+debug_info \
	+warn_exported_vars \
	+warn_unused_import \
	+warn_missing_spec \
	+warn_untyped_record

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
	concuerror_scheduler

vpath %.erl src

.PHONY: compile clean dialyze test submodules

compile: $(MODULES:%=$(EBIN)/%.beam) meck getopt concuerror

include $(MODULES:%=$(EBIN)/%.Pbeam)

$(EBIN)/%.Pbeam: %.erl
	erlc -o $(EBIN) -I $(INCLUDE) -MT $(subst .Pbeam,.beam,$@) -MD $<

$(EBIN)/concuerror_%.beam: concuerror_%.erl Makefile
	erlc $(ERL_COMPILE_FLAGS) -I $(INCLUDE) -DVSN="\"$(VSN)\"" -o $(EBIN) $<

concuerror:
	ln -s src/concuerror $@

getopt: submodules
	make -C deps/getopt

meck: submodules
	cd deps/meck \
		&& cp rebar.config rebar.config.bak \
		&& sed -i 's/warnings_as_errors, //' rebar.config \
		&& make get-deps \
		&& make compile \
		&& mv rebar.config.bak rebar.config

submodules:
	git submodule update --init

clean:
	rm -f concuerror
	rm -f $(EBIN)/*.beam
	rm -f $(EBIN)/*.Pbeam

dialyze: all .concuerror_plt
	dialyzer --plt .concuerror_plt $(DIALYZER_FLAGS) $(EBIN)/*.beam

.concuerror_plt: | meck getopt
	dialyzer --build_plt --output_plt $@ --apps erts kernel stdlib compiler \
	deps/*/ebin/*.beam deps/*/deps/*/ebin/*.beam 

###----------------------------------------------------------------------
### Testing
###----------------------------------------------------------------------

SUITES = basic_tests,dpor_tests,advanced_tests

test: all
	@(cd tests; bash -c "./runtests.py suites/{$(SUITES)}/src/*")