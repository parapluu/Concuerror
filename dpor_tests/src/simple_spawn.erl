-module(simple_spawn).

-export([simple_spawn/0]).

simple_spawn() ->
    spawn(fun() -> ok end).
