%%% @private
-module(concuerror_dependencies).

-export([dependent/3, dependent_safe/2, explain_error/1]).

%%------------------------------------------------------------------------------

-include("concuerror.hrl").

%%------------------------------------------------------------------------------

-type dep_ret() :: boolean() | 'irreversible' | {'true', message_id()}.

-spec dependent_safe(event(), event()) -> dep_ret().

dependent_safe(E1, E2) ->
  dependent(E1, E2, {true, ignore}).

-spec dependent(event(), event(), assume_racing_opt()) -> dep_ret().

dependent(#event{actor = A}, #event{actor = A}, _) ->
  irreversible;
dependent(#event{event_info = Info1, special = Special1},
          #event{event_info = Info2, special = Special2},
          AssumeRacing) ->
  try
    case dependent(Info1, Info2) of
      false ->
        M1 = [M || {message_delivered, M} <- Special1],
        M2 = [M || {message_delivered, M} <- Special2],
        first_non_false_dep([Info1|M1], M2, [Info2|M2]);
      Else -> Else
    end
  catch
    throw:irreversible -> irreversible;
    error:function_clause ->
      case AssumeRacing of
        {true, ignore} -> true;
        {true, Logger} ->
          Explanation = show_undefined_dependency(Info1, Info2),
          Msg =
            io_lib:format(
              "~s~n"
              " Concuerror treats such pairs as racing (--assume_racing)."
              " (No other such warnings will appear)~n", [Explanation]),
          ?unique(Logger, ?lwarning, Msg, []),
          true;
        {false, _} ->
          ?crash({undefined_dependency, Info1, Info2, []})
      end
  end.

first_non_false_dep([], _, _) -> false;
first_non_false_dep([_|R], [], I2) ->
  first_non_false_dep(R, I2, I2);
first_non_false_dep([I1H|_] = I1, [I2H|R], I2) ->
  case dependent(I1H, I2H) of
    false -> first_non_false_dep(I1, R, I2);
    Else -> Else
  end.

%% The first event happens before the second.

dependent(_, #builtin_event{mfargs = {erlang, halt, _}}) ->
  false;

dependent(#builtin_event{status = {crashed, _}},
          #builtin_event{status = {crashed, _}}) ->
  false;

dependent(#builtin_event{mfargs = MFArgs, extra = Extra},
          #exit_event{} = Exit) ->
  dependent_exit(Exit, MFArgs, Extra);
dependent(#exit_event{} = Exit, #builtin_event{} = Builtin) ->
  dependent(Builtin, Exit);

dependent(#builtin_event{mfargs = {erlang, process_info, _}} = PInfo, B) ->
  dependent_process_info(PInfo, B);
dependent(B, #builtin_event{mfargs = {erlang, process_info, _}} = PInfo) ->
  dependent_process_info(PInfo, B);

dependent(#builtin_event{} = BI1, #builtin_event{} = BI2) ->
  dependent_built_in(BI1, BI2);

dependent(#builtin_event{actor = Recipient, exiting = false,
                         trapping = Trapping} = Builtin,
          #message_event{message = #message{data = Signal},
                         recipient = Recipient, type = exit_signal}) ->
  #builtin_event{mfargs = MFArgs, result = Old} = Builtin,
  Signal =:= kill
    orelse
    case MFArgs of
      {erlang,process_flag,[trap_exit,New]} when New =/= Old -> true;
      _ ->
        {'EXIT', _, Reason} = Signal,
        not Trapping andalso Reason =/= normal
    end;
dependent(#builtin_event{actor = Recipient,
                         mfargs = {erlang, demonitor, [R|Rest]}
                        },
          #message_event{message = #message{data = {'DOWN', R, _, _, _}},
                         recipient = Recipient, type = message}) ->
  Options = case Rest of [] -> []; [O] -> O end,
  try
    [] = [O || O <- Options, O =/= flush, O =/= info],
    {lists:member(flush, Options), lists:member(info, Options)}
  of
    {true, false} -> false; %% Message will be discarded either way
    {true, true} -> true; %% Result is affected by the message being flushed
    {false, _} -> true %% Message is discarded upon delivery or not
  catch
    _:_ -> false
  end;
dependent(#builtin_event{}, #message_event{}) ->
  false;
dependent(#message_event{} = Message,
          #builtin_event{} = Builtin) ->
  dependent(Builtin, Message);

dependent(#exit_event{
             actor = Recipient,
             exit_by_signal = ExitBySignal,
             last_status = LastStatus,
             trapping = Trapping},
          #message_event{
             killing = Killing,
             message = #message{data = Signal},
             recipient = Recipient,
             type = exit_signal}) ->
  case Killing andalso ExitBySignal of
    true ->
      case LastStatus =:= running of
        false -> throw(irreversible);
        true -> true
      end;
    false ->
      case ExitBySignal of
        true -> false;
        false ->
          case Signal of
            kill -> true;
            {'EXIT', _, Reason} ->
              not Trapping andalso Reason =/= normal
          end
      end
  end;
dependent(#message_event{} = Message, #exit_event{} = Exit) ->
  dependent(Exit, Message);

dependent(#exit_event{}, #exit_event{}) ->
  false;

dependent(#message_event{
             killing = Killing1,
             message = #message{id = Id, data = EarlyData},
             receive_info = EarlyInfo,
             recipient = Recipient,
             trapping = Trapping,
             type = EarlyType},
          #message_event{
             killing = Killing2,
             message = #message{data = Data},
             receive_info = LateInfo,
             recipient = Recipient,
             type = Type
            }) ->
  KindFun =
    fun(exit_signal,    _, kill) -> exit_signal;
       (exit_signal, true,    _) -> message;
       (    message,    _,    _) -> message;
       (exit_signal,    _,    _) -> exit_signal
    end,
  case {KindFun(EarlyType, Trapping, EarlyData),
        KindFun(Type, Trapping, Data)} of
    {message, message} ->
      case EarlyInfo of
        undefined -> true;
        not_received -> false;
        {Counter1, Patterns} ->
          ObsDep =
            Patterns(Data) andalso
            case LateInfo of
              {Counter2, _} -> Counter2 >= Counter1;
              not_received -> true;
              undefined -> false
            end,
          case ObsDep of
            true -> {true, Id};
            false -> false
          end
      end;
    {_, _} -> Killing1 orelse Killing2 %% This is an ugly hack, see blame.
  end;

dependent(#message_event{
             message = #message{data = Data, id = MsgId},
             recipient = Recipient,
             type = Type
            },
          #receive_event{
             message = Recv,
             receive_info = {_, Patterns},
             recipient = Recipient,
             timeout = Timeout,
             trapping = Trapping
            }) ->
  EffType =
    case {Type, Trapping, Data} of
      {exit_signal,     _, kill} -> exit_signal;
      {exit_signal,  true,    _} -> message;
      {    message,     _,    _} -> message;
      _                          -> exit_signal
    end,
  case EffType =:= exit_signal of
    true ->
      case Data of
        kill -> true;
        {'EXIT', _, Reason} ->
          not Trapping andalso Reason =/= normal
      end;
    false ->
        case Recv of
          'after' ->
            %% Can only happen during wakeup (otherwise an actually
            %% delivered msg would be received)
            message_could_match(Patterns, Data, Trapping, Type);
          #message{id = RecId} ->
            %% Race exactly with the delivery of the received
            %% message
            MsgId =:= RecId andalso
              case Timeout =/= infinity of
                true -> true;
                false -> throw(irreversible)
              end
        end
  end;
dependent(#receive_event{
             message = 'after',
             receive_info = {RecCounter, Patterns},
             recipient = Recipient,
             trapping = Trapping},
          #message_event{
             message = #message{data = Data},
             receive_info = LateInfo,
             recipient = Recipient,
             type = Type
            }) ->
  case LateInfo of
    {Counter, _} ->
      %% The message might have been discarded before the receive.
      Counter >= RecCounter;
    _ -> true
  end
    andalso
    message_could_match(Patterns, Data, Trapping, Type);
dependent(#receive_event{
             recipient = Recipient,
             trapping = Trapping},
          #message_event{
             message = #message{data = Signal},
             recipient = Recipient,
             type = exit_signal
            }) ->
  case Signal of
    kill -> true;
    {'EXIT', _, Reason} ->
      not Trapping andalso Reason =/= normal
  end;

dependent(#message_event{}, _EventB) ->
  false;
dependent(_EventA, #message_event{}) ->
  false;

dependent(#receive_event{}, _EventB) ->
  false;
dependent(_EventA, #receive_event{}) ->
  false.

%%------------------------------------------------------------------------------

dependent_exit(#exit_event{actor = Exiting, name = Name},
               {erlang,UnRegisterOp,[RName|Rest]}, Extra)
  when UnRegisterOp =:= register;
       UnRegisterOp =:= unregister ->
  RName =:= Name orelse
    case UnRegisterOp of
      unregister ->
        Extra =:= Exiting;
      register ->
        [Pid] = Rest,
        Exiting =:= Pid
    end;
dependent_exit(Exit, MFArgs, _Extra) ->
  dependent_exit(Exit, MFArgs).

dependent_exit(_Exit, {erlang, A, _})
  when
    false
    ;A =:= date
    ;A =:= exit
    ;A =:= get_stacktrace
    ;A =:= make_ref
    ;A =:= monotonic_time
    ;A =:= now
    ;A =:= process_flag
    ;A =:= send_after
    ;A =:= spawn
    ;A =:= spawn_link
    ;A =:= spawn_opt
    ;A =:= start_timer
    ;A =:= system_time
    ;A =:= time
    ;A =:= time_offset
    ;A =:= timestamp
    ;A =:= unique_integer
    ->
  false;
dependent_exit(#exit_event{},
               {_, group_leader, []}) ->
  false;
dependent_exit(#exit_event{actor = Exiting},
               {_, group_leader, [Leader, Leaded]}) ->
  Exiting =:= Leader orelse Exiting =:= Leaded;
dependent_exit(#exit_event{actor = Actor}, {erlang, processes, []}) ->
  is_pid(Actor);
dependent_exit(#exit_event{actor = Cancelled},
               {erlang, ReadorCancelTimer, [Timer]})
  when ReadorCancelTimer =:= read_timer; ReadorCancelTimer =:= cancel_timer ->
  Cancelled =:= Timer;
dependent_exit(#exit_event{actor = Exiting},
               {erlang, is_process_alive, [Pid]}) ->
  Exiting =:= Pid;
dependent_exit(#exit_event{actor = Exiting},
               {erlang, process_info, [Pid|_]}) ->
  Exiting =:= Pid;
dependent_exit(#exit_event{actor = Exiting}, {erlang, UnLink, [Linked]})
  when UnLink =:= link; UnLink =:= unlink ->
  Exiting =:= Linked;
dependent_exit(#exit_event{monitors = Monitors},
               {erlang, demonitor, [Ref|Rest]}) ->
  Options = case Rest of [] -> []; [O] -> O end,
  try
    [] = [O || O <- Options, O =/= flush, O =/= info],
    {lists:member(flush, Options), lists:member(info, Options)}
  of
    {false, true} ->
      %% Result is whether monitor has been emitted
      false =/= lists:keyfind(Ref, 1, Monitors);
    {_, _} -> false
  catch
    _:_ -> false
  end;
dependent_exit(#exit_event{actor = Exiting, name = Name},
               {erlang, monitor, [process, PidOrName]}) ->
  Exiting =:= PidOrName orelse Name =:= PidOrName;
dependent_exit(#exit_event{name = Name}, {erlang, NameRelated, [OName|_]})
  when
    NameRelated =:= '!';
    NameRelated =:= send;
    NameRelated =:= whereis ->
  OName =:= Name;
dependent_exit(#exit_event{actor = Exiting}, {ets, give_away, [_, Pid, _]}) ->
  Exiting =:= Pid;
dependent_exit(_Exit, {ets, _, _}) ->
  false.

%%------------------------------------------------------------------------------

dependent_process_info(#builtin_event{mfargs = {M,F,[Pid, List]}} = ProcessInfo,
                       Other)
  when is_list(List) ->
  Pred =
    fun(Item) ->
        ItemInfo = ProcessInfo#builtin_event{mfargs = {M,F,[Pid,Item]}},
        dependent_process_info(ItemInfo, Other)
    end,
  lists:any(Pred, List);
dependent_process_info(#builtin_event{mfargs = {_,_,[Pid, group_leader]}},
                       Other) ->
  case Other of
    #builtin_event{mfargs = {_,group_leader,[_, Pid]}} -> true;
    _ -> false
  end;
dependent_process_info(#builtin_event{mfargs = {_,_,[Pid, links]}},
                       Other) ->
  case Other of
    #builtin_event{
       actor = Pid,
       mfargs = {erlang, UnLink, _}
      } when UnLink =:= link; UnLink =:= unlink -> true;
    #builtin_event{mfargs = {erlang, UnLink, [Pid]}}
      when UnLink =:= link; UnLink =:= unlink -> true;
    _ -> false
  end;
dependent_process_info(#builtin_event{mfargs = {_,_,[Pid, Msg]}},
                       Other)
  when Msg =:= messages; Msg =:= message_queue_len ->
  case Other of
    #message_event{recipient = Recipient} ->
      Recipient =:= Pid;
    #receive_event{recipient = Recipient, message = M} ->
      Recipient =:= Pid andalso M =/= 'after';
    _ -> false
  end;
dependent_process_info(#builtin_event{mfargs = {_, _, [Pid, registered_name]}},
                       Other) ->
  case Other of
    #builtin_event{extra = E, mfargs = {Module, Name, Args}} ->
      case Module =:= erlang of
        true when Name =:= register ->
          [_, RPid] = Args,
          Pid =:= RPid;
        true when Name =:= unregister ->
          E =:= Pid;
        _ -> false
      end;
    _ -> false
  end;
dependent_process_info(#builtin_event{mfargs = {_,_,[Pid, trap_exit]}},
                       Other) ->
  case Other of
    #builtin_event{
       actor = Pid,
       mfargs = {erlang, process_flag, [trap_exit, _]}} -> true;
    _ -> false
  end;
dependent_process_info(#builtin_event{mfargs = {_,_,[_, Safe]}},
                       _) when
    Safe =:= current_function;
    Safe =:= current_stacktrace;
    Safe =:= dictionary;
    Safe =:= heap_size;
    Safe =:= reductions;
    Safe =:= stack_size;
    Safe =:= status
    ->
  false.

%%------------------------------------------------------------------------------

dependent_built_in(#builtin_event{mfargs = {_,group_leader,ArgsA}} = A,
                   #builtin_event{mfargs = {_,group_leader,ArgsB}} = B) ->
  case {ArgsA, ArgsB} of
    {[], []} -> false;
    {[New, For], []} ->
      #builtin_event{actor = Actor, result = Result} = B,
      New =/= Result andalso Actor =:= For;
    {[], [_,_]} -> dependent_built_in(B, A);
    {[_, ForA], [_, ForB]} ->
      ForA =:= ForB
  end;

dependent_built_in(#builtin_event{actor = A, mfargs = {erlang, Spawn, _}},
                   #builtin_event{mfargs = {_, group_leader, [_, Leaded]}})
  when
    Spawn =:= spawn;
    Spawn =:= spawn_link;
    Spawn =:= spawn_opt ->
  Leaded =:= A;
dependent_built_in(#builtin_event{mfargs = {_, group_leader, [_, Leaded]}},
                   #builtin_event{actor = A, mfargs = {erlang, Spawn, _}})
  when
    Spawn =:= spawn;
    Spawn =:= spawn_link;
    Spawn =:= spawn_opt ->
  Leaded =:= A;

dependent_built_in(#builtin_event{mfargs = {_, group_leader, _}},
                   #builtin_event{}) ->
  false;
dependent_built_in(#builtin_event{},
                   #builtin_event{mfargs = {_, group_leader, _}}) ->
  false;

dependent_built_in(#builtin_event{mfargs = {erlang, processes, []}},
                   #builtin_event{mfargs = {erlang, Spawn, _}})
  when
    Spawn =:= spawn;
    Spawn =:= spawn_link;
    Spawn =:= spawn_opt ->
  true;
dependent_built_in(#builtin_event{mfargs = {erlang, Spawn, _}},
                   #builtin_event{mfargs = {erlang, processes, []}})
  when
    Spawn =:= spawn;
    Spawn =:= spawn_link;
    Spawn =:= spawn_opt ->
  true;

dependent_built_in(#builtin_event{mfargs = {erlang, A, _}},
                   #builtin_event{mfargs = {erlang, B, _}})
  when (A =:= '!' orelse A =:= send orelse A =:= whereis orelse
        A =:= process_flag orelse A =:= link orelse A =:= unlink),
       (B =:= '!' orelse B =:= send orelse B =:= whereis orelse
        B =:= process_flag orelse B =:= link orelse B =:= unlink) ->
  false;

dependent_built_in(#builtin_event{mfargs = {erlang,UnRegisterA,[AName|ARest]}},
                   #builtin_event{mfargs = {erlang,UnRegisterB,[BName|BRest]}})
  when (UnRegisterA =:= register orelse UnRegisterA =:= unregister),
       (UnRegisterB =:= register orelse UnRegisterB =:= unregister) ->
  AName =:= BName
    orelse
      (ARest =/= [] andalso ARest =:= BRest);

dependent_built_in(#builtin_event{mfargs = {erlang,SendOrWhereis,[SName|_]}},
                   #builtin_event{mfargs = {erlang,UnRegisterOp,[RName|_]}})
  when (UnRegisterOp =:= register orelse UnRegisterOp =:= unregister),
       (SendOrWhereis =:= '!' orelse SendOrWhereis =:= send orelse
        SendOrWhereis =:= whereis) ->
  SName =:= RName;
dependent_built_in(#builtin_event{mfargs = {erlang,UnRegisterOp,_}} = R,
                   #builtin_event{mfargs = {erlang,SendOrWhereis,_}} = S)
  when (UnRegisterOp =:= register orelse UnRegisterOp =:= unregister),
       (SendOrWhereis =:= '!' orelse SendOrWhereis =:= send orelse
        SendOrWhereis =:= whereis) ->
  dependent_built_in(S, R);

dependent_built_in(#builtin_event{mfargs = {erlang,monitor,[process,SName]}},
                   #builtin_event{mfargs = {erlang,UnRegisterOp,[RName|_]}})
  when (UnRegisterOp =:= register orelse UnRegisterOp =:= unregister) ->
  SName =:= RName;
dependent_built_in(#builtin_event{mfargs = {erlang,UnRegisterOp,_}} = R,
                   #builtin_event{mfargs = {erlang,monitor,_}} = S)
  when (UnRegisterOp =:= register orelse UnRegisterOp =:= unregister) ->
  dependent_built_in(S, R);

dependent_built_in(#builtin_event{mfargs = {erlang,RegistryOp,_}},
                   #builtin_event{mfargs = {erlang,LinkOp,_}})
  when (RegistryOp =:= register orelse
        RegistryOp =:= unregister orelse
        RegistryOp =:= whereis),
       (LinkOp =:= link orelse
        LinkOp =:= unlink) ->
  false;
dependent_built_in(#builtin_event{mfargs = {erlang,LinkOp,_}} = L,
                   #builtin_event{mfargs = {erlang,RegistryOp,_}} = R)
  when (RegistryOp =:= register orelse
        RegistryOp =:= unregister orelse
        RegistryOp =:= whereis),
       (LinkOp =:= link orelse
        LinkOp =:= unlink) ->
  dependent_built_in(R, L);

dependent_built_in(#builtin_event{mfargs = {erlang,ReadorCancelTimerA,[TimerA]}},
                   #builtin_event{mfargs = {erlang,ReadorCancelTimerB,[TimerB]}})
  when (ReadorCancelTimerA =:= read_timer orelse
        ReadorCancelTimerA =:= cancel_timer),
       (ReadorCancelTimerB =:= read_timer orelse
        ReadorCancelTimerB =:= cancel_timer),
       (ReadorCancelTimerA =:= cancel_timer orelse
        ReadorCancelTimerB =:= cancel_timer)
       ->
  TimerA =:= TimerB;

dependent_built_in(#builtin_event{mfargs = {erlang,send,_}, extra = Extra},
                   #builtin_event{mfargs = {erlang,ReadorCancelTimer,[Timer]}})
  when is_reference(Extra),
       (ReadorCancelTimer =:= read_timer orelse
        ReadorCancelTimer =:= cancel_timer) ->
  Extra =:= Timer;
dependent_built_in(#builtin_event{mfargs = {erlang,ReadorCancelTimer,_}} = Timer,
                   #builtin_event{mfargs = {erlang,send,_}} = Deliver)
  when ReadorCancelTimer =:= read_timer;
       ReadorCancelTimer =:= cancel_timer ->
  dependent_built_in(Deliver, Timer);

dependent_built_in(#builtin_event{mfargs = {erlang,ReadorCancelTimer,_}},
                   #builtin_event{})
  when ReadorCancelTimer =:= read_timer;
       ReadorCancelTimer =:= cancel_timer ->
  false;
dependent_built_in(#builtin_event{},
                   #builtin_event{mfargs = {erlang,ReadorCancelTimer,_}})
  when ReadorCancelTimer =:= read_timer;
       ReadorCancelTimer =:= cancel_timer ->
  false;

dependent_built_in(#builtin_event{mfargs = {erlang, monotonic_time, _}},
                   #builtin_event{mfargs = {erlang, monotonic_time, _}}) ->
  true;

dependent_built_in(#builtin_event{mfargs = {erlang, A, _}},
                   #builtin_event{mfargs = {erlang, B, _}})
  when
    false
    ;A =:= date
    ;A =:= demonitor        %% Depends only with an exit event or proc_info
    ;A =:= exit             %% Sending an exit signal (dependencies are on delivery)
    ;A =:= get_stacktrace   %% Depends with nothing
    ;A =:= is_process_alive %% Depends only with an exit event
    ;A =:= make_ref         %% Depends with nothing
    ;A =:= monitor          %% Depends only with an exit event or proc_info
    ;A =:= monotonic_time
    ;A =:= now
    ;A =:= process_flag     %% Depends only with delivery of a signal
    ;A =:= processes        %% Depends only with spawn and exit
    ;A =:= send_after
    ;A =:= spawn            %% Depends only with processes/0
    ;A =:= spawn_link       %% Depends only with processes/0
    ;A =:= spawn_opt        %% Depends only with processes/0
    ;A =:= start_timer
    ;A =:= system_time
    ;A =:= time
    ;A =:= time_offset
    ;A =:= timestamp
    ;A =:= unique_integer

    ;B =:= date
    ;B =:= demonitor
    ;B =:= exit
    ;B =:= get_stacktrace
    ;B =:= is_process_alive
    ;B =:= make_ref
    ;B =:= monitor
    ;B =:= monotonic_time
    ;B =:= now
    ;B =:= process_flag
    ;B =:= processes
    ;B =:= send_after
    ;B =:= spawn
    ;B =:= spawn_link
    ;B =:= spawn_opt
    ;B =:= start_timer
    ;B =:= system_time
    ;B =:= time
    ;B =:= time_offset
    ;B =:= timestamp
    ;B =:= unique_integer
    ->
  false;

%%------------------------------------------------------------------------------

dependent_built_in(#builtin_event{mfargs = {ets, rename, [TableA, NameA]}
                                 , extra = IdA},
                   #builtin_event{mfargs = {ets, AnyB, [TableB|ArgB]}
                                 , extra = IdB}) ->
  ets_same_table(TableA, IdA, TableB, IdB) orelse
    ets_same_table(NameA, IdA, TableB, IdB) orelse
    TableA =:= TableB orelse
    (AnyB =:= rename andalso ArgB =:= [NameA]);
dependent_built_in(#builtin_event{mfargs = {ets, _Any, _}} = EventA,
                   #builtin_event{mfargs = {ets, rename, _}} = EventB) ->
  dependent_built_in(EventB, EventA);

dependent_built_in(#builtin_event{mfargs = {ets, delete, [TableA]}
                                 , extra = IdA},
                   #builtin_event{mfargs = {ets, _Any, [TableB|_]}
                                 , extra = IdB}) ->
  ets_same_table(TableA, IdA, TableB, IdB);
dependent_built_in(#builtin_event{mfargs = {ets, _Any, _}} = EventA,
                   #builtin_event{mfargs = {ets, delete, _}} = EventB) ->
  dependent_built_in(EventB, EventA);

dependent_built_in(#builtin_event{mfargs = {ets, new, [TableA|_]}
                                 , extra = IdA},
                   #builtin_event{mfargs = {ets, _Any, [TableB|_]}
                                 , extra = IdB}) ->
  ets_same_table(TableA, IdA, TableB, IdB);
dependent_built_in(#builtin_event{mfargs = {ets, _Any, _}} = EventA,
                   #builtin_event{mfargs = {ets, new, _}} = EventB) ->
  dependent_built_in(EventB, EventA);

dependent_built_in(#builtin_event{ mfargs = {ets, _, [TableA|_]}
                                 , extra = IdA} = EventA,
                   #builtin_event{ mfargs = {ets, _, [TableB|_]}
                                 , extra = IdB} = EventB) ->
  ets_same_table(TableA, IdA, TableB, IdB)
    andalso
    case ets_is_mutating(EventA) of
      false ->
        case ets_is_mutating(EventB) of
          false -> false;
          Pred -> Pred(EventA)
        end;
      Pred -> Pred(EventB)
    end;

dependent_built_in(#builtin_event{mfargs = {erlang, _, _}},
                   #builtin_event{mfargs = {ets, _, _}}) ->
  false;
dependent_built_in(#builtin_event{mfargs = {ets, _, _}} = Ets,
                   #builtin_event{mfargs = {erlang, _, _}} = Erlang) ->
  dependent_built_in(Erlang, Ets).

%%------------------------------------------------------------------------------

message_could_match(Patterns, Data, Trapping, Type) ->
  Patterns(Data)
    andalso
      ((Trapping andalso Data =/= kill) orelse (Type =:= message)).

%%------------------------------------------------------------------------------

ets_same_table(TableA, IdA, TableB, IdB) ->
  ets_same_table(IdA, TableB) orelse ets_same_table(IdB, TableA).

ets_same_table(undefined, _Arg) ->
  false;
ets_same_table({Tid, Name}, Arg) ->
  case is_atom(Arg) of
    true -> Name =:= Arg;
    false -> Tid =:= Arg
  end.

-define(deps_with_any,fun(_) -> true end).

ets_is_mutating(#builtin_event{ status = {crashed, _}}) ->
  false;
ets_is_mutating(#builtin_event{ mfargs = {_, Op, [_|Rest] = Args}
                              , extra = {Tid, _}} = Event) ->
  case {Op, length(Args)} of
    {delete, 2} -> with_key(hd(Rest));
    {delete_object, 2} -> from_insert(Tid, hd(Rest), true);
    {DelAll, N}
      when
        {DelAll, N} =:= {delete_all_objects, 1};
        {DelAll, N} =:= {internal_delete_all, 2} ->
      ?deps_with_any;
    {first, _} -> false;
    {give_away, _} -> ?deps_with_any;
    {info, _} -> false;
    {insert, _} -> from_insert(Tid, hd(Rest), false);
    {insert_new, _} when Event#builtin_event.result ->
      from_insert(Tid, hd(Rest), true);
    {insert_new, _} -> false;
    {lookup, _} -> false;
    {lookup_element, _} -> false;
    {match, _} -> false;
    {match_object, _} -> false;
    {member, _} -> false;
    {next, _} -> false;
    {select, _} -> false;
    {SelDelete, 2}
      when
        SelDelete =:= select_delete;
        SelDelete =:= internal_select_delete ->
      from_delete(hd(Rest));
    {update_counter, 3} -> with_key(hd(Rest));
    {update_element, 3} -> with_key(hd(Rest));
    {whereis, 1} -> false
  end.

with_key(Key) ->
  fun(Event) ->
      Keys = ets_reads_keys(Event),
      case Keys =:= any of
        true -> true;
        false -> lists:any(fun(K) -> K =:= Key end, Keys)
      end
  end.

ets_reads_keys(Event) ->
  case keys_or_tuples(Event) of
    any -> any;
    none -> [];
    {matchspec, _MS} -> any; % can't test the matchspec against a single key
    {keys, Keys} -> Keys;
    {tuples, Tuples} ->
      #builtin_event{extra = {Tid, _}} = Event,
      KeyPos = ets:info(Tid, keypos),
      [element(KeyPos, Tuple) || Tuple <- Tuples]
  end.

keys_or_tuples(#builtin_event{mfargs = {_, Op, [_|Rest] = Args}}) ->
  case {Op, length(Args)} of
    {delete, 2} -> {keys, [hd(Rest)]};
    {DelAll, N}
      when
        {DelAll, N} =:= {delete_all_objects, 1};
        {DelAll, N} =:= {internal_delete_all, 2} ->
      any;
    {delete_object, 2} -> {tuples, [hd(Rest)]};
    {first, _} -> any;
    {give_away, _} -> any;
    {info, _} -> any;
    {Insert, _}
      when
        Insert =:= insert;
        Insert =:= insert_new ->
      Inserted = hd(Rest),
      {tuples,
       case is_list(Inserted) of
         true -> Inserted;
         false -> [Inserted]
       end};
    {lookup, _} -> {keys, [hd(Rest)]};
    {lookup_element, _} -> {keys, [hd(Rest)]};
    {match, _} -> {matchspec, [{hd(Rest), [], ['$$']}]};
    {match_object, _} -> {matchspec, [{hd(Rest), [], ['$_']}]};
    {member, _} -> {keys, [hd(Rest)]};
    {next, _} -> any;
    {select, _} -> {matchspec, hd(Rest)};
    {SelDelete, 2}
      when
        SelDelete =:= select_delete;
        SelDelete =:= internal_select_delete ->
      {matchspec, hd(Rest)};
    {update_counter, 3} -> {keys, [hd(Rest)]};
    {update_element, 3} -> {keys, [hd(Rest)]};
    {whereis, 1} -> none
  end.

from_insert(undefined, _, _) ->
  %% If table is undefined the op crashed so not mutating
  false;
from_insert(Table, Insert, InsertNewOrDelete) ->
  KeyPos = ets:info(Table, keypos),
  InsertList = case is_list(Insert) of true -> Insert; false -> [Insert] end,
  fun(Event) ->
      case keys_or_tuples(Event) of
        any -> true;
        none -> false;
        {keys, Keys} ->
          InsertKeys =
            ordsets:from_list([element(KeyPos, T) || T <- InsertList]),
          lists:any(fun(K) -> ordsets:is_element(K, InsertKeys) end, Keys);
        {tuples, Tuples} ->
          Pred =
            fun(Tuple) ->
                case lists:keyfind(element(KeyPos, Tuple), KeyPos, InsertList) of
                  false -> false;
                  InsertTuple -> InsertNewOrDelete orelse Tuple =/= InsertTuple
                end
            end,
          lists:any(Pred, Tuples);
        {matchspec, MS} ->
          Pred =
            fun (Tuple) ->
                case erlang:match_spec_test(Tuple, MS, table) of
                  {error, _} -> false;
                  {ok, Result, [], _Warnings} -> Result =/= false
                end
            end,
          lists:any(Pred, InsertList)
      end
  end.

from_delete(MatchSpec) ->
  fun (Event) ->
      case keys_or_tuples(Event) of
        any -> true;
        none -> false;
        {keys, _Keys} -> true;
        {matchspec, _MS} -> true;
        {tuples, Tuples} ->
          Pred =
            fun (Tuple) ->
                case erlang:match_spec_test(Tuple, MatchSpec, table) of
                  {error, _} -> false;
                  {ok, Result, [], _Warnings} -> Result =:= true
                end
            end,
          lists:any(Pred, Tuples)
      end
  end.


%%------------------------------------------------------------------------------

-spec explain_error(term()) -> string().

explain_error({undefined_dependency, A, B, C}) ->
  Message = show_undefined_dependency(A, B),
  io_lib:format(
    "~s~n"
    " You can run without '--assume_racing false' to treat them as racing.~n"
    " ~p~n",
    [Message, C]).

show_undefined_dependency(A, B) ->
  io_lib:format(
    "The following pair of instructions is not explicitly marked as non-racing"
    " in Concuerror's internals:~n"
    "  1) ~s~n  2) ~s~n"
    " Please notify the developers to add info about this pair.",
    [concuerror_io_lib:pretty_s(#event{event_info = I}, 10) || I <- [A,B]]).
