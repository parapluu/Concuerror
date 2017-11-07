-module(ring_leader_election).

-export([ring_leader_election/0, ring_leader_election/1]).
-export([scenarios/0]).

-concuerror_options_forced([{instant_delivery, false}]).

scenarios() -> [{?MODULE, inf, dpor}].

ring_leader_election() ->
    ring_leader_election(3).

ring_leader_election(N) ->
    Parent = self(),
    Pids = [spawn(fun() -> member(I, Parent) end) || I <- lists:seq(1, N)],
    [First|Rest] = Pids,
    Fold =
        fun(Pid, {Links, Last}) ->
                case Links of
                    [] ->
                        Pid ! {l, Last},
                        done;
                    [H|T] ->
                        Pid ! {l, H},
                        {T, Last}
                end
        end,
    done = lists:foldl(Fold, {Rest, First}, Pids),
    [receive {P, N} -> ok end || P <- Pids].

member(Id, Parent) ->
    receive
        {l, Link} ->
            Link ! Id,
            member_loop(Id, Id, Link, Parent)
    end.

member_loop(Id, Leader, Link, Parent) ->
    receive
        Id -> Parent ! {self(), Leader};
        NewId ->
            Link ! NewId,
            NewLeader = max(NewId, Leader),
            member_loop(Id, NewLeader, Link, Parent)
    end.
