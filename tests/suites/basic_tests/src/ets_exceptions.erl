-module(ets_exceptions).

-export([scenarios/0]).
-export([test/0]).

scenarios() -> [{test, inf, dpor}].

test() ->
  test(2).

test(N) ->
  table = ets:new(table, [public, named_table]),
  chain(N),
  true = [{key, N}] =/= ets:lookup(table, key).

chain(0) -> ok;
chain(N) ->
  Fun = fun() -> ets:insert(table, {key, N}) end,
  Q = spawn(Fun),
  chain(N - 1).
