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
	core \
	gui \
	utest \
	wx

GUI_MODULES = \
	funs \
	refServer \
	gui

CORE_MODULES = \
	instr \
	log \
	sched \
	util

MODULES = \
	$(GUI_MODULES) \
	$(CORE_MODULES)

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

.PHONY: doc
doc:	util.beam
	erl -noinput -pa $(EBIN) -s util doc $(TOP) -s init stop

core:	$(CORE_MODULES:%=%.beam)

gui:	$(GUI_MODULES:%=%.beam)

wx:	run.sh

utest:	test.sh

run.sh:
	printf "#%c/bin/bash\n \
	        erl -noinput -pa $(EBIN) -s gui start -s init stop" ! \
	      > run.sh
	chmod +x run.sh

test.sh:
	printf "#%c/bin/bash\n \
		dialyzer $(EBIN)/*.beam\n \
	        erl -noinput -pa $(EBIN) -s sched test -s init stop" ! \
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
