-module(ets_insert_objects).

-export([ets_insert_objects/0]).

ets_insert_objects() ->
    P = self(),
    T = ets:new(table, [public, named_table]),
    spawn(fun() ->
                  ets:insert(T, [{x,0},{y,0,0}]),
                  P ! ok
          end),
    spawn(fun() ->
                  ets:insert(T, [{y,0},{z,0,0}]),
                  P ! ok
          end),
    spawn(fun() ->
                  ets:insert(T, [{z,0},{x,0,0}]),
                  P ! ok
          end),
    spawn(fun() ->
                  ets:insert(T, [{w,0},{q,0,0}]),
                  P ! ok
          end),
    X = ets:lookup(T, x),
    Y = ets:lookup(T, y),
    Z = ets:lookup(T, z),
    receive
        _ ->
            receive
                _ ->
                    receive
                        _ ->
                            receive
                                _ -> ok
                            end
                    end
            end
    end,
    throw({X,Y,Z}).



