-module(process_info).

-compile(export_all).

scenarios() ->
  [ links
  ].

links() ->
  P = self(),
  Fun = fun() -> whereis(name), link(P) end,
  Fun2 = fun() -> P ! foo, link(P) end,
  P1 = spawn(Fun),
  P2 = spawn(Fun2),
  receive foo -> ok end,
  process_info(self(), links),
  register(name, self()),
  receive after infinity -> ok end.
