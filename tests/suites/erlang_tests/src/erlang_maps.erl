-module(erlang_maps).

-compile(export_all).

scenarios() ->
  [ maps_fold ].

maps_fold() ->
  maps:fold(fun(_,_,Acc) -> Acc end, ok, #{}).
