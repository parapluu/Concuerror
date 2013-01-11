-module(process_flag_link).

-export([process_flag_link/0]).
-export([scenarios/0]).

scenarios() -> [{?MODULE, inf, dpor}].

process_flag_link() ->
    P = self(),
    process_flag(trap_exit, true),
    spawn(fun() -> P ! message end),
    spawn(fun() -> link(P) end),
    receive
        M1 ->
            receive
                _M2 ->
                    message = M1
            end
    end.
