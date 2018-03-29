.PHONY: test

test: erlang-concurrency-litmus-tests
	./test mailbox
	./test link
	./test registry
	./test timer

#./test . #When everything works

erlang-concurrency-litmus-tests:
	git clone https://github.com/aronisstav/erlang-concurrency-litmus-tests.git
