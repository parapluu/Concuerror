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
                   F(clef, souffle),
                   Self ! ok
          end),
    spawn(fun() -> F(key, eulav),
                   F(clef, elffuos),
                   Self ! ok
          end),
    receive
        ok ->
            [{key, V1}] = ets:lookup(Tid, key),
            [{clef, V2}] = ets:lookup(Tid, clef),
            case {V1, V2} of
                {new_value, souffle} -> ok;
                {eulav, elffuos} -> ok
            end
    end.
    
