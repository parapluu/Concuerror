-module(hopeless_after).

-export([hopeless_after/0]).
-export([scenarios/0]).

scenarios() -> [{?MODULE, inf, dpor}].

hopeless_after() ->
    P = self(),
    spawn(fun() -> P ! hopeless end),
    receive
        hope -> saved
    after
        100 ->
            throw(no_hope)
    end.
