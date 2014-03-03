-module(register_again).

-export([register_again/0]).
-export([scenarios/0]).

scenarios() -> [{?MODULE, inf, dpor}].

register_again() ->
    Bank = self(),
    register(bank, Bank),
    _Customer = spawn(fun() -> bank ! money end),
    God =
        spawn(fun() ->
                      receive
                          _Msg -> money_changed_hands
                      end
              end),
    _Robber =
        spawn(fun() ->
                      unregister(bank),
                      register(bank, self()),
                      receive
                          money -> God ! robber_got_money
                      after
                          0 -> robbery_failed
                      end
              end),
    receive
        money -> God ! bank_got_money
    end.
