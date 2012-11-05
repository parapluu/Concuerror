-module(normal_exit).

-export([normal_exit/0]).

normal_exit() ->
    exit(normal).
