-module(module_loaded_dep).

-compile(export_all).

scenarios() ->
  [ test
  ].

test() ->
  P = spawn(fun() -> erlang:module_loaded(erlang) end),
  spawn(fun() -> P ! ok end).
