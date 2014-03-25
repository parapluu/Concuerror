-module(monitor_failure).

-export([monitor_failure/0]).
-export([scenarios/0]).

scenarios() -> [{?MODULE, inf, dpor}].

monitor_failure() ->
    monitor(process, 1).
