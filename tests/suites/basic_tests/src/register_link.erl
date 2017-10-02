-module(register_link).

-export([test/0]).

-export([scenarios/0]).

%%------------------------------------------------------------------------------

scenarios() -> [{test, inf, optimal}].

%%------------------------------------------------------------------------------

test() ->
  P = spawn(fun() -> receive ok -> ok end end),
  {Reg, M1} = 
    spawn_monitor(
      fun() ->
          register(foo, P)
      end),
  {Link, M2} =
    spawn_monitor(
      fun() ->
          link(P)
      end),
  receive
    _ -> ok
  end,
  receive
    _ -> ok
  end,
  P ! ok.
