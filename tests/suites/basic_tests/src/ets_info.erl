-module(ets_info).

-compile(export_all).

scenarios() ->
  [ info_good
  , info_bad
  , info_system
  , info_badarg
  ].

info_badarg() ->
  try
    ets:info(1.0),
    exit(fail)
  catch
    error:badarg ->
      ok
  end.

info_system() ->
  true = undefined =/= ets:info(global_names).

info_bad() ->
  T = ets:new(foo, []),
  ets:delete(T),
  true = undefined =:= ets:info(T).

info_good() ->
  T = ets:new(foo, []),
  true = undefined =/= ets:info(T).
