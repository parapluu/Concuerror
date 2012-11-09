-module(ets_dependencies_n).

-export([ets_dependencies_n/0,
         ets_dependencies_n/1]).

ets_dependencies_n() ->
    ets_dependencies_n(3).

ets_dependencies_n(Readers) ->
    Parent = self(),
    ets:new(table, [public, named_table]),
    ets:insert(table, {hot, 0}),
    Writer =
        fun() ->
            ets:insert(table, {hot, 1}),
            Parent ! ok
        end,
    Reader =
        fun(N) ->
            ets:insert(table, {N, 1}),
            ets:lookup(table, hot),
            Parent ! ok    
        end,
    spawn(Writer),
    [spawn(fun() -> Reader(I) end) || I <- lists:seq(1, Readers)],
    [receive _ -> ok end || _ <- lists:seq(1, Readers+1)],
    receive
        _ -> deadlock
    end.
