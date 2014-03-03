-module(depend_6_2).

-export([result/0, procs/0, run/1]).

result() -> io:format("27").

procs() -> io:format("4").

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
    ets:insert(table, {y, 0}),
    ets:insert(table, {z, 0}).

proc($1) ->
    ets:lookup(table, y),
    ets:lookup(table, z);
proc($2) ->
    ets:lookup(table, y);
proc($3) ->
    ets:insert(table, {y, 1});
proc($4) ->
    ets:insert(table, {z, 1}),
    ets:insert(table, {y, 2}).
