-module(indifferent_senders).

-export([indifferent_senders/0]).
-export([scenarios/0]).

scenarios() -> [{?MODULE, inf, dpor}].

indifferent_senders() ->
    Parent = self(),
    Messages = [msg1, msg2, msg3],
    [spawn(fun() -> Parent ! Msg end) || Msg <- Messages],
    receive_in_order(Messages),
    ok.

receive_in_order([]) -> ok;
receive_in_order([Msg|Rest]) ->
    receive
        Msg -> receive_in_order(Rest)
    end.
