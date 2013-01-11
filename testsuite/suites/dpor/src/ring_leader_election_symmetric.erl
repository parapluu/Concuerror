-module(ring_leader_election_symmetric).

-export([ring_leader_election_symmetric/0,
         ring_leader_election_symmetric/2]).
-export([scenarios/0]).

scenarios() -> [{?MODULE, inf, dpor}].

ring_leader_election_symmetric() ->
    ring_leader_election_symmetric(10, [2,3,9]).

ring_leader_election_symmetric(N, Leaders) ->
    Member1 = self(),
    ring_member(1, N, Leaders, Member1).

ring_member(I, N, Leaders, Member1) ->
    Link =
        case I =:= N of
            true -> Member1; %% Last member links to original.
            false -> spawn(fun() -> ring_member(I+1, N, Leaders, Member1) end)
        end,
    InitLeader =
        case lists:member(I, Leaders) of
            true -> Link ! I, I; %% Process tries to be leader
            false -> 0
        end,
    ring_member_loop(I, InitLeader, Link).

ring_member_loop(I, Leader, Link) ->
    receive
        {leader, Leader} = M ->
            case I =:= Leader of
                false -> Link ! M; %% Propagate the elected leader
                true -> ok %% Elected leader is propagated
            end;
        I ->
            case I =:= Leader of
                true -> Link ! {leader, I}; %% Leader informs everyone
                false -> ok %% Unelected leaders stay silent
            end,
            ring_member_loop(I, Leader, Link); %% Wait for {leader, L}
        J ->
            Link ! J, %% Propagate other leader suggestions
            NewLeader = max(J, Leader), %% Update own leader info
            ring_member_loop(I, NewLeader, Link)
    end.
