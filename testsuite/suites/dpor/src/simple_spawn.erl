-module(simple_spawn).

-export([simple_spawn/0]).
-export([scenarios/0]).

scenarios() -> [{?MODULE, inf, dpor}].

simple_spawn() ->
    spawn(fun() -> ok end).
