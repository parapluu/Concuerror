.PHONY: test

test: poolboy/ebin/poolboy.beam poolboy/.eunit/poolboy_test_worker.beam poolboy/poolboy_tests_1.erl
	./test

poolboy/ebin/poolboy.beam: poolboy/rebar
	$(MAKE) REBAR=./$(<F) -s -C $(<D)

poolboy/.eunit/poolboy_test_worker.beam: poolboy/rebar
	$(MAKE) REBAR=./$(<F) -s -C $(<D) test -i > /dev/null

poolboy/poolboy_tests_1.erl: | poolboy
	git clone -q https://gist.github.com/b67df16361cd9a2fa87e.git tmp
	mv tmp/$(notdir $@) $@
	rm -rf tmp

poolboy/rebar: | poolboy
	cd poolboy; wget https://github.com/rebar/rebar/wiki/rebar; chmod u+x rebar

poolboy:
	git clone -q https://github.com/devinus/poolboy.git --branch 1.2.2
