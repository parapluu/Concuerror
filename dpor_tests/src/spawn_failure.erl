-module(spawn_failure).

-export([spawn_failure/0]).

spawn_failure() ->
    spawn(2).
