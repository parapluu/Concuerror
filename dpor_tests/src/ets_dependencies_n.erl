-module(ets_dependencies_n).

-export([ets_dependencies_n/0,
         ets_dependencies_n/1]).

ets_dependencies_n() ->
    ets_dependencies_n(3).

ets_dependencies_n(Readers) ->
    Parent = self(),
    ets:new(table, [public, named_table]),
    Writer =
        fun() ->
            ets:insert(table, {x, 42}),
            Parent ! ok
        end,
    Reader =
        fun(N) ->
            ets:lookup(table, N),
            ets:lookup(table, x),
            Parent ! ok    
        end,
    spawn(Writer),
    [spawn(fun() -> Reader(I) end) || I <- lists:seq(1, Readers)],
    [receive _ -> ok end || _ <- lists:seq(1, Readers+1)],
    receive
        _ -> deadlock
    end.
