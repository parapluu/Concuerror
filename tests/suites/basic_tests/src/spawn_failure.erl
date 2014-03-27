-module(spawn_failure).

-export([spawn_failure/0]).
-export([scenarios/0]).

scenarios() -> [{?MODULE, inf, dpor}].

spawn_failure() ->
    spawn(2).
