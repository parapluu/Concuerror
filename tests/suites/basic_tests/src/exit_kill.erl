-module(exit_kill).

-export([scenarios/0]).
-export([test/0]).

-concuerror_options_forced([{treat_as_normal, kill}]).

scenarios() ->
    [{test, inf, dpor}].

test() ->
    process_flag(trap_exit, true),
    Child = spawn_link(fun() -> exit(kill) end),
    receive
        {'EXIT', Child, kill} -> ok
    end.
            
