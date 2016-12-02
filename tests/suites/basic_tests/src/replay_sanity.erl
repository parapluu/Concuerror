-module(replay_sanity).

-export([replay_sanity/0]).
-export([scenarios/0]).

-concuerror_options_forced([{instant_delivery, false}]).

scenarios() -> [{?MODULE, inf, dpor}].

replay_sanity() ->
    Pid0 = spawn(fun() ->
                         receive {p, PidA} -> PidA ! ok end,
                         receive {p, PidB} -> PidB ! ok end,
                         receive {ok, _Pid} -> ok end
                 end),
    PidX = spawn(fun() -> receive ok -> ok end end),
    PidY = spawn(fun() -> receive ok -> ok end end),
    Pid0 ! {ok, self()},
    _PidK = spawn(fun() -> Pid0 ! {p, PidX} end),
    _PidL = spawn(fun() -> Pid0 ! {p, PidY} end),
    receive
    after
        infinity -> deadlock
    end.
