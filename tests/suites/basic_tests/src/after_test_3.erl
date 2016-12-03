-module(after_test_3).

-export([after_test_3/0]).
-export([scenarios/0]).

-concuerror_options_forced([{instant_delivery, false}]).

scenarios() -> [{?MODULE, inf, dpor}].

after_test_3() ->
    Parent = self(),
    Child =
        spawn(fun() ->
                  receive
                      Get1 ->
                          receive
                              Get2 ->
                                  throw({Get1, Get2})
                          end
                  end
              end),
    spawn(fun() ->
                  Child ! a,
                  Parent ! f
          end),
    Msg =
        receive
            f -> b
        after
            0 -> c
        end,
    Child ! Msg.
