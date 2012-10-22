-module(simple_spawn).

-compile(export_all).

simple_spawn() ->
    spawn(fun() -> ok end).
