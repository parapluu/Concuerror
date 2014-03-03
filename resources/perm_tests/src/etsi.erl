-module(etsi).

-export([result/0, procs/0, run/1]).

result() -> io:format("7").

procs() -> io:format("3").

run(Procs) ->
    [S] = io_lib:format("~p",[Procs]),
    initial(),
    run_aux(S),
    block().

run_aux([]) -> ok;
run_aux([P|R]) ->
    spawn(fun() -> proc(P) end),
    run_aux(R).

block() ->
    receive
    after infinity -> never
    end.

initial() ->
    ets:new(table, [public, named_table]),
    ets:insert(table, {x, 0}),
    ets:insert(table, {y, 0}),
    ets:insert(table, {z, 0}).

proc($1) -> fun_abc(x, y, z);
proc($2) -> fun_abc(y, z, x);
proc($3) -> fun_abc(z, x, y).

fun_abc(A, B, C) ->
    [{A, V}] = ets:lookup(table, A),
    case V of
        0 -> ets:insert(table, {B, 1});
        1 -> ets:insert(table, {C, 0})
    end.
