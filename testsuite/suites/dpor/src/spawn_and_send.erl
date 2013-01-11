-module(spawn_and_send).

-export([spawn_and_send/0]).
-export([scenarios/0]).

scenarios() -> [{?MODULE, inf, dpor}].

spawn_and_send() ->
    spawn(fun() -> ok end) ! ok.
