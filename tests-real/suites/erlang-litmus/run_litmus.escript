#!/usr/bin/env escript
%%! -noshell

%%% This script can be used to run Concuerror on specified tests.

options() ->
  "--assertions_only -v0 --ignore_error deadlock"
    " --instant_delivery false --assume_racing false".

%%%-----------------------------------------------------------------------------

%%% Names and expected exit values from running concuerror on litmus tests

expected_exit(exhaustive) -> 0;
expected_exit(possible_1) -> 1;
expected_exit(possible_2) -> 1;
expected_exit(possible_3) -> 1;
expected_exit(_) -> -1.

%%%-----------------------------------------------------------------------------

main([]) ->
  %% Implied argument: all tests below
  {ok, Cwd} = file:get_cwd(),
  main([Cwd]);
main(Tests) ->
  case os:getenv("CONCUERROR") of
    false -> os:putenv("CONCUERROR","concuerror");
    _ -> ok
  end,
  Server = initialize(),
  ok = inspect_files(Tests, Server),
  finish(Server).

%%%-----------------------------------------------------------------------------

-record(
   state,
   {
     done   = 0
   , failed = 0
   , files  = 0
   , finish = false
   , limit  = parallelism()
   , tests  = 0
   }).

initialize() ->
  After17 =
    case erlang:system_info(otp_release) of
      "R" ++ _ -> false; %% ... 16 or earlier
      [D,U|_] -> list_to_integer([D,U]) > 17
    end,
  case After17 of
    false ->
      to_stderr("Skipping because OTP version < 18", []),
      halt(0);
    true ->
      print_header(),
      spawn_link(fun() -> loop(#state{}) end)
  end.

loop(#state{done = All, finish = {true, Report}, tests = All} = State) ->
  #state{failed = Failed, files = Files, tests = Tests} = State,
  Report ! {finish, Files, Tests, Failed},
  ok;
loop(State) ->
  #state{
     done = Done,
     failed = Failed,
     files = Files,
     limit = Limit,
     tests = Tests
    } = State,
  receive
    {file, File, Names} when Limit > 0 ->
      Server = self(),
      _ = [spawn_link(fun() -> run_test(File, T, Server) end) || T <- Names],
      NewFiles = Files + 1,
      NewTests = Tests + length(Names),
      NewLimit = Limit - length(Names),
      loop(State#state{files = NewFiles, limit = NewLimit, tests = NewTests});
    {test, File, Test, Status} ->
      print_test(File, Test, Status),
      NewDone = Done + 1,
      NewLimit = Limit + 1,
      NewFailed =
        case Status =:= ok of
          true -> Failed;
          false -> Failed + 1
        end,
      loop(State#state{done = NewDone, failed = NewFailed, limit = NewLimit});
    {finish, Report} when Limit > 0 ->
      loop(State#state{finish = {true, Report}})
  end.

%%%-----------------------------------------------------------------------------

run_test(File, Test, Server) ->
  Basename = filename:basename(File, ".erl"),
  Out = io_lib:format("~s-~p.out",[Basename, Test]),
  Opts = options(),
  Command =
    io_lib:format("$CONCUERROR ~s -f ~s -t ~p -o ~s", [Opts, File, Test, Out]),
  Exit = run_and_get_exit_status(Command),
  Status =
    case Exit =:= expected_exit(Test) of
      true ->
        file:delete(Out),
        ok;
      false ->
        failed
    end,
  Server ! {test, File, Test, Status}.

run_and_get_exit_status(Command) ->
  Port = open_port({spawn, Command}, [exit_status]),
  get_exit(Port, infinity).

get_exit(Port, Timeout) ->
  receive
    {Port, {exit_status, ExitStatus}} ->
      get_exit(Port, 0),
      ExitStatus;
    {Port, _} ->
      get_exit(Port, Timeout);
    {'EXIT', Port, _} ->
      get_exit(Port, Timeout)
  after
    Timeout -> ok
  end.

%%%-----------------------------------------------------------------------------

inspect_files([], _Server) ->
  ok;
inspect_files([File|Rest], Server) ->
  case filelib:is_dir(File) of
    true ->
      {ok, Files} = file:list_dir(File),
      inspect_files([filename:join([File, F]) || F <- Files] ++ Rest, Server);
    false ->
      extract_tests(File, Server),
      inspect_files(Rest, Server)
  end.

extract_tests(File, Server) ->
  case filename:extension(File) =:= ".erl" of
    false -> ok;
    true ->
      case compile:file(File, [binary]) of
        error ->
          print_test(File, 'compile', error),
          compile:file(File, [binary, report_errors]),
          halt(1);
        {ok, Module, Binary} ->
          {module, Module} = code:load_binary(Module, File, Binary),
          Exports = Module:module_info(exports),
          Tests = [Name || {Name, 0} <- Exports, is_test(Name)],
          case Tests =:= [] of
            true -> ok;
            false ->
              Server ! {file, File, Tests},
              ok
          end
      end
  end.

is_test(Name) -> expected_exit(Name) >= 0.

%%%-----------------------------------------------------------------------------

finish(Server) ->
  Server ! {finish, self()},
  receive
    {finish, Files, Tests, Failed} ->
      print_footer(Files, Tests, Failed),
      case Failed =:= 0 of
        true -> halt(0);
        false -> halt(1)
      end
  end.

%%%-----------------------------------------------------------------------------

print_header() ->
  to_stderr("Concurrent jobs: ~w", [parallelism()]),
  to_stderr("~-61s~-12s~-7s",["File", "Test", "Result"]),
  print_line().

print_test(File, Test, Status) ->
  TBasename = trim(File, 61),
  TTest = trim(Test, 12),
  TStatus = trim(Status, 7),
  Bold = "\033[1m",
  Color =
    case Status of
      ok -> "\033[92m";
      _ -> "\033[91m"
    end,
  EndC = "\033[0m",
  to_stderr(
    "~-61s~-12s~s~s~-7s~s",
    [TBasename, TTest, Bold, Color, TStatus, EndC]
   ).

trim(Atom, Length) when is_atom(Atom) ->
  trim(atom_to_list(Atom), Length);
trim(String, Length) ->
  Flat = lists:flatten(String),
  case length(Flat) =< Length of
    true -> Flat;
    false ->
      Trim = lists:sublist(String, Length - 4),
      [Trim,"... "]
  end.

print_footer(Files, Tests, Failed) ->
  print_line(),
  to_stderr("  Suites: ~p", [Files]),
  to_stderr("   Tests: ~p", [Tests]),
  to_stderr("  Failed: ~p", [Failed]).

print_line() ->
  to_stderr("~80..-s", [""]).

%%%-----------------------------------------------------------------------------

to_stderr(Format, Data) ->
  io:format(standard_error, Format ++ "~n", Data).

parallelism() ->
  erlang:system_info(schedulers).
