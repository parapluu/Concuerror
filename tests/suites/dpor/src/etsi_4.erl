-module(etsi_4).

-export([etsi_4/0]).
-export([scenarios/0]).

scenarios() -> [{?MODULE, inf, dpor}].

etsi_4() ->
    Parent = self(),
    ets:new(table, [public, named_table]),
    ets:insert(table, {x, 0}),
    ets:insert(table, {y, 0}),
    P1 = spawn(fun() ->
                       ets:insert(table, {y,1}),
                       receive _ -> Parent !
                                        ok
                       end
               end),
    P2 = spawn(fun() ->
                       [{x,_}] = ets:lookup(table,x),
                       [{y,_}] = ets:lookup(table,y),
                       receive _ -> P1 !
                                        ok
                       end
               end),
    spawn(fun() ->
                  ets:insert(table, {x,1}),
                  P2 !
                      ok
          end),
    receive _ -> ok end,
    receive
    after
        infinity -> ok
    end.
