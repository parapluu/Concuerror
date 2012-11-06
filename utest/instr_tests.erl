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

-module(instr_tests).

-include_lib("eunit/include/eunit.hrl").

-define(TEST_PATH, "./resources/syntax/").

%% Spec for auto-generated test/0 function (eunit).
-spec test() -> 'ok' | {'error', term()}.


-spec syntax_test_() -> term().

syntax_test_() ->
    Setup = fun() -> _ = log:start(), log:attach(log, []) end,
    Cleanup = fun(_Any) -> log:stop() end,
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
    Path = filename:join([?TEST_PATH, File]),
    Result = instr:instrument_and_compile([Path], [], [], false),
    ?assertMatch({ok, _Bin}, Result).
