-module(send_order).
-export([test1/0, test2/0]).

%%% See https://github.com/parapluu/Concuerror/issues/77

-export([scenarios/0]).

scenarios() ->
  [{T, inf, dpor, crash} || T <- [test1, test2]].

test1() ->
    Orig = [I || <<I>> <= crypto:rand_bytes(128)],
    Master = self(),
    [spawn(fun() -> Master ! I end) || I <- Orig],
    Orig = [receive I -> I end || _ <- Orig].

test2() ->
    Orig = [I || <<I>> <= crypto:rand_bytes(128)],
    Master = self(),
    Sorted = lists:sort(Orig),
    [spawn(fun() -> timer:sleep(I), Master ! I end) || I <- Orig],
    Sorted = [receive I -> I end || _ <- Orig].
