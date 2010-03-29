ERLC=erlc
CFLAGS=-Wall -I include -o bin

vpath %.hrl include
vpath %.erl gui pulse
vpath %.beam bin

all: gui pulse makerun

gui: gui.beam funs.beam refServer.beam

pulse: dot.beam driver.beam instrument.beam scheduler.beam

makerun: run.sh

run.sh:
	echo "#!/bin/bash\n \
	      erl -noshell -pa /home/alkis/Desktop/Chess \
	      /home/alkis/Desktop/Chess/bin -s gui start -s init stop" \
	      > run.sh
	chmod +x run.sh

*.beam: gui.hrl

%.beam: %.erl
	$(ERLC) $(CFLAGS) $<

.PHONY: clean
clean:
	rm -f run.sh
	rm -f bin/*.beam