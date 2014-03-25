-module(is_process_alive_1).

-export([is_process_alive_1/0]).
-export([scenarios/0]).

scenarios() -> [{?MODULE, inf, dpor}].

is_process_alive_1() ->
    Pid = spawn(fun() -> ok end),
    case is_process_alive(Pid) of
        true -> register(child, Pid);
        false -> ok
    end.
