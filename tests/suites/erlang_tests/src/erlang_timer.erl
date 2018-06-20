-module(erlang_timer).

-compile(export_all).

scenarios() ->
  [ cancel_badarg
  , read_badarg
  , cancel_bad
  , read_bad
  ].

cancel_badarg() ->
  try
    erlang:cancel_timer(1),
    exit(bad)
  catch
    error:badarg -> ok
  end.

read_badarg() ->
  try
    erlang:cancel_timer(1),
    exit(bad)
  catch
    error:badarg -> ok
  end.

cancel_bad() ->
  true = false =:= erlang:cancel_timer(make_ref()).

read_bad() ->
  true = false =:= erlang:cancel_timer(make_ref()).
