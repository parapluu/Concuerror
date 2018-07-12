.PHONY: test

test: erlang-concurrency-litmus-tests
	./test etsglobal
	./test leader
	./test link
	./test mailbox
	./test process
	./test registry
	./test signal
	./test timer

erlang-concurrency-litmus-tests:
	git clone https://github.com/aronisstav/erlang-concurrency-litmus-tests.git
