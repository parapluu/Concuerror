#!/usr/bin/env escript
%%! -noshell

main([ThresholdString]) ->
  Threshold = list_to_integer(ThresholdString),
  Version =
    case erlang:system_info(otp_release) of
      "R" ++ _ -> 16;
      [D,U|_] -> list_to_integer([D,U])
    end,
  if Threshold < 17 ->
      to_stderr("This script is not suitable for checking for OTP versions < 17", []),
      flush_and_exit(2);
     Version < Threshold ->
      to_stderr("OTP version ~w is lower than the threshold ~w", [Version, Threshold]),
      flush_and_exit(1);
     true ->
      flush_and_exit(0)
  end.

to_stderr(Format, Data) ->
  io:format(standard_error, Format ++ "~n", Data).

flush_and_exit(N) ->
  erlang:yield(),
  erlang:halt(N).
