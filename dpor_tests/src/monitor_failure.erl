-module(monitor_failure).

-export([monitor_failure/0]).

monitor_failure() ->
    monitor(process, 1).
