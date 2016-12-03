%%% @doc Two processes registering with the same name.
%%% @author Stavros Aronis <aronisstav@gmail.com>

-module(assert_filter).

-export([scenarios/0]).

-export([test/0]).

-concuerror_options_forced(
   [ {assertions_only, true}
   , {instant_delivery, false}]
 ).

-include_lib("eunit/include/eunit.hrl").

scenarios() ->
  [{test, inf, dpor}].

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
