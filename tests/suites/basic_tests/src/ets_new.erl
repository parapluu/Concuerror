%%%----------------------------------------------------------------------
%%% Copyright (c) 2012, Alkis Gotovos <el3ctrologos@hotmail.com>,
%%%                     Maria Christakis <mchrista@softlab.ntua.gr>
%%%                 and Kostis Sagonas <kostis@cs.ntua.gr>.
%%% All rights reserved.
%%%
%%% This file is distributed under the Simplified BSD License.
%%% Details can be found in the LICENSE file.
%%%----------------------------------------------------------------------
%%% Authors     : Ilias Tsitsimpis <iliastsi@hotmail.com>
%%% Description : Test the `ets:new' instrumentation
%%%----------------------------------------------------------------------

-module(ets_new).
-export([scenarios/0]).
-export([test/0]).

scenarios() ->
    [{test, inf, dpor}].

test() ->
    spawn(fun child/0),
    ets:new(table, [named_table, public]),
    ets:delete(table).

%% There should be an exception if this happens
%% between `new' and `delete'
child() ->
    case ets:info(table) of
        undefined -> ok;
        _ -> 1 = 2
    end.
