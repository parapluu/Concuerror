-module(ets_insert_objects).

-export([ets_insert_objects/0]).
-export([scenarios/0]).

scenarios() -> [{?MODULE, inf, dpor}].

ets_insert_objects() ->
    T = ets:new(table, [public, named_table]),
    P1 = spawn(fun() ->
                       X = ets:lookup(T, x),
                       Y = ets:lookup(T, y),
                       Z = ets:lookup(T, z),
                       receive
                           _ -> throw({X,Y,Z})
                       end
               end),
    P2 = spawn(fun() ->
                       ets:insert(T, [{x,0},{y,0,0}]),
                       receive
                           _ -> P1 ! ok
                       end
               end),
    P3 = spawn(fun() ->
                       ets:insert(T, [{y,0},{z,0,0}]),
                       receive
                           _ -> P2 ! ok
                       end
               end),
    P4 = spawn(fun() ->
                       ets:insert(T, [{z,0},{x,0,0}]),
                       receive
                           _ -> P3 ! ok
                       end
               end),
    spawn(fun() ->
                  ets:insert(T, [{w,0},{q,0,0}]),
                  P4 ! ok
          end),
    receive
    after
        infinity -> ok
    end.
