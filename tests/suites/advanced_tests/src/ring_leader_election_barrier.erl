-module(ring_leader_election_barrier).

-export([ring_leader_election_barrier/0, ring_leader_election_barrier/1]).
-export([scenarios/0]).

-concuerror_options_forced([{instant_delivery, false}]).

scenarios() -> [{?MODULE, inf, dpor}].

ring_leader_election_barrier() ->
    ring_leader_election_barrier(3).

ring_leader_election_barrier(N) ->
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
    [receive {P, ok} -> ok end || P <- Pids],
    [P ! go || P <- Pids],
    [receive {P, N} -> ok end || P <- Pids].

member(Id, Parent) ->
    receive
        {l, Link} ->
            Parent ! {self(), ok},
            receive
                go -> ok
            end,
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
