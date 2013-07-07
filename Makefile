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

APP_STRING = "Concuerror"
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
	concuerror_scheduler \
	getopt

vpath %.hrl include
vpath %.erl src

.PHONY: clean dialyze

all: concuerror $(MODULES:%=$(EBIN)/%.beam)

clean:
	rm -f concuerror
	rm -f $(OPTS)
	rm -f $(EBIN)/*.beam

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

### XXX: Replace with automatically dependencies
$(EBIN)/%.beam: %.erl include/* Makefile
	erlc $(ERL_COMPILE_FLAGS) -I $(INCLUDE) -DEBIN="\"$(EBIN)\"" -DAPP_STRING="\"$(APP_STRING)\"" -DVSN="\"$(VSN)\"" -o $(EBIN) $<
