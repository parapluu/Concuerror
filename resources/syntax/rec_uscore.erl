%%%----------------------------------------------------------------------
%%% File        : rec_uscore.erl
%%% Authors     : Alkis Gotovos <el3ctrologos@hotmail.com>
%%%               Maria Christakis <christakismaria@gmail.com>
%%% Description : Test underscore in record creation
%%% Created     : 3 Jan 2010
%%%----------------------------------------------------------------------

-module(rec_uscore).

-export([rec_uscore_test/0]).

-record(test, {foo :: integer(), bar :: atom(), baz :: atom()}).

rec_uscore_test() ->
    _Rec = #test{foo = 42, _ = '_'}.
