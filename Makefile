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

# ----------------------------------------------------
# Targets
# ----------------------------------------------------

TARGETS = \
	gui \
	pulse \
	wx \
	src \
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

SRC_MODULES = \
	instr \
	log \
	sched \
	util

MODULES = \
	$(GUI_MODULES) \
	$(PULSE_MODULES) \
	$(SRC_MODULES)

ERL_DIRS = \
	gui \
	pulse \
	src

vpath %.hrl include
vpath %.erl $(ERL_DIRS)
vpath %.beam ebin

all: 	$(TARGETS)

clean:
	rm -f *.sh
	rm -f $(EBIN)/*.beam
	rm -f $(DOC)/*.html $(DOC)/*.css $(DOC)/edoc-info $(DOC)/*.png

.PHONY: doc
doc:	util.beam
	erl -noshell -pa $(EBIN) -s util doc $(TOP) -s init stop

gui:   	$(GUI_MODULES:%=%.beam)

pulse: 	$(PULSE_MODULES:%=%.beam)

src:	$(SRC_MODULES:%=%.beam)

wx:	pulse_gui.sh

utest:	test.sh

pulse_gui.sh:
	printf "#%c/bin/bash\n \
	        erl -noshell -pa $(EBIN) -s gui start -s init stop" ! \
	      > pulse_gui.sh
	chmod +x pulse_gui.sh

test.sh:
	printf "#%c/bin/bash\n \
		dialyzer $(EBIN)/*.beam\n \
	        erl -noshell -pa $(EBIN) -s sched test -s init stop" ! \
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

instr.beam: gen.hrl
log.beam: gen.hrl
sched.beam: gen.hrl