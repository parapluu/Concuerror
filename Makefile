#=============================================================================
#
#    File:  Makefile
# Authors:  Alkis Gotovos and Maria Christakis
#
#=============================================================================

# ----------------------------------------------------
# Orientation information
# ----------------------------------------------------

TOP = 	  $(PWD)

EBIN = 	  $(TOP)/ebin

INCLUDE = $(TOP)/include

DOC =     $(TOP)/doc

OPTS =    $(TOP)/opts.mk

# ----------------------------------------------------
# Flags
# ----------------------------------------------------

# Removed for now: +warn_untyped_record
DEFAULT_ERL_COMPILE_FLAGS = +warn_exported_vars +warn_unused_import \
+warn_missing_spec +debug_info

ERL_COMPILE_FLAGS = $(DEFAULT_ERL_COMPILE_FLAGS)

DEBUG1_ERL_COMPILE_FLAGS = $(DEFAULT_ERL_COMPILE_FLAGS) -DDEBUG_LEVEL_1

DEBUG2_ERL_COMPILE_FLAGS = $(DEBUG1_ERL_COMPILE_FLAGS) -DDEBUG_LEVEL_2

DIALYZER_FLAGS = -Wbehaviours

# ----------------------------------------------------
# Targets
# ----------------------------------------------------

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
	preb \
	sched \
	state \
	ticket \
	util

LOG_MODULES = \
	log \
	replay_logger

UTEST_MODULES = \
	error_tests \
	lid_tests \
        preb_tests \
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
vpath %.beam ebin

include $(OPTS)

all: 	$(TARGETS)

clean:
	printf "" > $(OPTS)
	rm -f *.sh
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

.PHONY: doc
doc:	util.beam
	erl -noinput -pa $(EBIN) -s util doc $(TOP) -s init stop

core:	$(CORE_MODULES:%=%.beam)

gui:	$(GUI_MODULES:%=%.beam)

log:	$(LOG_MODULES:%=%.beam)

utest:	$(UTEST_MODULES:%=%.beam)

scripts: run.sh test.sh

run.sh:
	printf "#%c/bin/bash\n \
	        erl -noinput -pa $(EBIN) -s gui start -s init stop" ! \
	      > run.sh
	chmod +x run.sh

test.sh:
	printf "#%c/bin/bash\n \
		dialyzer $(DIALYZER_FLAGS) $(EBIN)/*.beam\n \
	        erl -noinput -pa $(EBIN) -s util test -s init stop" ! \
	      > test.sh
	chmod +x test.sh

%.beam: %.erl
	erlc -W $(ERL_COMPILE_FLAGS) -I $(INCLUDE) -o $(EBIN) $<

# ----------------------------------------------------
# Dependencies
# ----------------------------------------------------

gui.beam: gui.hrl
scheduler.beam: gui.hrl

instr.beam: gen.hrl
log.beam: gen.hrl
sched.beam: gen.hrl
state.beam: gen.hrl
