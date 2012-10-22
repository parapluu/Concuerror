-module(spawn_and_send).

-compile(export_all).

spawn_and_send() ->
    spawn(fun() -> ok end) ! ok.
