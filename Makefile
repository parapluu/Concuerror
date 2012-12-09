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
VSN = "0.9"

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
	core_target \
	main_target \
	log_target \
	utest_target \
	scripts_target

MAIN_MODULES = \
	concuerror

CORE_MODULES = \
	concuerror_gui \
	concuerror_error \
	concuerror_instr \
	concuerror_lid \
	concuerror_proc_action \
	concuerror_rep \
	concuerror_sched \
	concuerror_state \
	concuerror_ticket \
	concuerror_util

LOG_MODULES = \
	concuerror_log

UTEST_MODULES = \
	concuerror_error_tests \
	concuerror_instr_tests \
	concuerror_lid_tests \
	concuerror_state_tests \
	concuerror_ticket_tests

MODULES = \
	$(MAIN_MODULES) \
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

doc:	$(EBIN)/concuerror_util.beam
	erl -noinput -pa $(EBIN) -s concuerror_util doc $(TOP) -s init stop

core_target:    $(CORE_MODULES:%=$(EBIN)/%.beam)

main_target:    $(MAIN_MODULES:%=$(EBIN)/%.beam)

log_target:     $(LOG_MODULES:%=$(EBIN)/%.beam)

utest_target:   $(UTEST_MODULES:%=$(EBIN)/%.beam)

scripts_target: concuerror

utest: all
	erl -noinput -pa $(EBIN) \
		-s concuerror_util test -s init stop

test: all
	@(cd testsuite && THREADS=$(THREADS) ./runtests.py)

concuerror:
	printf "\
	#%c/bin/bash\n\n\
	Date=\$$(date +%%s%%N)\n\
	Name=\"$(APP_STRING)\$$Date\"\n\
	Cookie=\"$(APP_STRING)Cookie\"\n\n\
	trap ctrl_c INT\n\
	function ctrl_c() {\n\
	    erl -sname $(APP_STRING)Stop -noinput -cookie \$$Cookie \\\\\n\
	        -pa $(EBIN) \\\\\n\
	        -run concuerror stop \$$Name -run init stop\n\
	}\n\n\
	erl +Bi -smp enable -noinput -sname \$$Name -cookie \$$Cookie \\\\\n\
	    -pa $(EBIN) \\\\\n\
	    -run concuerror cli -run init stop -- \"\$$@\" &\n\
	wait \$$!\n" ! > $@
	chmod +x $@

$(EBIN)/%.beam: %.erl
	erlc $(ERL_COMPILE_FLAGS) -I $(INCLUDE) -DEBIN="\"$(EBIN)\"" -DAPP_STRING="\"$(APP_STRING)\"" -DVSN="\"$(VSN)\"" -o $(EBIN) $<

###----------------------------------------------------------------------
### Dependencies
###----------------------------------------------------------------------

# FIXME: Automatically generate these.
