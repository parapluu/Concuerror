-module(first_and_other_deadlock).

-export([test/0]).

test() ->
  CoinFlip =
    fun(Fun) ->
        fun() ->
            Palm = self(),
            spawn(fun() -> Palm ! coin end),
            receive
              coin -> Fun()
            after
              0 -> ok
            end
        end
    end,
  MessageWaiter =
    fun() ->
        receive
          ok -> ok
        end
    end,
  P = self(),
  MaybeDeadlock = spawn(MessageWaiter),
  CoinForNever = spawn(CoinFlip(fun() -> P ! ok end)),
  CoinForMaybe = spawn(CoinFlip(fun() -> MaybeDeadlock ! ok end)),
  MessageWaiter().
