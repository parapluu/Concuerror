-module(simple_delay).

-export([scenarios/0]).

-export([test/0]).

-define(TABLE, table).

scenarios() -> [{test, B, dpor} || B <- [0, 1, 2]].

test() ->
  ?TABLE = ets:new(?TABLE, [public, named_table]),
  write(x,0),
  Fun = fun(N) -> spawn(fun() -> work(N) end) end,
  lists:foreach(Fun, lists:seq(1, 10)),
  receive after infinity -> ok end.

work(N) ->
  write(x, 1),
  write(x, 2).

write(Key, Value) ->
  ets:insert(?TABLE, {Key, Value}).

read(Key) ->
  [{Key, V}] = ets:lookup(?TABLE, Key),
  V.
