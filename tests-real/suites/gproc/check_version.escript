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
      init:stop(2);
     Version < Threshold ->
      to_stderr("OTP version ~w is lower than the threshold ~w", [Version, Threshold]),
      init:stop(1);
     true ->
      init:stop(0)
  end.

to_stderr(Format, Data) ->
  io:format(standard_error, Format ++ "~n", Data).
