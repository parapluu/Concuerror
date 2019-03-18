%%% See test_template.erl for more details.

-module(timestamps).

-export([ exit_system_time0/0
        , exit_system_time1/0
        , exit_timestamp/0
        , other_system_time0/0
        , other_system_time1/0
        , other_timestamp/0
        ]).

-export([scenarios/0]).

%%------------------------------------------------------------------------------

scenarios() ->
  CurrentOTPRelease =
    case erlang:system_info(otp_release) of
      "R" ++ _ -> 16; %% ... or earlier
      [D,U|_] -> list_to_integer([D,U])
    end,
  case CurrentOTPRelease < 18 of
    true -> ok;
    false ->
      [{T, inf, optimal} ||
        {T, 0} <-
          ?MODULE:module_info(exports)
          , T =/= scenarios
          , T =/= module_info
      ]
  end.

%%------------------------------------------------------------------------------

exit_system_time0() ->
  spawn(fun() ->
            os:system_time()
        end).

exit_system_time1() ->
  spawn(fun() ->
            os:system_time(seconds)
        end).

exit_timestamp() ->
  spawn(fun() ->
            os:timestamp()
        end).

other_system_time0() ->
  spawn(fun() ->
            os:system_time()
        end),
  self() ! ok.

other_system_time1() ->
  spawn(fun() ->
            os:system_time(seconds)
        end),
  self() ! ok.

other_timestamp() ->
  spawn(fun() ->
            os:timestamp()
        end),
  self() ! ok.
