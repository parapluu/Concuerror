%% -*- erlang-indent-level: 2 -*-

%% This module will never be instrumented. Function instrumented/3 should:
%%  - return the result of a call, if it is called from a non-Concuerror process
%%  - grab concuerror_info and continue to concuerror_callback

-module(concuerror_inspect).

%% Interface to instrumented code:
-export([instrumented/3]).

-include("concuerror.hrl").
-include("concuerror_callback.hrl").

%%------------------------------------------------------------------------------

-spec instrumented(Tag      :: instrumented_tags(),
                   Args     :: [term()],
                   Location :: term()) -> Return :: term().

instrumented(Tag, Args, Location) ->
  Ret =
    case get(concuerror_info) of
      #concuerror_info{escaped_pdict = Escaped} = Info ->
        case Escaped =:= nonexisting of
          true  -> erase(concuerror_info);
          false -> put(concuerror_info, Escaped)
        end,
        {Result, #concuerror_info{} = NewInfo} =
          concuerror_callback:instrumented(Tag, Args, Location, Info),
        NewEscaped =
          case get(concuerror_info) of
            %% XXX: Someone might go and store undefined in concuerror_info...
            undefined -> nonexisting;
            NewProcessInfo -> NewProcessInfo
          end,
        FinalInfo = NewInfo#concuerror_info{escaped_pdict = NewEscaped},
        put(concuerror_info, FinalInfo),
        Result;
    undefined ->
        doit
    end,
  case Ret of
    doit ->
      case {Tag, Args} of
        {apply, [Fun, ApplyArgs]} ->
          erlang:apply(Fun, ApplyArgs);
        {call, [Module, Name, CallArgs]} ->
          erlang:apply(Module, Name, CallArgs);
        {'receive', _} ->
          ok
      end;
    {didit, Res} -> Res;
    {error, Reason} -> error(Reason)
  end.
