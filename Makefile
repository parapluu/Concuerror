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

# ----------------------------------------------------
# Flags
# ----------------------------------------------------

ERL_COMPILE_FLAGS += +warn_exported_vars +warn_unused_import +warn_untyped_record +warn_missing_spec

# ----------------------------------------------------
# Targets
# ----------------------------------------------------

TARGETS = \
	gui \
	pulse \
	wx

GUI_MODULES = \
	funs \
	refServer \
	gui

PULSE_MODULES = \
	dot \
	driver \
	instrument \
	scheduler

MODULES = \
	$(GUI_MODULES) \
	$(PULSE_MODULES)

ERL_DIRS = \
	gui \
	pulse

vpath %.hrl include
vpath %.erl $(ERL_DIRS)
vpath %.beam ebin

all: 	$(TARGETS)

clean:
	rm -f run.sh
	rm -f $(EBIN)/*.beam

gui:   	$(GUI_MODULES:%=%.beam)

pulse: 	$(PULSE_MODULES:%=%.beam)

wx:	run.sh

run.sh:
	echo "#!/bin/bash\n \
	      erl -noshell -pa $(TOP) \
	      $(EBIN) -s gui start -s init stop" \
	      > run.sh
	chmod +x run.sh

%.beam: %.erl
	erlc -W $(ERL_COMPILE_FLAGS) -I $(INCLUDE) -o $(EBIN) $<

# ----------------------------------------------------
# Dependencies
# ----------------------------------------------------

driver.beam : gui.hrl
gui.beam: gui.hrl
refServer.beam: gui.hrl
scheduler.beam: gui.hrl
