-module(normal_exit).

-export([normal_exit/0]).
-export([scenarios/0]).

scenarios() -> [{?MODULE, inf, dpor}].

normal_exit() ->
    exit(normal).
