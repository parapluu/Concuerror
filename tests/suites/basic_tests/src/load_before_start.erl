-module(load_before_start).

-export([scenarios/0]).
-export([test/0]).

scenarios() ->
    [{test, inf, dpor}].

test() ->
    spawn(ets,new,[table,[named_table]]),
    spawn(ets,lookup,[table,key]).
