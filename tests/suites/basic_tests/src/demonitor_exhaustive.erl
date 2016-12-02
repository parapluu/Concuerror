-module(demonitor_exhaustive).

-compile(export_all).

-export([scenarios/0]).

-concuerror_options_forced([show_races]).

%%------------------------------------------------------------------------------

scenarios() ->
  [{T, inf, dpor} ||
    T <-
      [parent_none,
       parent_flush,
       parent_info,
       parent_both,
       child_none,
       child_flush,
       child_info,
       child_both
      ]
  ].

%%------------------------------------------------------------------------------

parent() ->
  spawn_monitor(fun() -> ok end).

child() ->
  P = self(),
  Res = spawn_monitor(fun() -> P ! go end),
  receive go -> ok end,
  Res.

%%------------------------------------------------------------------------------

-define(assert(BoolExpr, Explain),
	((fun() ->
              case (BoolExpr) of
		true -> ok;
		__V ->
                  erlang:error(
                    {assertion_failed,
                     [{module, ?MODULE},
                      {line, ?LINE},
                      {expression, (??BoolExpr)},
                      {expected, true},
                      {explain, Explain},
                      {value,
                       case __V of false -> __V;
                         _ -> {not_a_boolean,__V}
                       end}
                     ]
                    }
                   )
              end
	  end)())).

%%------------------------------------------------------------------------------

got_monitor(Ref, Pid) ->
  receive
    {'DOWN', Ref, process, Pid, _} -> true
  after
    0 -> false
  end.

before_demonitor_after(Ref, Pid, Options) ->
  Before = got_monitor(Ref, Pid),
  Demonitor = demonitor(Ref, Options),
  After = got_monitor(Ref, Pid),
  ?assert(
     not (Before andalso After),
     "Unbreakable: received both before or after."),
  ?assert(
     Before orelse After,
     "Breakable: if demonitor before child exits or monitor arrives too late."),
  {Before, Demonitor, After}.

%%------------------------------------------------------------------------------

with_none(Pid, Ref) ->
  {_Before, Demonitor, _After} = before_demonitor_after(Ref, Pid, []),
  ?assert(
     Demonitor,
     "Unbreakable: always returns true if no info.").


with_flush(Pid, Ref) ->
  {_Before, Demonitor, After} = before_demonitor_after(Ref, Pid, [flush]),
  ?assert(
     Demonitor,
     "Unbreakable: always returns true if no info."),
  ?assert(
     not After,
     "Unbreakable: message is always consumed by flush.").

with_info(Pid, Ref) ->
  {_Before, Demonitor, After} = before_demonitor_after(Ref, Pid, [info]),
  ?assert(
     not (Demonitor andalso After),
     "Unbreakable: if demonitored, it can't be received too.").

with_both(Pid, Ref) ->
  {Before, Demonitor, After} = before_demonitor_after(Ref, Pid, [flush, info]),
  ?assert(
     not After,
     "Unbreakable: message is always consumed by flush."),
  ?assert(
     not (Before andalso Demonitor),
     "Unbreakable: if received before, cannot be flushed").

%%------------------------------------------------------------------------------

parent_none() ->
  {Pid, Ref} = parent(),
  with_none(Pid, Ref).

parent_flush() ->
  {Pid, Ref} = parent(),
  with_flush(Pid, Ref).

parent_info() ->
  {Pid, Ref} = parent(),
  with_info(Pid, Ref).

parent_both() ->
  {Pid, Ref} = parent(),
  with_both(Pid, Ref).

child_none() ->
  {Pid, Ref} = child(),
  with_none(Pid, Ref).

child_flush() ->
  {Pid, Ref} = child(),
  with_flush(Pid, Ref).

child_info() ->
  {Pid, Ref} = child(),
  with_info(Pid, Ref).

child_both() ->
  {Pid, Ref} = child(),
  with_both(Pid, Ref).
