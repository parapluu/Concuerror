-module(depend_4_screen).

-export([depend_4_screen/0]).
-export([scenarios/0]).

scenarios() -> [{?MODULE, inf, dpor}].

depend_4_screen() ->
    ets:new(table, [public, named_table]),
    ets:insert(table, {x, 0}),
    ets:insert(table, {y, 0}),
    ets:insert(table, {z, 0}),
    P = self(),
    P1 = spawn(fun() -> ets:insert(table, {z, 1}), get_and_send( P) end),
    P2 = spawn(fun() -> ets:insert(table, {x, 1}), get_and_send(P1) end),
    P3 = spawn(fun() -> ets:insert(table, {y, 1}), get_and_send(P2) end),
    P4 = spawn(fun() ->
                       [{x, X}] = ets:lookup(table, x),
                       Val =
                           case X of
                               1 ->
                                   [{y, Y}] = ets:lookup(table, y),
                                   case Y of
                                       1 -> [{x,1},{y,1}|ets:lookup(table, z)];
                                       _ -> [{x,1},{y,0}]
                                   end;
                               _ -> [{x, X}]
                           end,
                       ets:insert(table, {p4, Val}),
                       get_and_send(P3)
               end),
    P5 = spawn(fun() ->
                       [{y, Y}] = ets:lookup(table, y),
                       Val =
                           case Y of
                               1 -> [{y,1}|ets:lookup(table, z)];
                               _ -> [{y,0}]
                           end,
                       ets:insert(table, {p5, Val}),
                       get_and_send(P4)
               end),
    P6 = spawn(fun() -> ets:insert(table, {x, 2}), get_and_send(P5) end),
    P6 ! ok,
    receive
        ok ->
            A = ets:lookup(table, x),
            B = ets:lookup(table, p5),
            C = ets:lookup(table, p4),
            throw({A,B,C})
    end.

get_and_send(P) ->
    receive
        ok -> P ! ok
    end.
