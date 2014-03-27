-module(simple_ets).

-export([simple_ets/0]).
-export([scenarios/0]).

scenarios() -> [{?MODULE, inf, dpor}].

simple_ets() ->
    Tid = ets:new(simple_ets, [public, named_table]),
    P = self(),
    F =
        fun(K,V) ->
            ets:insert(Tid, {K, V})
        end,
    P1 = spawn(fun() -> F(key, value),
                        F(key, new_value),
                        F(clef, souffle),
                        receive
                            ok -> P ! ok
                        end
               end),
    P2 = spawn(fun() -> F(key, eulav),
                        F(clef, elffuos),
                        receive
                            ok -> P1 ! ok
                        end
               end),
    P2 ! ok,
    receive
        ok ->
            [{key, V1}] = ets:lookup(Tid, key),
            [{clef, V2}] = ets:lookup(Tid, clef),
            case {V1, V2} of
                {new_value, souffle} -> ok;
                {eulav, elffuos} -> ok
            end
    end.
