%%%----------------------------------------------------------------------
%%% File        : sched_tests.erl
%%% Authors     : Alkis Gotovos <el3ctrologos@hotmail.com>
%%%               Maria Christakis <christakismaria@gmail.com>
%%% Description : Scheduler unit tests
%%% Created     : 25 Sep 2010
%%%----------------------------------------------------------------------

-module(sched_tests).

-include_lib("eunit/include/eunit.hrl").

-define(TEST_ERL_PATH, "./resources/test.erl").
-define(TEST_AUX_ERL_PATH, "./resources/test_aux.erl").

%% Spec for auto-generated test/0 function (eunit).
-spec test() -> 'ok' | {'error', term()}.


-spec interleave_test_() -> term().

interleave_test_() ->
    {setup,
     fun() -> log:start() end,
     fun(_) -> log:stop() end,
     [{"test01",
       ?_assertMatch({ok, {test, test01, []}},
		     sched:analyze({test, test01, []},
			     [{files, [?TEST_ERL_PATH]}]))},
      {"test02",
       ?_assertMatch({ok, {test, test02, []}},
		     sched:analyze({test, test02, []},
			     [{files, [?TEST_ERL_PATH]}]))},
      {"test03",
       ?_assertMatch({ok, {test, test03, []}},
		     sched:analyze({test, test03, []},
			     [{files, [?TEST_ERL_PATH]}]))},
      {"test04",
       ?_test(
	  begin
	      Target = {test, test04, []},
	      Options = [{files, [?TEST_ERL_PATH]}],
	      {error, analysis, Target, [Ticket|_Tickets]} =
		  sched:analyze(Target, Options),
	      ?assertEqual(Target, ticket:get_target(Ticket)),
	      ?assertEqual(deadlock, error:type(ticket:get_error(Ticket)))
	  end)},
      {"test05",
       ?_test(
	  begin
	      Target = {test, test05, []},
	      Options = [{files, [?TEST_ERL_PATH]}],
	      {error, analysis, Target, [Ticket|_Tickets]} =
		  sched:analyze(Target, Options),
	      ?assertEqual(Target, ticket:get_target(Ticket)),
	      ?assertEqual(deadlock, error:type(ticket:get_error(Ticket)))
	  end)},
      {"test06",
       ?_assertMatch({ok, {test, test06, []}},
		     sched:analyze({test, test06, []},
			     [{files, [?TEST_ERL_PATH]}]))},
      {"test07",
       ?_assertMatch({ok, {test, test07, []}},
		     sched:analyze({test, test07, []},
			     [{files, [?TEST_ERL_PATH]}]))},
      {"test08",
       ?_test(
	  begin
	      Target = {test, test08, []},
	      Options = [{files, [?TEST_ERL_PATH]}],
	      {error, analysis, Target, [Ticket|_Tickets]} =
		  sched:analyze(Target, Options),
	      ?assertEqual(Target, ticket:get_target(Ticket)),
	      ?assertEqual(exception, error:type(ticket:get_error(Ticket)))
	  end)},
      {"test09",
       ?_assertMatch({ok, {test, test03, []}},
		     sched:analyze({test, test03, []},
			     [{files, [?TEST_ERL_PATH,
				       ?TEST_AUX_ERL_PATH]}]))},
      {"test10",
       ?_assertMatch({ok, {test, test09, []}},
		     sched:analyze({test, test09, []},
			     [{files, [?TEST_ERL_PATH,
				       ?TEST_AUX_ERL_PATH]}]))},
      {"test11",
       ?_test(
	  begin
	      Target = {test, test09, []},
	      Options = [{files, [?TEST_ERL_PATH]}],
	      {error, analysis, Target, [Ticket|_Tickets]} =
		  sched:analyze(Target, Options),
	      ?assertEqual(Target, ticket:get_target(Ticket)),
	      ?assertEqual(exception, error:type(ticket:get_error(Ticket)))
	  end)},
      {"test12",
       ?_test(
	  begin
	      Target = {test, test10, []},
	      Options = [{files, [?TEST_ERL_PATH]}],
	      {error, analysis, Target, [Ticket|_Tickets]} =
		  sched:analyze(Target, Options),
	      ?assertEqual(Target, ticket:get_target(Ticket)),
	      ?assertEqual(assertion_violation,
                           error:type(ticket:get_error(Ticket)))
	  end)},
      {"test13",
       ?_assertMatch({ok, {test, test11, []}},
		     sched:analyze({test, test11, []},
			     [{files, [?TEST_ERL_PATH]}]))},
      {"test14",
       ?_assertMatch({ok, {test, test12, []}},
		     sched:analyze({test, test12, []},
			     [{files, [?TEST_ERL_PATH]}]))},
      {"test15",
       ?_assertMatch({ok, {test, test13, []}},
		     sched:analyze({test, test13, []},
			     [{files, [?TEST_ERL_PATH]}]))},
      {"test16",
       ?_test(
	  begin
	      Target = {test, test14, []},
	      Options = [{files, [?TEST_ERL_PATH]}],
	      {error, analysis, Target, [Ticket|_Tickets]} =
		  sched:analyze(Target, Options),
	      ?assertEqual(Target, ticket:get_target(Ticket)),
	      ?assertEqual(assertion_violation,
                           error:type(ticket:get_error(Ticket)))
	  end)},
      {"test17",
       ?_assertMatch({ok, {test, test15, []}},
		     sched:analyze({test, test15, []},
			     [{files, [?TEST_ERL_PATH]}]))},
      {"test18",
       ?_assertMatch({ok, {test, test16, []}},
		     sched:analyze({test, test16, []},
			     [{files, [?TEST_ERL_PATH]}]))},
      {"test19",
       ?_test(
	  begin
	      Target = {test, test17, []},
	      Options = [{files, [?TEST_ERL_PATH]}],
	      {error, analysis, Target, [Ticket|_Tickets]} =
		  sched:analyze(Target, Options),
	      ?assertEqual(Target, ticket:get_target(Ticket)),
	      ?assertEqual(deadlock,
                           error:type(ticket:get_error(Ticket)))
	  end)}
     ]}.
