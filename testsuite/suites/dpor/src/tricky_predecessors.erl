-module(tricky_predecessors).

-export([tricky_predecessors/0]).
-export([scenarios/0]).

scenarios() -> [{?MODULE, inf, dpor}].

tricky_predecessors() ->
    Parent = self(),
    ets:new(table, [public, named_table]),
    ets:insert(table, {x, 0}),
    ets:insert(table, {l1, false}),
    ets:insert(table, {l2, false}),
    ets:insert(table, {l3, false}),
    L12K = {l1,l2},
    L23K = {l2,l3},
    L31K = {l3,l1},
    P1 = unlocker(l1, Parent),
    P2 = unlocker(l2, P1),
    P3 = unlocker(l3, P2),
    P4 = locked_reader(L12K, P3),
    P5 = locked_reader(L23K, P4),
    P6 = locked_reader(L31K, P5),
    P6 ! ok,
    ets:insert(table, {x, 1}),
    receive
        ok ->
            [{L12K, L12V}] = ets:lookup(table, L12K),
            [{L23K, L23V}] = ets:lookup(table, L23K),
            [{L31K, L31V}] = ets:lookup(table, L31K),
            List = [L12V, L23V, L31V],
            case lists:member(irrelevant, List) of
                true -> ok;
                false -> throw(List)
            end
    end.

locked_reader({A, B} = LK, Next) ->
    spawn(
      fun() ->
              [{A, AV}] = ets:lookup(table, A),
              [{B, BV}] = ets:lookup(table, B),
              LV =
                  case (AV andalso BV) of
                      true ->
                          [{x, XV}] = ets:lookup(table, x),
                          XV;
                      false ->
                          irrelevant
                  end,
              ets:insert(table, {LK, LV}),
              receive
                  ok -> Next ! ok
              end
      end).

unlocker(L, Next) ->
    spawn(
      fun() ->
              ets:insert(table, {L, true}),
              receive
                  ok -> Next ! ok
              end
      end).
