%%%----------------------------------------------------------------------
%%% File        : strip_attr.erl
%%% Authors     : Alkis Gotovos <el3ctrologos@hotmail.com>
%%%               Maria Christakis <mchrista@softlab.ntua.gr>
%%% Description : Test stripping type and spec related attributes
%%%               (type, spec, opaque, export_type, import_type)
%%%               before instrumentation (import_type not tested).
%%% Created     : 9 Jan 2010
%%%----------------------------------------------------------------------

-module(strip_attr).

-export([foo/0]).

-export_type([mytype/0]).

-record(myrec, {foo :: integer(), bar :: integer()}).

-type mytype() :: #myrec{}.

-opaque mytype_2() :: #myrec{}.

-spec foo() -> {mytype(), mytype_2()}.

foo() -> {#myrec{foo = 42, bar = 42}, #myrec{foo = 42, bar = 42}}.
