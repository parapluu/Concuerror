%% -*- erlang-indent-level: 2 -*-

-module(concuerror_dependencies).

-export([dependent/3, dependent_safe/2, explain_error/1]).

%%------------------------------------------------------------------------------

-include("concuerror.hrl").

-define(is_lookup(V),
        (V =:= lookup orelse V =:= lookup_element orelse V =:= member)).
-define(is_insert(V),
        (V =:= insert orelse V =:= insert_new)).
-define(is_match(V),
        (V =:= select) orelse (V =:= match)).
-define(is_delete(V),
        (V =:= delete)).
-define(is_match_delete(V),
        (V =:= select_delete orelse V =:= match_delete)).

%%------------------------------------------------------------------------------

-spec dependent_safe(event(), event()) -> boolean() | irreversible.

dependent_safe(E1, E2) ->
  dependent(E1, E2, {true, ignore}).

-spec dependent(event(), event(), assume_racing_opt()) ->
                   boolean() | irreversible.

dependent(#event{actor = A}, #event{actor = A}, _) ->
  irreversible;
dependent(#event{event_info = Info1, special = Special1},
          #event{event_info = Info2, special = Special2},
          AssumeRacing) ->
  M1 = [M || {message_delivered, M} <- Special1],
  M2 = [M || {message_delivered, M} <- Special2],
  try
    lists:any(fun({A,B}) -> dependent(A,B) end,
              [{I1,I2}|| I1 <- [Info1|M1], I2 <- [Info2|M2]])
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
          exit({undefined_dependency, Info1, Info2, erlang:get_stacktrace()})
      end
  end.

%% The first event happens before the second.

dependent(#builtin_event{mfargs = {erlang, halt, _}}, _) ->
  true;
dependent(_, #builtin_event{mfargs = {erlang, halt, _}}) ->
  true;

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
                         mfargs = {erlang, demonitor, [R, Opts]}},
          #message_event{message = #message{data = {_, R, _, _, _}},
                         recipient = Recipient, type = message}) ->
  is_list(Opts)
    andalso
      ([] =:= [O || O <- Opts, O =/= info, O =/= flush])
    andalso
    case {lists:member(flush, Opts), lists:member(info, Opts)} of
      {true, false} -> throw(irreversible);
      {    _,    _} -> true
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
             ignored = false,
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
             ignored = false,
             killing = Killing1,
             message = #message{id = Id, data = EarlyData},
             recipient = Recipient,
             trapping = Trapping,
             type = EarlyType},
          #message_event{
             ignored = false,
             killing = Killing2,
             message = #message{data = Data},
             recipient = Recipient,
             type = Type
            }) ->
  KindFun =
    fun(exit_signal,    _,                kill) -> kill_exit;
       (exit_signal, true,                   _) -> message;
       (    message,    _,                   _) -> message;
       (exit_signal,    _, {'EXIT', _, normal}) -> normal_exit;
       (exit_signal,    _,                   _) -> abnormal_exit
    end,
  case {KindFun(EarlyType, Trapping, EarlyData),
        KindFun(Type, Trapping, Data)} of
    {message, message} -> 
      concuerror_receive_dependencies:dependent_delivery(Id, Data);
    {message, normal_exit} -> false;
    {message, _} -> true;
    {normal_exit, kill_exit} -> true;
    {normal_exit, _} -> Trapping;
    {_, normal_exit} -> Trapping;
    {_, _} -> Killing1 orelse Killing2 %% This is an ugly hack, see blame.
  end;

dependent(#message_event{
             ignored = false,
             message = #message{data = Data, id = MsgId},
             recipient = Recipient,
             type = Type
            },
          #receive_event{
             message = Recv,
             patterns = Patterns,
             recipient = Recipient,
             timeout = Timeout,
             trapping = Trapping
            }) ->
  case Type =:= exit_signal of
    true ->
      case Data of
        kill -> true;
        {'EXIT', _, Reason} ->
          not Trapping andalso Reason =/= normal
      end;
    false ->
      Timeout =/= infinity
        andalso
        case Recv of
          'after' ->
            %% Can only happen during wakeup (otherwise an actually
            %% delivered msg would be received)
            message_could_match(Patterns, Data, Trapping, Type);
          #message{id = RecId} ->
            %% Race exactly with the delivery of the received
            %% message
            MsgId =:= RecId
        end
  end;
dependent(#receive_event{
             message = 'after',
             patterns = Patterns,
             recipient = Recipient,
             trapping = Trapping},
          #message_event{
             ignored = false,
             message = #message{data = Data},
             recipient = Recipient,
             type = Type
            }) ->
  message_could_match(Patterns, Data, Trapping, Type);
dependent(#receive_event{
             recipient = Recipient,
             trapping = Trapping},
          #message_event{
             ignored = false,
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
    A =:= erase;
    A =:= exit;
    A =:= get_stacktrace;
    A =:= make_ref;
    A =:= process_flag;
    A =:= put;
    A =:= send_after;
    A =:= spawn;
    A =:= spawn_opt;
    A =:= spawn_link;
    A =:= start_timer;
    A =:= group_leader ->
  false;
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
dependent_exit(#exit_event{monitors = Monitors}, {erlang, demonitor, [Ref|_]}) ->
  false =/= lists:keyfind(Ref, 1, Monitors);
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
dependent_process_info(#builtin_event{mfargs = {_,_,[Pid, dictionary]}},
                       Other) ->
  case Other of
    #builtin_event{actor = EPid, mfargs = {Module, Name, _}} ->
      Pid =:= EPid
        andalso
        case Module =:= erlang of
          true when Name =:= put; Name =:= erase ->
            true;
          _ -> false
        end;
    _ -> false
  end;
dependent_process_info(#builtin_event{mfargs = {_,_,[Pid, messages]}},
                       Other) ->
  case Other of
    #message_event{ignored = false, recipient = Recipient} ->
      Recipient =:= Pid;
    #receive_event{recipient = Recipient, message = M} ->
      Recipient =:= Pid andalso M =/= 'after';
    _ -> false
  end;
dependent_process_info(#builtin_event{mfargs = {_,_,[Pid, group_leader]}},
                       Other) ->
  case Other of
    #builtin_event{mfargs = {erlang,group_leader,[Pid,_]}} -> true;
    _-> false
  end;
dependent_process_info(#builtin_event{mfargs = {_,_,[_, Safe]}},
                       _) when
    Safe =:= heap_size;
    Safe =:= reductions;
    Safe =:= stack_size
    ->
  false.

%%------------------------------------------------------------------------------

dependent_built_in(#builtin_event{mfargs = {erlang, make_ref, _}},
                   #builtin_event{mfargs = {erlang, make_ref, _}}) ->
  true;

dependent_built_in(#builtin_event{mfargs = {erlang,group_leader,ArgsA}} = A,
                   #builtin_event{mfargs = {erlang,group_leader,ArgsB}} = B) ->
  case {ArgsA, ArgsB} of
    {[], []} -> false;
    {[New, For], []} ->
      #builtin_event{actor = Actor, result = Result} = B,
      New =/= Result andalso Actor =:= For;
    {[], [_,_]} -> dependent_built_in(B, A);
    {[_, ForA], [_, ForB]} ->
      ForA =:= ForB
  end;

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
  when
    false
    ;A =:= date
    ;A =:= demonitor        %% Depends only with an exit event or proc_info
    ;A =:= erase            %% Depends only with proc_info
    ;A =:= exit             %% Sending an exit signal (dependencies are on delivery)
    ;A =:= get_stacktrace   %% Depends with nothing
    ;A =:= group_leader     %% Depends only with another group_leader get/set
    ;A =:= is_process_alive %% Depends only with an exit event
    ;A =:= make_ref         %% Depends with nothing
    ;A =:= monitor          %% Depends only with an exit event or proc_info
    ;A =:= now
    ;A =:= process_flag     %% Depends only with delivery of a signal
    ;A =:= processes        %% Depends only with spawn and exit
    ;A =:= put              %% Depends only with proc_info
    ;A =:= send_after
    ;A =:= spawn            %% Depends only with processes/0
    ;A =:= spawn_link       %% Depends only with processes/0
    ;A =:= spawn_opt        %% Depends only with processes/0
    ;A =:= start_timer
    ;A =:= time
    
    ;B =:= date
    ;B =:= demonitor
    ;B =:= erase
    ;B =:= exit
    ;B =:= get_stacktrace
    ;B =:= group_leader
    ;B =:= is_process_alive
    ;B =:= make_ref
    ;B =:= monitor
    ;B =:= now
    ;B =:= process_flag
    ;B =:= processes
    ;B =:= put
    ;B =:= send_after
    ;B =:= spawn
    ;B =:= spawn_link
    ;B =:= spawn_opt
    ;B =:= start_timer
    ;B =:= time
    ->
  false;

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

%%------------------------------------------------------------------------------

dependent_built_in(#builtin_event{mfargs = {ets,delete,[Table1]}},
                   #builtin_event{mfargs = {ets,_Any,[Table2|_]}}) ->
  Table1 =:= Table2;
dependent_built_in(#builtin_event{mfargs = {ets,_Any,_}} = EtsAny,
                   #builtin_event{mfargs = {ets,delete,[_]}} = EtsDelete) ->
  dependent_built_in(EtsDelete, EtsAny);

dependent_built_in(#builtin_event{mfargs = {ets,new,_}, result = Table1},
                   #builtin_event{mfargs = {ets,_Any,[Table2|_]}}) ->
  Table1 =:= Table2;
dependent_built_in(#builtin_event{mfargs = {ets,_Any,_}} = EtsAny,
                   #builtin_event{mfargs = {ets,new,_}} = EtsNew) ->
  dependent_built_in(EtsNew, EtsAny);

dependent_built_in(#builtin_event{mfargs = {ets,_,[Table|_]}} = EventA,
                   #builtin_event{mfargs = {ets,_,[Table|_]}} = EventB) ->
  case ets_is_mutating(EventA) of
    false ->
      case ets_is_mutating(EventB) of
        false -> false;
        Pred -> Pred(EventA)
      end;
    Pred -> Pred(EventB)
  end;

dependent_built_in(#builtin_event{mfargs = {ets,_,_}},
                   #builtin_event{mfargs = {ets,_,_}}) ->
  false;

dependent_built_in(#builtin_event{mfargs = {erlang,_,_}},
                   #builtin_event{mfargs = {ets,_,_}}) ->
  false;
dependent_built_in(#builtin_event{mfargs = {ets,_,_}} = Ets,
                   #builtin_event{mfargs = {erlang,_,_}} = Erlang) ->
  dependent_built_in(Erlang, Ets).

%%------------------------------------------------------------------------------

message_could_match(Patterns, Data, Trapping, Type) ->
  Patterns(Data)
    andalso
      ((Trapping andalso Data =/= kill) orelse (Type =:= message)).

%%------------------------------------------------------------------------------

-define(deps_with_any,fun(_) -> true end).

ets_is_mutating(#builtin_event{mfargs = {_,Op,[_|Rest] = Args}} = Event) ->
  case {Op, length(Args)} of
    {delete        ,2} -> with_key(hd(Rest));
    {delete_object ,2} ->
      from_insert(Event#builtin_event.extra, hd(Rest), true);
    {first         ,_} -> false;
    {give_away     ,_} -> ?deps_with_any;
    {info          ,_} -> false;
    {insert        ,_} ->
      from_insert(Event#builtin_event.extra, hd(Rest), false);
    {insert_new    ,_}
      when Event#builtin_event.result ->
      from_insert(Event#builtin_event.extra, hd(Rest), true);
    {insert_new    ,_} -> false;
    {lookup        ,_} -> false;
    {lookup_element,_} -> false;
    {match         ,_} -> false;
    {match_object  ,_} -> false;
    {member        ,_} -> false;
    {next          ,_} -> false;
    {select        ,_} -> false;
    {select_delete ,_} -> ?deps_with_any;
    {update_counter,3} -> with_key(hd(Rest))                   
  end.

with_key(Key) ->
  fun(Event) ->
      Keys = ets_reads_keys(Event),
      if Keys =:= any -> true;
         true -> lists:any(fun(K) -> K =:= Key end, Keys)
      end
  end.

ets_reads_keys(Event) ->
  case keys_or_tuples(Event) of
    any -> any;
    {keys, Keys} -> Keys;
    {tuples, Tuples} ->
      KeyPos = ets:info(Event#builtin_event.extra, keypos),
      [element(KeyPos, Tuple) || Tuple <- Tuples]
  end.      

keys_or_tuples(#builtin_event{mfargs = {_,Op,[_|Rest] = Args}}) ->
  case {Op, length(Args)} of
    {delete        ,2} -> {keys, [hd(Rest)]};
    {delete_object ,2} -> {tuples, [hd(Rest)]};
    {first         ,_} -> any;
    {give_away     ,_} -> any;
    {info          ,_} -> any;
    {Insert        ,_} when Insert =:= insert; Insert =:= insert_new ->
      Inserted = hd(Rest),
      {tuples,
       case is_list(Inserted) of true -> Inserted; false -> [Inserted] end};
    {lookup        ,_} -> {keys, [hd(Rest)]};
    {lookup_element,_} -> {keys, [hd(Rest)]};
    {match         ,_} -> any;
    {match_object  ,_} -> any;
    {member        ,_} -> {keys, [hd(Rest)]};
    {next          ,_} -> any;
    {select        ,_} -> any;
    {select_delete ,_} -> any;
    {update_counter,3} -> {keys, [hd(Rest)]}
  end.

from_insert(Table, Insert, InsertNewOrDelete) ->
  KeyPos = ets:info(Table, keypos),
  InsertList = case is_list(Insert) of true -> Insert; false -> [Insert] end,
  fun(Event) ->
      case keys_or_tuples(Event) of
        any -> true;
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
