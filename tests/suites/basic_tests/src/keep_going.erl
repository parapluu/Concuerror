-module(keep_going).

-export([scenarios/0]).
-export([exceptional/0]).

-export([test/0]).

-concuerror_options_forced([{keep_going, false}]).

scenarios() ->
    [{test, inf, dpor}].

exceptional() ->
  fun(_Expected, Actual) ->
      Cmd = "grep \"Stop testing on first error. (Check '-h keep_going').\" ",
      [_,_,_|_] = os:cmd(Cmd ++ Actual),
      true
  end.

test() ->
    P = self(),
    spawn(fun() -> P ! ok end),
    spawn(fun() -> P ! ok end),
    spawn(fun() -> P ! ok end),
    receive
        ok -> ok
    after
      0 ->
        receive
          ok -> exit(error)
        after
          0 ->
            receive
              ok -> ok
            after
              0 -> ok
            end
        end
    end.
