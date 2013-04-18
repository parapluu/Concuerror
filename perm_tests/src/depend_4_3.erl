-module(depend_4_3).

-export([result/0, procs/0, run/1]).

result() -> io:format("16").

procs() -> io:format("5").

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
    ets:insert(table, {y, 1});
proc($3) ->
    [{x, X}] = ets:lookup(table, x),
    case X of
        1 -> ets:lookup(table, y);
        _ -> ok
    end;
proc($4) ->
    ets:lookup(table, y);
proc($5) ->
    ets:insert(table, {x, 2}).
