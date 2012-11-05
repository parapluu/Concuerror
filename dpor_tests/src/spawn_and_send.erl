-module(spawn_and_send).

-export([spawn_and_send/0]).

spawn_and_send() ->
    spawn(fun() -> ok end) ! ok.
