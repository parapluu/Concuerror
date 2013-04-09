-module(conditional_readers_3).

-export([result/0, procs/0, run/1]).

result() -> io:format("6").

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
    ets:insert(table, {y, 0}).

proc($1) ->
    ets:insert(table, {x, 1});
proc($2) ->
    [{y, Y}] = ets:lookup(table, y),
    case Y of
        0 -> ets:lookup(table, x);
        _ -> ok
    end;
proc($3) ->
    ets:lookup(table, x),
    ets:insert(table, {y, 1}).
