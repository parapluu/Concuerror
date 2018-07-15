-module(eunit_sample).

-include_lib("eunit/include/eunit.hrl").

-export([concuerror_tests/0]).

-export([concuerror_entry_point_tests/0]).

concuerror_tests() ->
  eunit:test(
    [{test, ?MODULE, T} ||
      T <-
        [ foo_concuerror_test
        , msg_concuerror_test
        , reg_concuerror_test
        ]
    ]
   ).

concuerror_entry_point_tests() ->
  eunit:test(
    [{test, ?MODULE, T} ||
      T <-
        [ foo_ep_concuerror_test
        , msg_ep_concuerror_test
        ]
    ]
   ).

%%==============================================================================

foo_test() ->
  ?assert(true).

msg_test() ->
  P = self(),
  spawn(fun() -> P ! foo end),
  spawn(fun() -> P ! bar end),
  receive
    Msg -> ?assertEqual(foo, Msg)
  end.

reg_test() ->
  Fun =
    fun() ->
        receive message -> ok
        after 100 -> timeout
        end
    end,
  P = spawn(Fun),
  register(p, P),
  p ! message,
  ?assert(true).

%%==============================================================================

-define(concuerror_options, [{module, ?MODULE}, quiet]).

foo_concuerror_test() ->
  ?assertEqual(ok, concuerror:run([{test, foo_test}|?concuerror_options])).

msg_concuerror_test() ->
  ?assertEqual(error, concuerror:run([{test, msg_test}|?concuerror_options])).

reg_concuerror_test() ->
  ?assertEqual(error, concuerror:run([{test, reg_test}|?concuerror_options])).

%%==============================================================================

foo_ep_concuerror_test() ->
  ?assertEqual(ok, concuerror:run([quiet, {entry_point, {?MODULE, foo_test, []}}])).

msg_ep_concuerror_test() ->
  ?assertEqual(error, concuerror:run([quiet, {entry_point, {?MODULE, msg_test, []}}])).
