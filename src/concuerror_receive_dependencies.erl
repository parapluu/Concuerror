%% -*- erlang-indent-level: 2 -*-

%%% @doc Conditional dependencies for sends, based on receives
%%%
%%% Ideas:
%%%
%%% - This feature will be turned on and off via an entry in the
%%%   process dictionary, for convenience.
%%%
%%% - We will store receive patterns in an ETS table owned by the
%%%   scheduler.
%%%
%%% - Since race detection happens on full traces, we will allow any
%%%   send to wakeup a sleeping send and accurately detect
%%%   dependencies for it in the end.
%%%
%%% - We need to take care to erase 'receive' info when backtracking.

-module(concuerror_receive_dependencies).

%%==============================================================================

-export([initialise/1, store/3, reset/1, dependent_delivery/3]).

%%==============================================================================

-include("concuerror.hrl").

%%==============================================================================

-spec initialise(boolean()) -> ok.

initialise(UseReceivePatterns) ->
  put(use_receive_patterns, UseReceivePatterns),
  case UseReceivePatterns of
    true ->
      use_receive_patterns = ets:new(use_receive_patterns, [named_table]),
      ok;
    false ->
      ok
  end.

%%==============================================================================

-spec store(message_id(), receive_pattern_fun(), pos_integer()) -> ok.

store(MessageId, PatternFun, Counter) ->
  case get(use_receive_patterns) of
    false -> ok;
    true ->
      ets:insert(use_receive_patterns, {MessageId, PatternFun, Counter}),
      ok
  end.

%%==============================================================================

-spec reset(message_id()) -> ok.

reset(MessageId) ->
  case get(use_receive_patterns) of
    false -> ok;
    true ->
      ets:delete(use_receive_patterns, MessageId),
      ok
  end.

%%==============================================================================

-spec dependent_delivery(message_id(), message_id(), term()) ->
                            boolean() | {'true', message_id()}.

dependent_delivery(MessageId, MessageId2, Data) ->
  case get(use_receive_patterns) of
    false -> true;
    true ->
      case ets:lookup(use_receive_patterns, MessageId) of
        [] -> false;
        [{MessageId, Pats, Counter}] ->
          case Pats(Data) of
            true ->
              case ets:lookup(use_receive_patterns, MessageId2) of
                [{MessageId2, _, Counter2}]
                  when Counter2 < Counter ->
                  false;
                _ -> {true, MessageId}
              end;
            false -> false
          end
      end
  end.
