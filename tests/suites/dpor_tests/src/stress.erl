-module(stress).

-export([stress/0]).
-export([scenarios/0]).

scenarios() -> [{?MODULE, inf, dpor}].

stress() ->
    Me = self(),
    Rcvr = spawn(fun() -> rcvr(3, Me) end),
    spawn(fun() -> creator(Me, Rcvr) end),
    receive
        ok ->
            receive
                ok ->
                    _B = spawn(sender(Rcvr, ok2)),
                    _C = spawn(sender(Rcvr, ok2))
            end
    end,
    receive
        ok -> worked
    end.

sender(To, What) ->
    fun() -> To ! What end.

rcvr(0, Mother) ->
    Mother ! ok;
rcvr(N, Mother) ->
    receive
        _ -> rcvr(N - 1, Mother)
    end.

creator(Mother, Rcvr) ->
    _A = spawn(sender(Rcvr, ok1)),
    _Unblocker1 = spawn(sender(Mother, ok)),
    _Unblocker2 = spawn(sender(Mother, ok)).
