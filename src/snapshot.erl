%%%----------------------------------------------------------------------
%%% File        : snapshot.erl
%%% Author      : Maria Christakis <mchrista@softlab.ntua.gr>
%%% Description : Snapshot utilities
%%% Created     : 30 Sep 2010
%%%
%%% @doc: Snapshot utilities
%%% @end
%%%----------------------------------------------------------------------

-module(snapshot).

-export([export/4, get_analysis/1, get_module_id/1,
         get_function_id/1, get_modules/1, get_selection/1,
         import/1, selection/2]).

-include("gen.hrl").

%%%----------------------------------------------------------------------
%%% Types and Records
%%%----------------------------------------------------------------------

-type analysis()  :: 'undef' | sched:analysis_ret().
-type files()     :: [binary()].
-type modules()   :: [string()].
-type selection() :: [{'module' | 'function', integer()}].

-record(snapshot, {analysis  :: analysis(),
                   files     :: files(),
                   modules   :: modules(),
                   selection :: selection()}).

-type snapshot() :: #snapshot{}.

%%%----------------------------------------------------------------------
%%% User interface
%%%----------------------------------------------------------------------

-spec export(analysis(), [file()], selection(), file()) -> 'ok'.

export(Analysis, Files, Selection, Export) ->
    Modules = [filename:basename(F) || F <- Files],
    BinFiles = [begin
                    {ok, Bin} = file:read_file(F),
                    Bin
                end|| F <- Files],
    Snapshot = new(Analysis, BinFiles, Modules, Selection),
    to_file(Export, Snapshot).

-spec from_file(file()) -> snapshot() | 'ok'.

from_file(File) ->
    case file:read_file(File) of
        {ok, Bin} ->
            try binary_to_term(Bin) of
                #snapshot{} = Snapshot ->
                    log:log("Read file ~s successfully.~n", [File]),
                    Snapshot;
                _ ->
                    log:log("File ~s is not valid.~n", [File])
            catch
                _:_ ->
                    log:log("File ~s is not valid.~n", [File])
            end;
        {error, enoent} ->
            log:log("File ~s does not exist.~n", [File]);
        {error, _} ->
            log:log("Could not read file ~s.~n", [File])
    end.

-spec get_analysis(snapshot()) -> analysis().

get_analysis(#snapshot{analysis = Analysis}) ->
    Analysis.

-spec get_module_id(selection()) -> integer().

get_module_id(Selection) ->
    {module, ModuleID} = lists:keyfind(module, 1, Selection),
    ModuleID.

-spec get_function_id(selection()) -> integer().

get_function_id(Selection) ->
    {function, FunctionID} = lists:keyfind(function, 1, Selection),
    FunctionID.

-spec get_modules(snapshot()) -> modules().

get_modules(#snapshot{modules = Modules}) ->
    Modules.

-spec get_selection(snapshot()) -> selection().

get_selection(#snapshot{selection = Selection}) ->
    Selection.

-spec import(file()) -> snapshot() | 'ok'.

import(File) ->
    case from_file(File) of
        #snapshot{files = Files, modules = Modules} = Snapshot ->
            case file:make_dir(?IMPORT_DIR) of
                ok ->
                    NewModules = write_code(Modules, Files),
                    Snapshot#snapshot{modules = NewModules};
                {error, _Reason} ->
                    log:log("Could not create import directory.~n")
            end;
        _ -> ok
    end.

-spec new(analysis(), files(), modules(), selection()) -> snapshot().

new(Analysis, Files, Modules, Selection) ->
    #snapshot{analysis = Analysis, files = Files,
              modules = Modules, selection = Selection}.

-spec selection(integer(), integer()) -> selection().

selection(ModuleID, FunctionID) ->
    [{module, ModuleID}, {function, FunctionID}].

-spec to_file(file(), snapshot()) -> 'ok'.

to_file(File, Snapshot) ->
    Bin = term_to_binary(Snapshot, [compressed]),
    case file:write_file(File, Bin) of
        ok ->
            log:log("Wrote file ~s successfully.~n", [File]);
        {error, _Reason} ->
            log:log("Could not write file ~s.~n", [File])
    end.

-spec write_code(modules(), files()) -> modules().

write_code(Modules, Files) ->
    write_code(Modules, Files, []).

write_code([], [], Acc) ->
    lists:reverse(Acc);
write_code([M|Modules], [F|Files], Acc) ->
    NewM = filename:join([?IMPORT_DIR, M]),
    ok = file:write_file(NewM, F),
    write_code(Modules, Files, [NewM|Acc]).
