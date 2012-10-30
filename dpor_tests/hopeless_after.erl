-module(hopeless_after).

-compile(export_all).

hopeless_after() ->
    P = self(),
    spawn(fun() -> P ! hopeless end),
    receive
        hope -> saved
    after
        100 ->
            throw(no_hope)
    end.
