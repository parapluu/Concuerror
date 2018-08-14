%%% @private
-module(concuerror_io_lib).

-export([error_s/2, pretty/3, pretty_s/2]).

-include("concuerror.hrl").

-spec error_s(concuerror_scheduler:interleaving_error(), pos_integer()) ->
                 string().

error_s(fatal, _Depth) ->
  io_lib:format("* Concuerror crashed~n", []);
error_s({Type, Info}, Depth) ->
  case Type of
    abnormal_halt ->
      {Step, P, Status} = Info,
      S1 =
        io_lib:format(
          "* At step ~w process ~p called halt with an abnormal status~n",
          [Step, P]),
      S2 =
        io_lib:format(
          "    Status:~n"
          "      ~P~n", [Status, Depth]),
      [S1, S2];
    abnormal_exit ->
      {Step, P, Reason, Stacktrace} = Info,
      S1 =
        io_lib:format(
          "* At step ~w process ~p exited abnormally~n", [Step, P]),
      S2 =
        io_lib:format(
          "    Reason:~n"
          "      ~P~n", [Reason, Depth]),
      S3 =
        io_lib:format(
          "    Stacktrace:~n"
          "      ~p~n", [Stacktrace]),
      [S1, S2, S3];
    deadlock ->
      InfoStr =
        [io_lib:format(
           "    ~p ~s~n"
           "     Mailbox contents: ~p~n", [P, location(F, L), Msgs]) ||
          {P, [L, {file, F}], Msgs} <- Info],
      Format =
        "* Blocked at a 'receive' (\"deadlocked\";"
        " other processes have exited):~n~s",
      io_lib:format(Format, [InfoStr]);
    depth_bound ->
      io_lib:format("* Reached the depth bound of ~p events~n", [Info])
  end.

-spec pretty('disable' | io:device(), event(), pos_integer()) -> ok.

pretty(disable, _, _) ->
  ok;
pretty(Output, I, Depth) ->
  Fun =
    fun(P, A) ->
        Msg = io_lib:format(P ++ "~n", A),
        io:format(Output, "~s", [Msg])
    end,
  _ = pretty_aux(I, {Fun, []}, Depth),
  ok.

-type indexed_event() :: {index(), event()}.

-spec pretty_s(event() | indexed_event() | [indexed_event()], pos_integer()) ->
                  [string()].

pretty_s(Events, Depth) ->
  {_, Acc} = pretty_aux(Events, {fun io_lib:format/2, []}, Depth),
  lists:reverse(Acc).

pretty_aux({I, #event{} = Event}, {F, Acc}, Depth) ->
  #event{
     actor = Actor,
     event_info = EventInfo,
     location = Location
    } = Event,
  TraceString =
    case I =/= 0 of
      true -> io_lib:format("~4w: ", [I]);
      false -> ""
    end,
  ActorString =
    case Actor of
      P when is_pid(P) -> io_lib:format("~p: ", [P]);
      _ -> ""
    end,
  EventString = pretty_info(EventInfo, Depth),
  LocationString =
    case Location of
      [Line, {file, File}] -> io_lib:format("~n    ~s", [location(File, Line)]);
      exit ->
        case EventInfo of
          #exit_event{} -> "";
          _Other -> io_lib:format("~n    (while exiting)", [])
        end;
      _ -> ""
    end,
  R = F("~s~s~s~s", [TraceString, ActorString, EventString, LocationString]),
  {F, [R|Acc]};
pretty_aux(#event{} = Event, FAcc, Depth) ->
  pretty_aux({0, Event}, FAcc, Depth);
pretty_aux(List, FAcc, Depth) when is_list(List) ->
  Fun = fun(Event, Acc) -> pretty_aux(Event, Acc, Depth) end,
  lists:foldl(Fun, FAcc, List).

pretty_info(#builtin_event{mfargs = {erlang, send, [To, Msg]},
                           extra = Ref}, Depth) when is_reference(Ref) ->
  io_lib:format("expires, delivering ~W to ~W", [Msg, Depth, To, Depth]);
pretty_info(#builtin_event{mfargs = {erlang, '!', [To, Msg]},
                           status = {crashed, Reason}}, Depth) ->
  io_lib:format("Exception ~W is raised by: ~W ! ~W",
                [Reason, Depth, To, Depth, Msg, Depth]);
pretty_info(#builtin_event{mfargs = {M, F, Args},
                           status = {crashed, Reason}}, Depth) ->
  ArgString = pretty_arg(Args, Depth),
  io_lib:format("Exception ~W is raised by: ~p:~p(~s)",
                [Reason, Depth, M, F, ArgString]);
pretty_info(#builtin_event{mfargs = {erlang, '!', [To, Msg]},
                           result = Result}, Depth) ->
  io_lib:format("~W = ~w ! ~W", [Result, Depth, To, Msg, Depth]);
pretty_info(#builtin_event{mfargs = {M, F, Args}, result = Result}, Depth) ->
  ArgString = pretty_arg(Args, Depth),
  io_lib:format("~W = ~p:~p(~s)", [Result, Depth, M, F, ArgString]);
pretty_info(#exit_event{actor = Timer}, _Depth) when is_reference(Timer) ->
  "is removed";
pretty_info(#exit_event{reason = Reason}, Depth) ->
  ReasonStr =
    case Reason =:= normal of
      true -> "normally";
      false -> io_lib:format("abnormally (~W)", [Reason, Depth])
    end,
  io_lib:format("exits ~s", [ReasonStr]);
pretty_info(#message_event{} = MessageEvent, Depth) ->
  #message_event{
     message = #message{data = Data},
     recipient = Recipient,
     sender = Sender,
     type = Type
    } = MessageEvent,
  MsgString =
    case Type of
      message -> io_lib:format("Message (~W)", [Data, Depth]);
      exit_signal ->
        Reason =
          case Data of
            {'EXIT', Sender, R} -> R;
            kill -> kill
          end,
        io_lib:format("Exit signal (~W)", [Reason, Depth])
    end,
  io_lib:format("~s from ~p reaches ~p", [MsgString, Sender, Recipient]);
pretty_info(#receive_event{message = Message, timeout = Timeout}, Depth) ->
  case Message of
    'after' ->
      io_lib:format("receive timeout expires after ~p ms", [Timeout]);
     #message{data = Data} ->
      io_lib:format("receives message (~W)", [Data, Depth])
  end.

pretty_arg(Args, Depth) ->
  pretty_arg(lists:reverse(Args), "", Depth).

pretty_arg([], Acc, _Depth) -> Acc;
pretty_arg([Arg|Args], "", Depth) ->
  pretty_arg(Args, io_lib:format("~W", [Arg, Depth]), Depth);
pretty_arg([Arg|Args], Acc, Depth) ->
  pretty_arg(Args, io_lib:format("~W, ", [Arg, Depth]) ++ Acc, Depth).

location(F, L) ->
  Basename = filename:basename(F),
  io_lib:format("in ~s line ~w", [Basename, L]).
