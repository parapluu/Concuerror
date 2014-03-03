-module(depend_4_2).

-export([result/0, procs/0, run/1]).

result() -> io:format("20").

procs() -> io:format("6").

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

proc($1) ->
    ets:insert(table, {z, 1});
proc($2) ->
    ets:insert(table, {x, 1});
proc($3) ->
    ets:insert(table, {y, 1});
proc($4) ->
    [{x, X}] = ets:lookup(table, x),
    case X of
        1 ->
            [{y, Y}] = ets:lookup(table, y),
            case Y of
                1 -> ets:lookup(table, z);
                _ -> ok
            end;
        _ -> ok
    end;
proc($5) ->
    ets:lookup(table, y);
proc($6) ->
    ets:insert(table, {x, 2}).
