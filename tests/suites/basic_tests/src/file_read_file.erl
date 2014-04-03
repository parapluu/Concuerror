-module(file_read_file).

-export([scenarios/0]).
-export([test/0]).

scenarios() ->
    [{test, inf, dpor}].

test() ->
    spawn(fun() -> file:get_cwd() end),
    file:get_cwd().
