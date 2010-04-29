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

ERL_COMPILE_FLAGS += +warn_exported_vars +warn_unused_import +warn_untyped_record +warn_missing_spec +debug_info

# ----------------------------------------------------
# Targets
# ----------------------------------------------------

TARGETS = \
	gui \
	pulse \
	wx \
	pra1 \
	utest

GUI_MODULES = \
	funs \
	refServer \
	gui

PULSE_MODULES = \
	dot \
	driver \
	instrument \
	scheduler

PRA1_MODULES = \
	sched \
	instr \
	test_instr \
	test

MODULES = \
	$(GUI_MODULES) \
	$(PULSE_MODULES) \
	$(PRA1_MODULES)

ERL_DIRS = \
	gui \
	pulse \
	pra1

vpath %.hrl include
vpath %.erl $(ERL_DIRS)
vpath %.beam ebin

all: 	$(TARGETS)

clean:
	rm -f *.sh
	rm -f $(EBIN)/*.beam

gui:   	$(GUI_MODULES:%=%.beam)

pulse: 	$(PULSE_MODULES:%=%.beam)

pra1:	$(PRA1_MODULES:%=%.beam)

wx:	pulse_gui.sh

utest:	test.sh

pulse_gui.sh:
	printf "#%c/bin/bash\n \
	      erl -noshell -pa $(EBIN) \
	      -s gui start -s init stop" ! \
	      > pulse_gui.sh
	chmod +x pulse_gui.sh

test.sh:
	printf "#%c/bin/bash\n \
	      erl -noshell -pa $(EBIN) \
	      -s sched test \044\061 -s init stop" ! \
	      > test.sh
	chmod +x test.sh

%.beam: %.erl
	erlc -W $(ERL_COMPILE_FLAGS) -I $(INCLUDE) -o $(EBIN) $<

# ----------------------------------------------------
# Dependencies
# ----------------------------------------------------

driver.beam : gui.hrl
gui.beam: gui.hrl
refServer.beam: gui.hrl
scheduler.beam: gui.hrl
