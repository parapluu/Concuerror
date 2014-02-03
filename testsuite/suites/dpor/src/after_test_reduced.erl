-module(after_test_reduced).

-export([after_test_reduced/0]).
-export([scenarios/0]).

scenarios() -> [{?MODULE, inf, dpor}].

after_test_reduced() ->
    Parent = self(),
    spawn(fun() -> Parent ! ok2 end),
    spawn(fun() -> Parent ! ok2 end),
    allow_but_wait(2,1),
    receive
        deadlock -> ok
    end.

allow_but_wait(0, _) -> crash_if_mail();
allow_but_wait(N, 0) ->
    receive
        _ -> allow_but_wait(N-1, 0)
    end;
allow_but_wait(N, M) ->
    receive
        _ -> allow_but_wait(N-1, M)
    after
        0 -> allow_but_wait(N, M-1)
    end.

crash_if_mail() ->
    receive
        Any -> throw(Any)
    after
        0 -> ok
    end.
