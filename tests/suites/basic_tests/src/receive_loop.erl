-module(receive_loop).

-export([test/0]).

-export([scenarios/0]).
-export([exceptional/0]).

-concuerror_options_forced([{keep_going, false}, {depth_bound, 80}]).

%%------------------------------------------------------------------------------

scenarios() -> [{test, inf}].

exceptional() ->
  fun(_Expected, Actual) ->
      Cmd = "grep \"a 'receive loop' using a timeout can lead to an infinite execution\" ",
      [_,_,_|_] = os:cmd(Cmd ++ Actual),
      true
  end.

%%------------------------------------------------------------------------------

test() ->
  P = self(),
  spawn(fun() -> P ! ok end),
  loop().

loop() ->
  receive
    ok -> ok
  after
    50 -> loop()
  end.
