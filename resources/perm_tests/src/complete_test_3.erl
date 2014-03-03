-module(complete_test_3).

-export([result/0, procs/0, run/1]).

result() -> io:format("80").

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

-define(cover, ets:insert(table, {self(), ?LINE})).

proc($1) ->
    ?cover, ets:insert(table, {x, 1});
proc($2) ->
    ?cover, ets:insert(table, {z, 1});
proc($3) ->
    ?cover, [{y, Y}] = ets:lookup(table, y),
    case Y of
        0 -> ?cover, ets:lookup(table, x);
        _ -> ok
    end;
proc($4) ->
    ?cover, [{z, Z}] = ets:lookup(table, z),
    case Z of
        1 -> ?cover, ets:lookup(table, x);
        _ -> ok
    end,
    ?cover, ets:insert(table, {y, 1});
proc($5) ->
    ?cover, ets:insert(table, {x, 2});
proc($6) ->
    ?cover, ets:insert(table, {y, 2}).
