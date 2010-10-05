%%%----------------------------------------------------------------------
%%% File        : preb_tests.erl
%%% Authors     : Alkis Gotovos <el3ctrologos@hotmail.com>
%%%               Maria Christakis <christakismaria@gmail.com>
%%% Description : Preemption bounding unit tests
%%% Created     : 28 Sep 2010
%%%----------------------------------------------------------------------

-module(preb_tests).

-include_lib("eunit/include/eunit.hrl").

-define(TEST_ERL_PATH, "./resources/test.erl").
-define(TEST_AUX_ERL_PATH, "./resources/test_aux.erl").

%% Spec for auto-generated test/0 function (eunit).
-spec test() -> 'ok' | {'error', term()}.

%% Analyzing with an infinite preemption bound gives the same results
%% as analyzing without using preemption bounding.
-spec preemption_bounding_test_() -> term().

preemption_bounding_test_() ->
    {setup,
     fun() -> log:start() end,
     fun(_) -> log:stop() end,
     [{"test01",
       ?_test(
	  begin
	      Target = {test, test01, []},
	      Files = {files, [?TEST_ERL_PATH]},
	      Options = [Files],
	      OptionsPreb = [Files, {preb, infinite}],
	      Result = sched:analyze(Target, Options),
	      ResultPreb = sched:analyze(Target, OptionsPreb),
	      ?assertEqual(Result, ResultPreb)
	  end)},
      {"test02",
       ?_test(
	  begin
	      Target = {test, test02, []},
	      Files = {files, [?TEST_ERL_PATH]},
	      Options = [Files],
	      OptionsPreb = [Files, {preb, infinite}],
	      Result = sched:analyze(Target, Options),
	      ResultPreb = sched:analyze(Target, OptionsPreb),
	      ?assertEqual(Result, ResultPreb)
	  end)},
      {"test03",
       ?_test(
	  begin
	      Target = {test, test03, []},
	      Files = {files, [?TEST_ERL_PATH]},
	      Options = [Files],
	      OptionsPreb = [Files, {preb, infinite}],
	      Result = sched:analyze(Target, Options),
	      ResultPreb = sched:analyze(Target, OptionsPreb),
	      ?assertEqual(Result, ResultPreb)
	  end)},
      {"test04",
       ?_test(
	  begin
	      Target = {test, test04, []},
	      Files = {files, [?TEST_ERL_PATH]},
	      Options = [Files],
	      OptionsPreb = [Files, {preb, infinite}],
	      Result = sched:analyze(Target, Options),
	      ResultPreb = sched:analyze(Target, OptionsPreb),
	      ?assertEqual(Result, ResultPreb)
	  end)},
      {"test05",
       ?_test(
	  begin
	      Target = {test, test05, []},
	      Files = {files, [?TEST_ERL_PATH]},
	      Options = [Files],
	      OptionsPreb = [Files, {preb, infinite}],
	      Result = sched:analyze(Target, Options),
	      ResultPreb = sched:analyze(Target, OptionsPreb),
	      ?assertEqual(Result, ResultPreb)
	  end)},
      {"test06",
       ?_test(
	  begin
	      Target = {test, test06, []},
	      Files = {files, [?TEST_ERL_PATH]},
	      Options = [Files],
	      OptionsPreb = [Files, {preb, infinite}],
	      Result = sched:analyze(Target, Options),
	      ResultPreb = sched:analyze(Target, OptionsPreb),
	      ?assertEqual(Result, ResultPreb)
	  end)},
      {"test07",
       ?_test(
	  begin
	      Target = {test, test07, []},
	      Files = {files, [?TEST_ERL_PATH]},
	      Options = [Files],
	      OptionsPreb = [Files, {preb, infinite}],
	      Result = sched:analyze(Target, Options),
	      ResultPreb = sched:analyze(Target, OptionsPreb),
	      ?assertEqual(Result, ResultPreb)
	  end)},
      {"test08",
       ?_test(
	  begin
	      Target = {test, test08, []},
	      Files = {files, [?TEST_ERL_PATH]},
	      Options = [Files],
	      OptionsPreb = [Files, {preb, infinite}],
	      {error, analysis, Target, [Ticket]} =
		  sched:analyze(Target, Options),
	      {error, analysis, Target, [TicketPreb]} =
		  sched:analyze(Target, OptionsPreb),
	      State = ticket:get_state(Ticket),
	      StatePreb = ticket:get_state(TicketPreb),
	      ?assertEqual(State, StatePreb)
	  end)},
      {"test09",
       ?_test(
	  begin
	      Target = {test, test03, []},
	      Files = {files, [?TEST_ERL_PATH]},
	      Options = [Files],
	      OptionsPreb = [Files, {preb, infinite}],
	      Result = sched:analyze(Target, Options),
	      ResultPreb = sched:analyze(Target, OptionsPreb),
	      ?assertEqual(Result, ResultPreb)
	  end)},
      {"test10",
       ?_test(
	  begin
	      Target = {test, test09, []},
	      Files = {files, [?TEST_ERL_PATH, ?TEST_AUX_ERL_PATH]},
	      Options = [Files],
	      OptionsPreb = [Files, {preb, infinite}],
	      Result = sched:analyze(Target, Options),
	      ResultPreb = sched:analyze(Target, OptionsPreb),
	      ?assertEqual(Result, ResultPreb)
	  end)},
      {"test11",
       ?_test(
	  begin
	      Target = {test, test09, []},
	      Files = {files, [?TEST_ERL_PATH]},
	      Options = [Files],
	      OptionsPreb = [Files, {preb, infinite}],
	      {error, analysis, Target, [Ticket1, Ticket2]} =
		  sched:analyze(Target, Options),
	      {error, analysis, Target, [TicketPreb1, TicketPreb2]} =
		  sched:analyze(Target, OptionsPreb),
	      States = {ticket:get_state(Ticket1),
			ticket:get_state(Ticket2)},
	      StatesPreb = {ticket:get_state(TicketPreb1),
			    ticket:get_state(TicketPreb2)},
	      ?assertEqual(States, StatesPreb)
	  end)},
      {"test12",
       ?_test(
	  begin
	      Target = {test, test10, []},
	      Files = {files, [?TEST_ERL_PATH]},
	      Options = [Files],
	      OptionsPreb = [Files, {preb, infinite}],
	      Result = sched:analyze(Target, Options),
	      ResultPreb = sched:analyze(Target, OptionsPreb),
	      ?assertEqual(Result, ResultPreb)
	  end)},
      {"test13",
       ?_test(
	  begin
	      Target = {test, test11, []},
	      Files = {files, [?TEST_ERL_PATH]},
	      Options = [Files],
	      OptionsPreb = [Files, {preb, infinite}],
	      Result = sched:analyze(Target, Options),
	      ResultPreb = sched:analyze(Target, OptionsPreb),
	      ?assertEqual(Result, ResultPreb)
	  end)},
      {"test14",
       ?_test(
	  begin
	      Target = {test, test12, []},
	      Files = {files, [?TEST_ERL_PATH]},
	      Options = [Files],
	      OptionsPreb = [Files, {preb, infinite}],
	      Result = sched:analyze(Target, Options),
	      ResultPreb = sched:analyze(Target, OptionsPreb),
	      ?assertEqual(Result, ResultPreb)
	  end)},
      {"test15",
       ?_test(
	  begin
	      Target = {test, test13, []},
	      Files = {files, [?TEST_ERL_PATH]},
	      Options = [Files],
	      OptionsPreb = [Files, {preb, infinite}],
	      Result = sched:analyze(Target, Options),
	      ResultPreb = sched:analyze(Target, OptionsPreb),
	      ?assertEqual(Result, ResultPreb)
	  end)},
      {"test16",
       ?_test(
	  begin
	      Target = {test, test14, []},
	      Files = {files, [?TEST_ERL_PATH]},
	      Options = [Files],
	      OptionsPreb = [Files, {preb, infinite}],
	      Result = sched:analyze(Target, Options),
	      ResultPreb = sched:analyze(Target, OptionsPreb),
	      ?assertEqual(Result, ResultPreb)
	  end)},
     {"test17",
       ?_test(
	  begin
	      Target = {test, test15, []},
	      Files = {files, [?TEST_ERL_PATH]},
	      Options = [Files],
	      OptionsPreb = [Files, {preb, infinite}],
	      Result = sched:analyze(Target, Options),
	      ResultPreb = sched:analyze(Target, OptionsPreb),
	      ?assertEqual(Result, ResultPreb)
	  end)},
     {"test18",
       ?_test(
	  begin
	      Target = {test, test16, []},
	      Files = {files, [?TEST_ERL_PATH]},
	      Options = [Files],
	      OptionsPreb = [Files, {preb, infinite}],
	      Result = sched:analyze(Target, Options),
	      ResultPreb = sched:analyze(Target, OptionsPreb),
	      ?assertEqual(Result, ResultPreb)
	  end)},
     {"test19",
       ?_test(
	  begin
	      Target = {test, test17, []},
	      Files = {files, [?TEST_ERL_PATH]},
	      Options = [Files],
	      OptionsPreb = [Files, {preb, infinite}],
	      Result = sched:analyze(Target, Options),
	      ResultPreb = sched:analyze(Target, OptionsPreb),
	      ?assertEqual(Result, ResultPreb)
	  end)},
     {"test20",
       ?_test(
	  begin
	      Target = {test, test18, []},
	      Files = {files, [?TEST_ERL_PATH]},
	      Options = [Files],
	      OptionsPreb = [Files, {preb, infinite}],
	      Result = sched:analyze(Target, Options),
	      ResultPreb = sched:analyze(Target, OptionsPreb),
	      ?assertEqual(Result, ResultPreb)
	  end)},
      {"test21",
       ?_test(
	  begin
	      Target = {test, test19, []},
	      Files = {files, [?TEST_ERL_PATH]},
	      Options = [Files],
	      OptionsPreb = [Files, {preb, infinite}],
	      Result = sched:analyze(Target, Options),
	      ResultPreb = sched:analyze(Target, OptionsPreb),
	      ?assertEqual(Result, ResultPreb)
	  end)}
     ]}.
