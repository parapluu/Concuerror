-module(register_again).

-export([register_again/0]).

register_again() ->
    register(bank, self()),
    spawn(fun() -> bank ! money end),
    spawn(fun() ->
                  unregister(bank),
                  register(bank, self()),
                  receive
                      money -> robber_got_money
                  after
                      0 -> robbery_failed
                  end
          end),
    receive
        money -> bank_got_money
    end.
                  
