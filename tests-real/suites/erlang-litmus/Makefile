.PHONY: test

test: erlang-concurrency-litmus-tests
	#./test etsglobal # Skip: The tests are incomplete and a bit
	#                 #       irrelevant for Concuerror right now
	./test leader
	./test link
	./test mailbox
	./test process
	./test registry
	./test signal
	./test timer

erlang-concurrency-litmus-tests:
	git clone https://github.com/aronisstav/erlang-concurrency-litmus-tests.git
