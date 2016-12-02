-module(preemption).

-export([preemption/0]).
-export([scenarios/0]).

-concuerror_options_forced([{instant_delivery, false}, {scheduling, oldest}]).

scenarios() -> [{?MODULE, inf, dpor}].

-define(senders, 2).
-define(receivers, 2).

preemption() ->
    Parent = self(),
    Receivers = spawn_receivers(?senders, ?receivers),
    Senders = spawn_senders(?senders, Receivers, Parent),
    wait_senders(Senders),
    trigger_receivers(Receivers),
    receive
        deadlock -> ok
    end.

spawn_receivers(Senders, N) ->
    [spawn(fun() -> receiver(Senders) end) || _ <- lists:seq(1,N)].

receiver(N) ->
    receive
        go ->
            receiver(N,[])
    end.

receiver(0, Acc) -> Acc;
receiver(N, Acc) ->
    receive
        I -> receiver(N-1, [I|Acc])
    end.

spawn_senders(N, Receivers, Parent) ->
    [spawn(fun() -> sender(I, Receivers, Parent) end)
     || I <- lists:seq(1,N)].

sender(I, Receivers, Parent) ->
    [R ! I-1 || R <- Receivers],
    Parent ! {sender, self()}.

wait_senders([]) -> ok;
wait_senders([P|R]) ->
    receive
        {sender, P} ->
            wait_senders(R)
    end.

trigger_receivers(Receivers) ->
    [R ! go || R <- Receivers].
