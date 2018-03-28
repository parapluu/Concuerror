-module(register).

-export([test/0]).

-concuerror_options_forced([symbolic_names]).

test() ->
  spawn(fun() ->
            register(foo, self()),
            exit(abnormal)
        end).
