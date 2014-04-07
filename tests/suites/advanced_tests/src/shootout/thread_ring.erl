%%% The Computer Language Benchmarks Game
%%% http://shootout.alioth.debian.org/
%%% Contributed by Jiri Isa

-module(thread_ring).
-export([main/1, roundtrip/2, test1/0]).

-define(RING, 5).

start(Token) ->
   H = lists:foldl(
      fun(Id, Pid) -> spawn(thread_ring, roundtrip, [Id, Pid]) end,
      self(),
      lists:seq(?RING, 2, -1)),
   H ! Token,
   roundtrip(1, H).

roundtrip(Id, Pid) ->
   receive
      1 -> erlang:halt();
      Token ->
         Pid ! Token - 1,
         roundtrip(Id, Pid)
   end.

main([Arg]) ->
   Token = list_to_integer(Arg),
   start(Token).

test1() -> main(["10"]).
