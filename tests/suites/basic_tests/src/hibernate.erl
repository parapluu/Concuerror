-module(hibernate).

-compile(export_all).

scenarios() ->
  [ test
  ].

test() ->
  P = spawn(fun foo/0),
  P ! ok.

foo() ->
  try
    erlang:hibernate(?MODULE, resume, [])
  catch
    _:_ -> error(impossible)
  end.

resume() ->
  throw(possible).
