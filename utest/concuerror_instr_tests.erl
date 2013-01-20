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
%%% Description : Instrumenter unit tests
%%%----------------------------------------------------------------------

-module(concuerror_instr_tests).

-include_lib("eunit/include/eunit.hrl").
-include("gen.hrl").

-define(TEST_PATH, "./resources/syntax/").

%% Spec for auto-generated test/0 function (eunit).
-spec test() -> 'ok' | {'error', term()}.


-spec syntax_test_() -> term().

syntax_test_() ->
    Setup =
        fun() ->
                _ = concuerror_log:start(),
                _ = concuerror_log:attach(concuerror_log, [])
        end,
    Cleanup =
        fun(_Any) ->
                concuerror_log:stop()
        end,
    Test01 = {"Block expression in after clause",
	      fun(_Any) -> test_ok("block_after.erl") end},
    Test02 = {"Assignments to non-local variables in patterns",
	      fun(_Any) -> test_ok("non_local_pat.erl") end},
    Test03 = {"Underscore in record creation",
	      fun(_Any) -> test_ok("rec_uscore.erl") end},
    Test04 = {"Strip types and specs",
	      fun(_Any) -> test_ok("strip_attr.erl") end},
    Tests = [Test01, Test02, Test03, Test04],
    Inst = fun(X) -> [{D, fun() -> T(X) end} || {D, T} <- Tests] end,
    {foreach, local, Setup, Cleanup, [Inst]}.

test_ok(File) ->
    %% Initialize test
    ?NT_CALLED_MOD = ets:new(?NT_CALLED_MOD,
        [named_table, public, set, {write_concurrency, true}]),
    ?NT_INSTR_MOD = ets:new(?NT_INSTR_MOD,
        [named_table, public, set, {read_concurrency, true}]),
    Path = filename:join([?TEST_PATH, File]),
    Result = concuerror_instr:instrument_and_compile([Path], []),
    %% Cleanup test
    concuerror_instr:delete_and_purge([]),
    ets:delete(?NT_CALLED_MOD),
    ets:delete(?NT_INSTR_MOD),
    %% Assert Result
    ?assertMatch({ok, _Bin}, Result).
