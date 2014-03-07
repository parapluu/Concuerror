-module(etsi_7).

-export([etsi_7/0]).
-export([scenarios/0]).

scenarios() -> [{?MODULE, inf, dpor}].

etsi_7() ->
    Parent = self(),
    ets:new(table, [public, named_table]),
    ets:insert(table, {x, 0}),
    ets:insert(table, {y, 0}),
    ets:insert(table, {z, 0}),
    ets:insert(table, {z5, 0}),
    ets:insert(table, {xy, 0}),
    P1 =
        spawn(fun() ->
                      cover(?LINE),
                      ets:insert(table, {y, 1}),
                      receive
                          ok -> Parent ! ok
                      end
              end),
    P2 =
        spawn(fun() ->
                      cover(?LINE),
                      ets:insert(table, {x, 1}),
                      receive
                          ok -> P1 ! ok
                      end
              end),
    P3 =
        spawn(fun() ->
                      cover(?LINE),
                      [{x,Y}] = ets:lookup(table, x),
                      cover(?LINE),
                      case Y of
                          1 -> ok;
                          0 -> ets:insert(table, {z, 1})
                      end,
                      receive
                          ok -> P2 ! ok
                      end
              end),
    P4 =
        spawn(fun() ->
                      cover(?LINE),
                      [{x,X}] = ets:lookup(table, x),
                      cover(?LINE),
                      [{y,Y}] = ets:lookup(table, y),
                      ets:insert(table, {xy, {X,Y}}),
                      receive
                          ok -> P3 ! ok
                      end
              end),
    spawn(fun() ->
                  cover(?LINE),
                  [{z,Z}] = ets:lookup(table, z),
                  ets:insert(table, {z5, Z}),
                  P4 ! ok
          end),
    receive
        ok -> ok
    end,
    P3D = ets:lookup(table, z),
    P4D = ets:lookup(table, xy),
    P5D = ets:lookup(table, z5),
    throw(P3D++P4D++P5D).

cover(L) ->
    ets:insert(table, {L, ok}).
