-module(renaming_2).

-export([test/0, find_me/0]).
-export([scenarios/0]).

scenarios() -> [{test, inf, X} || X <-[full, dpor]].

test() ->
    apply(renaming_2, find_me, []).

find_me() ->
    ok.
