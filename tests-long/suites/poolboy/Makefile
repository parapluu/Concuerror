.PHONY: test

test: poolboy/ebin/poolboy.beam poolboy/.eunit/poolboy_test_worker.beam poolboy/poolboy_tests_1.erl
	./test

poolboy/ebin/poolboy.beam: poolboy
	$(MAKE) -s -C $<

poolboy/.eunit/poolboy_test_worker.beam: poolboy
	$(MAKE) -s -C $< test -i > /dev/null

poolboy/poolboy_tests_1.erl: poolboy
	git clone -q https://gist.github.com/b67df16361cd9a2fa87e.git tmp
	mv tmp/$(notdir $@) $@
	rm -rf tmp

poolboy:
	git clone -q https://github.com/devinus/poolboy.git --branch 1.2.1
