-module(receive_pats).

-export([test1/0, test2/0, test3/0, test4/0]).
-export([scenarios/0]).

-concuerror_options([{use_receive_patterns, true}]).

scenarios() -> [{T, inf, dpor} || T <- [test1, test2, test3, test4]].

test1() ->
  P = self(),
  Fun1 =
    fun() ->
        P ! {foo, 1},
        P ! {bar, 1}
    end,
  Fun2 =
    fun() ->
        P ! {foo, 2}
    end,
  spawn(Fun1),
  spawn(Fun2),
  receive
    {foo, _A} -> ok
  end,
  receive
    {bar, _B} -> ok
  end.

test2() ->
  P = self(),
  Fun1 =
    fun() ->
        P ! {foo, 1},
        P ! {bar, 1}
    end,
  Fun2 =
    fun() ->
        P ! {foo, 2}
    end,
  spawn(Fun1),
  spawn(Fun2),
  receive
    {bar, _A} -> ok
  end,
  receive
    {foo, _B} -> ok
  end.

test3() ->
  P = self(),
  Fun1 =
    fun() ->
        P ! {foo, 1},
        P ! {bar, 1}
    end,
  Fun2 =
    fun() ->
        P ! {bar, 2}
    end,
  spawn(Fun1),
  spawn(Fun2),
  receive
    {foo, _A} -> ok
  end,
  receive
    {bar, _B} -> ok
  end.

test4() ->
  P = self(),
  Fun1 =
    fun() ->
        P ! {foo, 1},
        P ! {bar, 1}
    end,
  Fun2 =
    fun() ->
        P ! {bar, 2}
    end,
  spawn(Fun1),
  spawn(Fun2),
  receive
    {bar, _A} -> ok
  end,
  receive
    {foo, _B} -> ok
  end.
