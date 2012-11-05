-module(hopeless_after).

-export([hopeless_after/0]).

hopeless_after() ->
    P = self(),
    spawn(fun() -> P ! hopeless end),
    receive
        hope -> saved
    after
        100 ->
            throw(no_hope)
    end.
