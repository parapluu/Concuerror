-module(exit_kill).

-export([scenarios/0]).
-export([concuerror_options/0]).
-export([test/0]).

concuerror_options() ->
    [{treat_as_normal, kill}].

scenarios() ->
    [{test, inf, dpor}].

test() ->
    process_flag(trap_exit, true),
    Child = spawn_link(fun() -> exit(kill) end),
    receive
        {'EXIT', Child, kill} -> ok
    end.
            
