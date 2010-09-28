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
     fun() -> log:start(log, []) end,
     fun(_) -> log:stop() end,
     [{"test01",
       ?_assertMatch({ok, {{test, test01, []}, _}},
		     sched:analyze({test, test01, []},
			     [{files, [?TEST_ERL_PATH]}]))},
      {"test02",
       ?_assertMatch({ok, {{test, test02, []}, _}},
		     sched:analyze({test, test02, []},
			     [{files, [?TEST_ERL_PATH]}]))},
      {"test03",
       ?_assertMatch({ok, {{test, test03, []}, _}},
		     sched:analyze({test, test03, []},
			     [{files, [?TEST_ERL_PATH]}]))},
      {"test04",
       ?_test(
	  begin
	      Target = {test, test04, []},
	      Options = [{files, [?TEST_ERL_PATH]}],
	      {error, analysis, Info, [Ticket|_Tickets]} =
		  sched:analyze(Target, Options),
	      ?assertMatch({Target, {_, _}}, Info), 
	      ?assertEqual(Target, ticket:get_target(Ticket)),
	      ?assertEqual("Deadlock",
                           error:format_error_type(ticket:get_error(Ticket)))
	  end)},
      {"test05",
       ?_test(
	  begin
	      Target = {test, test05, []},
	      Options = [{files, [?TEST_ERL_PATH]}],
	      {error, analysis, Info, [Ticket|_Tickets]} =
		  sched:analyze(Target, Options),
	      ?assertMatch({Target, {_, _}}, Info), 
	      ?assertEqual(Target, ticket:get_target(Ticket)),
	      ?assertEqual("Deadlock",
                           error:format_error_type(ticket:get_error(Ticket)))
	  end)},
      {"test06",
       ?_assertMatch({ok, {{test, test06, []}, _}},
		     sched:analyze({test, test06, []},
			     [{files, [?TEST_ERL_PATH]}]))},
      {"test07",
       ?_assertMatch({ok, {{test, test07, []}, _}},
		     sched:analyze({test, test07, []},
			     [{files, [?TEST_ERL_PATH]}]))},
      {"test08",
       ?_test(
	  begin
	      Target = {test, test08, []},
	      Options = [{files, [?TEST_ERL_PATH]}],
	      {error, analysis, Info, [Ticket|_Tickets]} =
		  sched:analyze(Target, Options),
	      ?assertMatch({Target, {_, _}}, Info), 
	      ?assertEqual(Target, ticket:get_target(Ticket)),
	      ?assertEqual("Exception",
                           error:format_error_type(ticket:get_error(Ticket)))
	  end)},
      {"test09",
       ?_assertMatch({ok, {{test, test03, []}, _}},
		     sched:analyze({test, test03, []},
			     [{files, [?TEST_ERL_PATH,
				       ?TEST_AUX_ERL_PATH]}]))},
      {"test10",
       ?_assertMatch({ok, {{test, test09, []}, _}},
		     sched:analyze({test, test09, []},
			     [{files, [?TEST_ERL_PATH,
				       ?TEST_AUX_ERL_PATH]}]))},
      {"test11",
       ?_test(
	  begin
	      Target = {test, test10, []},
	      Options = [{files, [?TEST_ERL_PATH]}],
	      {error, analysis, Info, [Ticket|_Tickets]} =
		  sched:analyze(Target, Options),
	      ?assertMatch({Target, {_, _}}, Info), 
	      ?assertEqual(Target, ticket:get_target(Ticket)),
	      ?assertEqual("Assertion violation",
                           error:format_error_type(ticket:get_error(Ticket)))
	  end)},
      {"test12",
       ?_assertMatch({ok, {{test, test11, []}, _}},
		     sched:analyze({test, test11, []},
			     [{files, [?TEST_ERL_PATH,
				       ?TEST_AUX_ERL_PATH]}]))},
      {"test13",
       ?_assertMatch({ok, {{test, test12, []}, _}},
		     sched:analyze({test, test12, []},
			     [{files, [?TEST_ERL_PATH,
				       ?TEST_AUX_ERL_PATH]}]))},
      {"test14",
       ?_assertMatch({ok, {{test, test13, []}, _}},
		     sched:analyze({test, test13, []},
			     [{files, [?TEST_ERL_PATH,
				       ?TEST_AUX_ERL_PATH]}]))},
      {"test15",
       ?_test(
	  begin
	      Target = {test, test14, []},
	      Options = [{files, [?TEST_ERL_PATH]}],
	      {error, analysis, Info, [Ticket|_Tickets]} =
		  sched:analyze(Target, Options),
	      ?assertMatch({Target, {_, _}}, Info), 
	      ?assertEqual(Target, ticket:get_target(Ticket)),
	      ?assertEqual("Assertion violation",
                           error:format_error_type(ticket:get_error(Ticket)))
	  end)}
     ]}.
