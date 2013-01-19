%%%----------------------------------------------------------------------
%%% Copyright (c) 2011, Alkis Gotovos <el3ctrologos@hotmail.com>,
%%%                     Maria Christakis <mchrista@softlab.ntua.gr>
%%%                 and Kostis Sagonas <kostis@cs.ntua.gr>.
%%% All rights reserved.
%%%
%%% This file is distributed under the Simplified BSD License.
%%% Details can be found in the LICENSE file.
%%%----------------------------------------------------------------------
%%% Authors     : Alkis Gotovos <el3ctrologos@hotmail.com>
%%%               Maria Christakis <mchrista@softlab.ntua.gr>
%%% Description : Error interface
%%%----------------------------------------------------------------------

-module(concuerror_error).

-export([long/1, mock/0, new/1, short/1, type/1]).

-export_type([error/0]).

-include("gen.hrl").

-type error_type()  :: 'assertion_violation' | 'deadlock' | 'exception'.
-type error()       :: {error_type(), term()}.

-spec new(term()) -> error().

new({deadlock, _Set} = Deadlock) -> Deadlock;
new({{assertion_failed, Details}, _Any}) -> {assertion_violation, Details};
new({{assertEqual_failed, Details}, _Any}) -> {assertion_violation, Details};
new(Reason) -> {exception, Reason}.

-spec type(error()) -> nonempty_string().

type({deadlock, _Blocked}) -> "Deadlock";
type({assertion_violation, _Details}) -> "Assertion violation";
type({exception, _Details}) -> "Exception".

-spec short(error()) -> nonempty_string().

short({deadlock, Blocked}) ->
    OldList = lists:sort(?SETS:to_list(Blocked)),
    {List, [Last]} = lists:split(length(OldList) - 1, OldList),
    Fun = fun(L, A) -> A ++ concuerror_lid:to_string(L) ++ ", " end,
    lists:foldl(Fun, "", List) ++ concuerror_lid:to_string(Last);
short({assertion_violation, [{module, Module}, {line, Line}|_Rest]}) ->
    OldModule = concuerror_instr:old_module_name(Module),
    concuerror_util:flat_format("~p.erl:~p", [OldModule, Line]);
short({exception, Reason}) ->
    lists:flatten(io_lib:format("~W", [Reason, 3])).

-spec long(error()) -> nonempty_string().

long({deadlock, _Blocked} = Error) ->
    Format = "Error type        : Deadlock~n"
             "Blocked processes : ~s",
    concuerror_util:flat_format(Format, [short(Error)]);
long({assertion_violation,
      [{module, Module}, {line, Line}, _Xpr, {expected, Exp}, {value, Val}]}) ->
    Format = "Error type        : Assertion violation~n"
             "Module:Line       : ~p.erl:~p~n"
             "Expected          : ~p~n"
             "Value             : ~p",
    OldModule = concuerror_instr:old_module_name(Module),
    concuerror_util:flat_format(Format, [OldModule, Line, Exp, Val]);
long({exception, Details}) ->
    Format = "Error type        : Exception~n"
             "Details           : ~p",
    concuerror_util:flat_format(Format, [Details]).

-spec mock() -> {'exception', 'foobar'}.

mock() -> {exception, foobar}.
