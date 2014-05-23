.PHONY: test

test: gproc/ebin/gproc.beam run
	./test

gproc/ebin/gproc.beam: gproc
	$(MAKE) -C gproc

gproc:
	git clone https://github.com/uwiger/gproc.git -b 0.3


run:
	mkdir $@
