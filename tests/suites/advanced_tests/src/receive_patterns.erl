-module(receive_patterns).

-export([test1/0, test2/0]).

-export([scenarios/0]).

-concuerror_options_forced([{use_receive_patterns, true}, {dpor, optimal}]).

%%------------------------------------------------------------------------------

scenarios() -> [{T, inf, optimal} || T <-[test1, test2]].

%%------------------------------------------------------------------------------

alpha(P, N) ->
  sender(P, {alpha, N}).

beta(P, N) ->
  sender(P, {beta, N}).

sender(Recipient, Msg) ->
  Recipient ! Msg.

test1() ->
  P = self(),
  spawn(fun() -> alpha(P, 1) end),
  spawn(fun() -> beta(P, 1) end),
  receive
    {alpha, _} -> ok;
    {beta, _} ->
      receive
        {alpha, _} -> ok
      end,
      spawn(fun() -> alpha(P, 2) end),
      spawn(fun() -> alpha(P, 3) end),
      spawn(fun() -> beta(P, 2) end),
      receive
        {alpha, _} ->
          receive
            {alpha, _} -> ok
          end
      end
  end.

test2() ->
  P = self(),
  spawn(fun() -> alpha(P, 1) end),
  spawn(fun() -> beta(P, 1) end),
  receive
    {alpha, _} -> ok;
    {beta, _} ->
      receive
        {alpha, _} -> ok
      end,
      spawn(fun() -> alpha(P, 2) end),
      spawn(fun() -> alpha(P, 3) end),
      spawn(fun() -> beta(P, 2) end),
      receive
        {alpha, _} -> ok
      end
  end.
