-module(code_when_undef).

-compile(export_all).

scenarios() ->
  [ test
  ].

test() ->
  catch ets:non_existing_function(),
  code:module_info(),
  P = self(),
  spawn(fun() -> P ! ok end),
  receive
    ok -> ok
  after
    0 -> ok
  end,
  exit(error).
