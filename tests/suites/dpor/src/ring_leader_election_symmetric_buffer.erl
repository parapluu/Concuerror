-module(ring_leader_election_symmetric_buffer).

-export([ring_leader_election_symmetric_buffer/0,
         ring_leader_election_symmetric_buffer/2]).
-export([scenarios/0]).

scenarios() -> [{?MODULE, inf, dpor}].

ring_leader_election_symmetric_buffer() ->
    ring_leader_election_symmetric_buffer(3, [1]).

ring_leader_election_symmetric_buffer(N, Leaders) ->
    [Last|Rest] = [spawn(fun() -> channel() end) || _ <- lists:seq(1,N)],
    Channels = Rest ++ [Last],
    ring_member(1, N, Leaders, Last, Channels).

ring_member(I, N, Leaders, From, [To|Rest]) ->
    case I =:= N of
        true -> ok; %% Last member links to original.
        false -> spawn(fun() -> ring_member(I+1, N, Leaders, To, Rest) end)
    end,
    Name = my_name(I),
    register(Name, self()),
    InitLeader =
        case lists:member(I, Leaders) of
            true -> channel_send(To,I), I; %% Process tries to be leader
            false -> 0
        end,
    ring_member_loop(I, Name, InitLeader, From, To).

my_name(I) ->
    list_to_atom(lists:flatten(io_lib:format("p~w",[I]))).

ring_member_loop(I, Name, Leader, From, To) ->
    case channel_receive(Name, From) of
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
            ring_member_loop(I, Name, Leader, From, To); %% Wait for {leader, L}
        J ->
            channel_send(To,J), %% Propagate other leader suggestions
            NewLeader = max(J, Leader), %% Update own leader info
            ring_member_loop(I, Name, NewLeader, From, To)
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

channel_receive(Name, Chan) ->
    Chan ! {get, Name},
    receive
        Ans -> Ans
    end.
