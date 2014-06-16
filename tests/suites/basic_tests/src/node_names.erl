-module(node_names).

-export([scenarios/0]).
-export([test1/0,test2/0]).

scenarios() ->
    [{T, inf, dpor} || T <- [test1,test2]].

test1() ->
    R = monitor(process, {foo, node()}),
    receive
        {'DOWN',R,process,{foo,N},noproc} when N =:= node() -> ok
    end.

test2() ->
    register(foo, self()),
    spawn(fun() -> {foo, node()} ! ok end),
    receive
        ok -> ok
    end.
