-module(a_fun).

-export([test/0]).

test() ->
  ThisIsAFun = fun() -> exit(error) end,
  P1 = spawn(fun() -> receive F -> F() end end),
  P1 ! ThisIsAFun.
