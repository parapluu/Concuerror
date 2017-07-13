-module(deliver_exhaustive).

-export([test/0]).

-export([scenarios/0]).

-concuerror_options_forced([{disable_sleep_sets,true},{instant_delivery,false}]).

%%------------------------------------------------------------------------------

scenarios() -> [{test, inf, none}].

%%------------------------------------------------------------------------------

p1() ->
  receive
    M -> M = first
  end.

p2(P1) ->
  receive
    M -> P1 ! M
  end.

test() ->
  Fun1 = fun() -> p1() end,
  {P1, M} = spawn_monitor(Fun1),
  Fun2 = fun() -> p2(P1) end,
  P2 = spawn(Fun2),
  P1 ! first,
  P2 ! second,
  receive
    {'DOWN', M, process, P1, Tag} -> Tag =/= normal
  end.
