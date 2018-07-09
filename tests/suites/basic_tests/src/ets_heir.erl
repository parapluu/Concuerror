-module(ets_heir).

-compile(export_all).

scenarios() -> [{T, inf, dpor} || T <- [?MODULE, test, test1, test2]].

ets_heir() ->
    Heir = spawn(fun() -> ok end),
    ets:new(table, [named_table, {heir, Heir, heir}]),
    spawn(fun() ->
                  ets:lookup(table, x),
                  throw(too_bad)
          end).

test() ->
  P = self(),
  Q = spawn(fun() -> ets:new(foo, [named_table, {heir, P, fan}]) end),
  receive
    {'ETS-TRANSFER', foo, Q, fan} ->
      ok
  end.

test1() ->
  P = self(),
  Q = spawn(fun() ->
                ets:new(foo, [named_table]),
                ets:give_away(foo, P, fan)
            end),
  receive
    {'ETS-TRANSFER', foo, Q, fan} ->
      ok
  end.

test2() ->
  P = self(),
  ets:new(table, [named_table, {heir, P, bad}]),
  spawn(fun() ->
            ets:lookup(table, x)
        end).
