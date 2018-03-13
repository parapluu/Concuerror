-module(message_queue_length).

-export([test/0]).

-export([scenarios/0]).

%%------------------------------------------------------------------------------

scenarios() -> [{test, inf, optimal}].

%%------------------------------------------------------------------------------

test() ->
  P = self(),
  spawn(fun() ->
            P ! one,
            P ! two
        end),
  receive
    two ->
      {message_queue_len, 1}
        = erlang:process_info(self(), message_queue_len)
  end.
