-module(after_test).

-export([after_test/0]).
-export([scenarios/0]).

scenarios() -> [{?MODULE, inf, dpor}].

after_test() ->
    allow_but_wait(0,2),
    Parent = self(),
    spawn(fun() -> Parent ! ok1 end),
    allow_but_wait(1,2),
    spawn(fun() -> Parent ! ok2 end),
    spawn(fun() -> Parent ! ok2 end),
    allow_but_wait(2,2),
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
