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

DOC = $(TOP)/doc

# ----------------------------------------------------
# Flags
# ----------------------------------------------------

ERL_COMPILE_FLAGS += +warn_exported_vars +warn_unused_import +warn_untyped_record +warn_missing_spec +debug_info

DIALYZER_FLAGS += -Wbehaviours

# ----------------------------------------------------
# Targets
# ----------------------------------------------------

TARGETS = \
	core \
	gui \
	log \
	scripts

GUI_MODULES = \
	gui

CORE_MODULES = \
	instr \
	sched \
	util

LOG_MODULES = \
	log \
	replay_server \
	replay_logger

MODULES = \
	$(GUI_MODULES) \
	$(CORE_MODULES) \
	$(LOG_MODULES)

ERL_DIRS = \
	src

vpath %.hrl include
vpath %.erl $(ERL_DIRS)
vpath %.beam ebin

all: 	$(TARGETS)

clean:
	rm -f *.sh
	rm -f $(EBIN)/*.beam
	rm -f $(DOC)/*.html $(DOC)/*.css $(DOC)/edoc-info $(DOC)/*.png

# TODO: Better way than 'clean'.
debug1:	ERL_COMPILE_FLAGS += -DDEBUG_LEVEL_1
debug1:	clean $(TARGETS)

debug2:	ERL_COMPILE_FLAGS += -DDEBUG_LEVEL_2
debug2:	clean $(TARGETS)

.PHONY: doc
doc:	util.beam
	erl -noinput -pa $(EBIN) -s util doc $(TOP) -s init stop

core:	$(CORE_MODULES:%=%.beam)

gui:	$(GUI_MODULES:%=%.beam)

log:	$(LOG_MODULES:%=%.beam)

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
