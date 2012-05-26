###----------------------------------------------------------------------
### Copyright (c) 2011, Alkis Gotovos <el3ctrologos@hotmail.com>,
###                     Maria Christakis <mchrista@softlab.ntua.gr>
###                 and Kostis Sagonas <kostis@cs.ntua.gr>.
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

###----------------------------------------------------------------------
### Orientation information
###----------------------------------------------------------------------

TOP = 	  $(PWD)

EBIN = 	  $(TOP)/ebin

INCLUDE = $(TOP)/include

DOC =     $(TOP)/doc

OPTS =    $(TOP)/opts.mk

###----------------------------------------------------------------------
### Flags
###----------------------------------------------------------------------

# Removed for now: +warn_untyped_record
DEFAULT_ERL_COMPILE_FLAGS = +warn_exported_vars +warn_unused_import \
+warn_missing_spec +debug_info

ERL_COMPILE_FLAGS = $(DEFAULT_ERL_COMPILE_FLAGS)

DEBUG1_ERL_COMPILE_FLAGS = $(DEFAULT_ERL_COMPILE_FLAGS) -DDEBUG_LEVEL_1

DEBUG2_ERL_COMPILE_FLAGS = $(DEBUG1_ERL_COMPILE_FLAGS) -DDEBUG_LEVEL_2

DIALYZER_FLAGS = -Wunmatched_returns

###----------------------------------------------------------------------
### Targets
###----------------------------------------------------------------------

TARGETS = \
	core \
	gui \
	log \
	utest \
	scripts

GUI_MODULES = \
	gui

CORE_MODULES = \
	error \
	instr \
	lid \
	proc_action \
	rep \
	sched \
	snapshot \
	state \
	ticket \
	util

LOG_MODULES = \
	log \
	replay_logger

UTEST_MODULES = \
	error_tests \
	instr_tests \
	lid_tests \
	sched_tests \
	state_tests \
	ticket_tests

MODULES = \
	$(GUI_MODULES) \
	$(CORE_MODULES) \
	$(LOG_MODULES) \
	$(UTEST_MODULES)

ERL_DIRS = \
	src \
	utest

vpath %.hrl include
vpath %.erl $(ERL_DIRS)

include $(wildcard $(OPTS))

.PHONY: clean dialyze doc test

all: 	$(TARGETS)

clean:
	rm -f concuerror
	rm -f $(OPTS)
	rm -f $(EBIN)/*.beam
	rm -f $(DOC)/*.html $(DOC)/*.css $(DOC)/edoc-info $(DOC)/*.png

ifneq ($(ERL_COMPILE_FLAGS), $(DEFAULT_ERL_COMPILE_FLAGS))
release:
	make clean
	make
else
release:
	make
endif

ifneq ($(ERL_COMPILE_FLAGS), $(DEBUG1_ERL_COMPILE_FLAGS))
debug1:
	make clean
	printf "ERL_COMPILE_FLAGS += -DDEBUG_LEVEL_1" > $(OPTS)
	make
else
debug1:
	make
endif

ifneq ($(ERL_COMPILE_FLAGS), $(DEBUG2_ERL_COMPILE_FLAGS))
debug2:
	make clean
	printf "ERL_COMPILE_FLAGS += -DDEBUG_LEVEL_1 -DDEBUG_LEVEL_2" > $(OPTS)
	make
else
debug2:
	make
endif

dialyze: all
	dialyzer $(DIALYZER_FLAGS) $(EBIN)/*.beam

doc:	$(EBIN)/util.beam
	erl -noinput -pa $(EBIN) -s util doc $(TOP) -s init stop

core:	$(CORE_MODULES:%=$(EBIN)/%.beam)

gui:	$(GUI_MODULES:%=$(EBIN)/%.beam)

log:	$(LOG_MODULES:%=$(EBIN)/%.beam)

utest:	$(UTEST_MODULES:%=$(EBIN)/%.beam)

scripts: concuerror

test: 	all
	erl -noinput -sname $(APP_STRING) -pa $(EBIN) -s util test -s init stop

concuerror:
	printf "#%c/bin/bash\n \
		\n\
	        erl -smp enable -noinput -sname $(APP_STRING) -pa $(EBIN) -s gui start -s init stop" ! \
	      > concuerror
	chmod +x concuerror

$(EBIN)/%.beam: %.erl
	erlc $(ERL_COMPILE_FLAGS) -I $(INCLUDE) -DEBIN="\"$(EBIN)\"" -DAPP_STRING="\"$(APP_STRING)\"" -o $(EBIN) $<

###----------------------------------------------------------------------
### Dependencies
###----------------------------------------------------------------------

# FIXME: Automatically generate these.