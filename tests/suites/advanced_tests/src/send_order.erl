-module(send_order).
-export([test1/0, test2/0]).

%%% See https://github.com/parapluu/Concuerror/issues/77

-export([scenarios/0]).
-export([exceptional/0]).

scenarios() ->
  [{T, inf, dpor, crash} || T <- [test1, test2]].

exceptional() ->
  fun(_Expected, Actual) ->
      Cmd = "grep \"Module crypto contains a call to erlang:load_nif/2.\" ",
      [_,_,_|_] = os:cmd(Cmd ++ Actual),
      true
  end.

test1() ->
    Orig = [I || <<I>> <= crypto:strong_rand_bytes(5)],
    Master = self(),
    [spawn(fun() -> Master ! I end) || I <- Orig],
    Orig = [receive I -> I end || _ <- Orig].

test2() ->
    Orig = [I || <<I>> <= crypto:strong_rand_bytes(5)],
    Master = self(),
    Sorted = lists:sort(Orig),
    [spawn(fun() -> timer:sleep(I), Master ! I end) || I <- Orig],
    Sorted = [receive I -> I end || _ <- Orig].
