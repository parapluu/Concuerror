-module(unsupported_exit).

-export([scenarios/0]).
-export([test/0]).

scenarios() ->
    [{test, inf, dpor, crash}].

test() ->
    try
        erlang:trace(all, true, all)
    catch
        _:_ -> ok
    end.
            
