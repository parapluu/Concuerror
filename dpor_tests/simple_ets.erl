-module(simple_ets).

-compile(export_all).

simple_ets() ->
    Tid = ets:new(simple_ets, [public]),
    Self = self(),
    F =
        fun(K,V) ->
            ets:insert(Tid, {K, V})
        end,
    spawn(fun() -> F(key, value),
                   F(key, new_value),
                   F(clef, souffle)
          end),
    spawn(fun() -> F(key, eulav),
                   F(clef, elffuos),
                   Self ! ok
          end),
    receive
        ok -> ok
    end.
    
