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

### XXX: Restore
#DEF_WARNS = +warn_exported_vars +warn_unused_import +warn_missing_spec +warn_untyped_record
DEF_WARNS =

DEFAULT_ERL_COMPILE_FLAGS = +debug_info $(DEF_WARNS) -Werror

ERL_COMPILE_FLAGS = $(DEFAULT_ERL_COMPILE_FLAGS)

NATIVE_ERL_COMPILE_FLAGS = $(DEFAULT_ERL_COMPILE_FLAGS) +native

DEBUG_ERL_COMPILE_FLAGS = $(DEFAULT_ERL_COMPILE_FLAGS) -DDEBUG

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

.PHONY: compile clean dialyze test

all: compile

compile: concuerror $(MODULES:%=$(EBIN)/%.beam) $(EBIN)/getopt.beam

include $(MODULES:%=$(EBIN)/%.Pbeam)

clean:
	rm -f concuerror
	rm -f $(OPTS)
	rm -f $(EBIN)/*.beam
	rm -f $(EBIN)/*.Pbeam

ifneq ($(ERL_COMPILE_FLAGS), $(NATIVE_ERL_COMPILE_FLAGS))
native:
	make clean
	printf "ERL_COMPILE_FLAGS += +native" > $(OPTS)
	make
else
native:
	make
endif

ifneq ($(ERL_COMPILE_FLAGS), $(DEBUG_ERL_COMPILE_FLAGS))
debug:
	make clean
	printf "ERL_COMPILE_FLAGS += -DDEBUG" > $(OPTS)
	make
else
debug:
	make
endif

dialyze: all
	dialyzer $(DIALYZER_FLAGS) $(EBIN)/*.beam

concuerror:
	ln -s src/concuerror $@

$(EBIN)/getopt.beam:
	git submodule update
	cd deps/getopt && make
	cp deps/getopt/ebin/getopt.beam $@

$(EBIN)/%.Pbeam: %.erl
	erlc -o $(EBIN) -I $(INCLUDE) -MD -MT $@ $<

$(EBIN)/concuerror_%.beam: concuerror_%.erl Makefile
	erlc $(ERL_COMPILE_FLAGS) -I $(INCLUDE) -DVSN="\"$(VSN)\"" -o $(EBIN) $<

###----------------------------------------------------------------------
### Testing
###----------------------------------------------------------------------

SUITES = basic_tests,dpor_tests

test: all $(EBIN)/meck.beam
	@(cd tests; bash -c "./runtests.py suites/{$(SUITES)}/src/*")

$(EBIN)/meck.beam:
	git submodule update
	cd deps/meck \
		&& cp rebar.config rebar.config.bak \
		&& sed -i 's/warnings_as_errors, //' rebar.config \
		&& make get-deps \
		&& make compile \
		&& mv rebar.config.bak rebar.config
	cp deps/meck/ebin/*.beam ebin
