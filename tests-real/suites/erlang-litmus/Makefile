.PHONY: test

test: erlang-concurrency-litmus-tests
	./test link
	./test mailbox
	./test process
	./test registry
	./test signal
	./test timer

#./test . #When everything works

erlang-concurrency-litmus-tests:
	git clone https://github.com/aronisstav/erlang-concurrency-litmus-tests.git
