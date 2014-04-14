%%% Inspired by "Cartesian Partial-Order Reduction" paper

-module(shared_ptr).

-export([shared_ptr/0]).
-export([scenarios/0]).

-define(N, 25).

scenarios() -> [{?MODULE, inf, dpor}].

shared_ptr() ->
    ets:new(table, [public, named_table]),
    ets:insert(table, {x, 3}),
    ets:insert(table, {y, 4}),
    ets:insert(table, {c1, 0}),
    ets:insert(table, {c2, 0}),
    ets:insert(table, {p, foo}),
    Parent = self(),
    P1 = spawn(fun() -> shared_ptr(y, x, c1, 3, Parent) end),
    P2 =spawn(fun() -> shared_ptr(x, y, c2, 2, P1) end),
    P2 ! ok,
    receive
        ok -> ok
    end.

shared_ptr(Key1, Key2, CKey, Amount, Chain) ->
    ets:insert(table, {p, Key1}),
    repeat(CKey, Key2, ?N),
    [{p, Key3}] = ets:lookup(table, p),
    [{Key3, V}] = ets:lookup(table, Key3),
    ets:insert(table, {Key3, V + Amount}),
    assertion(),
    receive
        ok -> Chain ! ok
    end.

repeat(_CKey, _Key, 0) -> ok;
repeat(CKey, Key, N) ->
    [{CKey, V1}] = ets:lookup(table, CKey),
    [{Key, V2}] = ets:lookup(table, Key),
    ets:insert(table, {CKey, V1 + V2}),
    repeat(CKey, Key, N-1).

assertion() ->
    [{x, V1}] = ets:lookup(table, x),
    [{y, V2}] = ets:lookup(table, y),
    Max = max(V1, V2),
    Min = min(V1, V2),
    if Max > 9 -> throw(error);
       Min < 3 -> throw(error);
       true -> ok
    end.
