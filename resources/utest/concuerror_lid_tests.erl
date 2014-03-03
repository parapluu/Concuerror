%%%----------------------------------------------------------------------
%%% Copyright (c) 2011, Alkis Gotovos <el3ctrologos@hotmail.com>,
%%%                     Maria Christakis <mchrista@softlab.ntua.gr>
%%%                 and Kostis Sagonas <kostis@cs.ntua.gr>.
%%% All rights reserved.
%%%
%%% This file is distributed under the Simplified BSD License.
%%% Details can be found in the LICENSE file.
%%%----------------------------------------------------------------------
%%% Author      : Alkis Gotovos <el3ctrologos@hotmail.com>
%%% Description : LID interface unit tests
%%%----------------------------------------------------------------------

-module(concuerror_lid_tests).

-include_lib("eunit/include/eunit.hrl").

-include("gen.hrl").

%% Spec for auto-generated test/0 function (eunit).
-spec test() -> 'ok' | {'error', term()}.


-spec one_proc_test_() -> term().

one_proc_test_() ->
    Setup =
        fun() -> concuerror_lid:start(),
                 Pid = c:pid(0, 2, 3),
                 Lid = concuerror_lid:new(Pid, noparent),
                 {Pid, Lid}
        end,
    Cleanup = fun(_Any) -> concuerror_lid:stop() end,
    Test1 = {"LID to Pid",
        fun({Pid, Lid}) -> ?assertEqual(Pid,concuerror_lid:get_pid(Lid)) end},
    Test2 = {"Pid to LID",
        fun({Pid, Lid}) -> ?assertEqual(Lid,concuerror_lid:from_pid(Pid)) end},
    Test3 = {"Parent -> Child",
        fun({_Pid, Lid}) ->
                ChildPid = c:pid(0, 2, 4),
                ChildLid = concuerror_lid:new(ChildPid, Lid),
                ?assertEqual(ChildPid, concuerror_lid:get_pid(ChildLid)),
                ?assertEqual(ChildLid, concuerror_lid:from_pid(ChildPid))
        end},
    Tests = [Test1, Test2, Test3],
    Inst = fun(X) -> [{D, fun() -> T(X) end} || {D, T} <- Tests] end,
    {foreach, local, Setup, Cleanup, [Inst]}.

-spec two_proc_test_() -> term().

two_proc_test_() ->
    Setup =
        fun() -> concuerror_lid:start(),
                 Pid1 = spawn(fun() -> receive ok -> ok end end),
                 Pid2 = spawn(fun() -> receive ok -> ok end end),
                 Lid1 = concuerror_lid:new(Pid1, noparent),
                 Lid2 = concuerror_lid:new(Pid2, Lid1),
                 {Pid1, Pid2, Lid1, Lid2}
        end,
    Cleanup =
        fun({Pid1, Pid2, _Lid1, _Lid2}) ->
                Pid1 ! ok, Pid2 ! ok,
                concuerror_lid:stop()
        end,
    Test1 = {"Fold Pids",
        fun({Pid1, Pid2, _Lid1, _Lid2}) ->
                Fun = fun(P, A) -> [P|A] end,
                Result = concuerror_lid:fold_pids(Fun, []),
                ?assertEqual(lists:member(Pid1, Result), true),
                ?assertEqual(lists:member(Pid2, Result), true)
        end},
    Test2 = {"Cleanup",
        fun({Pid1, _Pid2, Lid1, _Lid2}) ->
                concuerror_lid:cleanup(Lid1),
                ?assertEqual(not_found, concuerror_lid:from_pid(Pid1)),
                ?assertEqual(not_found, concuerror_lid:get_pid(Lid1))
        end},
    Tests = [Test1, Test2],
    Inst = fun(X) -> [{D, fun() -> T(X) end} || {D, T} <- Tests] end,
    {foreach, local, Setup, Cleanup, [Inst]}.
