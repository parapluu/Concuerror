-module(log_all).

-export([test/0]).
-export([scenarios/0]).
-export([exceptional/0]).

-concuerror_options_forced([log_all]).

scenarios() -> [{test, inf, dpor}].

exceptional() ->
  fun(_Expected, Actual) ->
      Cmd = "grep \"Event trace\" ",
      case os:cmd(Cmd ++ Actual) of
        [_,_,_|_] -> true;
        _ -> false
      end
  end.

test() ->
    P = self(),
    Q = spawn(fun() -> receive A -> A ! ok end end),
    S = spawn(fun() -> receive _ -> ok after 100 -> ok end end),
    Q ! S,
    S ! ok.
