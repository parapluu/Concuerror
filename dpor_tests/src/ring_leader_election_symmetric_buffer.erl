-module(ring_leader_election_symmetric_buffer).

-export([ring_leader_election_symmetric_buffer/0,
         ring_leader_election_symmetric_buffer/2]).

ring_leader_election_symmetric_buffer() ->
    ring_leader_election_symmetric_buffer(3, [2,3]).

ring_leader_election_symmetric_buffer(N, Leaders) ->
    C = [Last|_] = [spawn(fun() -> channel() end) || _ <- lists:seq(1,N)],
    Channels = lists:reverse(C),
    ring_member(1, N, Leaders, Last, Channels).

ring_member(I, N, Leaders, From, [To|Rest]) ->
    Next =
        case I =:= N of
            true -> ok; %% Last member links to original.
            false -> spawn(fun() -> ring_member(I+1, N, Leaders, To, Rest) end)
        end,
    InitLeader =
        case lists:member(I, Leaders) of
            true -> channel_send(To,I), I; %% Process tries to be leader
            false -> 0
        end,
    ring_member_loop(I, InitLeader, From, To).

ring_member_loop(I, Leader, From, To) ->
    case channel_receive(From) of
        {leader, Leader} = M ->
            case I =:= Leader of
                false -> channel_send(To, M); %% Propagate the elected leader
                true -> ok %% Elected leader is propagated
            end,
            ok;
            %% channel_destroy(From); %% ... and exit.
        I ->
            case I =:= Leader of
                true -> channel_send(To,{leader, I}); %% Leader informs everyone
                false -> ok %% Unelected leaders stay silent
            end,
            ring_member_loop(I, Leader, From, To); %% Wait for {leader, L}
        J ->
            channel_send(To,J), %% Propagate other leader suggestions
            NewLeader = max(J, Leader), %% Update own leader info
            ring_member_loop(I, NewLeader, From, To)
    end.

channel() ->
    channel(queue:new(), queue:new()).

channel(Buffer, Requests) ->
    case queue:is_empty(Buffer) of
        true ->
            receive
                {put, M} ->
                    channel(queue:in(M,Buffer),Requests);
                {get, Pid} ->
                    channel(Buffer, queue:in(Pid,Requests));
                exit -> ok
            end;
        false ->
            case queue:is_empty(Requests) of
                false ->
                    {{value, Msg}, NewBuffer} = queue:out(Buffer),
                    {{value, Pid}, NewRequests} = queue:out(Requests),
                    Pid ! Msg,
                    channel(NewBuffer, NewRequests);
                true ->
                    receive
                        {put, M} ->
                            channel(queue:in(M,Buffer), Requests);
                        {get, Pid} ->
                            channel(Buffer, queue:in(Pid,Requests))
                    end
            end
    end.

channel_send(Chan, Msg) ->        
    Chan ! {put, Msg}.

channel_receive(Chan) ->
    Chan ! {get, self()},
    receive
        Ans -> Ans
    end.

channel_destroy(Chan) ->
    Chan ! exit.
