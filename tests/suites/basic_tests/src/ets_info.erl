-module(ets_info).

-compile(export_all).

-include_lib("eunit/include/eunit.hrl").

scenarios() ->
  [ info_good
  , info_bad
  , info_system
  , info_badarg
  , info_2_badarg
  ].

info_badarg() ->
  try
    ets:info(1.0),
    exit(fail)
  catch
    error:badarg ->
      ok
  end.

info_2_badarg() ->
  try
    ets:info([om,nom], owner),
    exit(fail)
  catch
    error:badarg ->
      ok
  end.

info_system() ->
  ?assertNotEqual(undefined, ets:info(global_names)).

info_bad() ->
  T = ets:new(foo, []),
  ets:delete(T),
  ?assertEqual(undefined, ets:info(T)),
  ?assertEqual(undefined, ets:info(T, owner)).

info_good() ->
  T = ets:new(foo, []),
  ?assertNotEqual(undefined, ets:info(T)).
