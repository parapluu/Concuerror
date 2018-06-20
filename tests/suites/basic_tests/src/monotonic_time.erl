-module(monotonic_time).

-export([test/0]).

-export([scenarios/0]).

-concuerror_options_forced([]).

%%------------------------------------------------------------------------------

scenarios() ->
  case get_current_otp() > 17 of
    true -> [{test, inf, optimal}];
    false -> []
  end.

get_current_otp() ->
  case erlang:system_info(otp_release) of
    "R" ++ _ -> 16; %% ... or earlier
    [D,U|_] -> list_to_integer([D,U])
  end.

%%------------------------------------------------------------------------------

test() ->
  P = self(),
  A = spawn(fun() -> P ! {self(), erlang:monotonic_time()} end),
  B = spawn(fun() -> P ! {self(), erlang:monotonic_time()} end),
  TA =
    receive
      {A, T1} -> T1
    end,
  TB =
    receive
      {B, T2} -> T2
    end,
  true = TA < TB.
