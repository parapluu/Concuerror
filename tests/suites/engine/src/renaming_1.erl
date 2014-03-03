-module(renaming_1).

-export([test/0, find_me/0]).
-export([scenarios/0]).

scenarios() -> [{test, inf, X} || X <-[full, dpor]].

test() ->
    apply(renaming_1, find_me, []).

find_me() ->
    ok.
