%%% @doc Two processes registering with the same name.
%%% @author Stavros Aronis <aronisstav@gmail.com>

-module(assert_tip).

-export([scenarios/0]).
-export([exceptional/0]).

-export([test/0]).

-include_lib("eunit/include/eunit.hrl").

scenarios() ->
  [{test, inf, dpor}].

exceptional() ->
  fun(_Expected, Actual) ->
      Cmd = "grep \"you can use the '--assertions_only' option\" ",
      [_,_,_|_] = os:cmd(Cmd ++ Actual),
      true
  end.

test() ->

  Parent = self(),

  Fun =
    fun() ->
        Result =
          try
            register(same_name, self())
          catch
            error:badarg -> false
          end,
        Parent ! {self(), Result}
    end,

  P1 = spawn(Fun),
  P2 = spawn(Fun),

  receive
    {P1, First} ->
      receive
        {P2, Second} ->
          ?assert(First andalso Second)
      end
  end,
  exit(hate).
