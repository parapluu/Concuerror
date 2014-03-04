%%%----------------------------------------------------------------------
%%% Copyright (c) 2013, Alkis Gotovos <el3ctrologos@hotmail.com>,
%%%                     Maria Christakis <mchrista@softlab.ntua.gr>
%%%                 and Kostis Sagonas <kostis@cs.ntua.gr>.
%%% All rights reserved.
%%%
%%% This file is distributed under the Simplified BSD License.
%%% Details can be found in the LICENSE file.
%%%----------------------------------------------------------------------
%%% Authors     : Ilias Tsitsimpis <i.tsitsimpis@gmail.com>
%%% Description : Instrumentation header file
%%%----------------------------------------------------------------------

%%%----------------------------------------------------------------------
%%% Definitions
%%%----------------------------------------------------------------------

%% List of attributes that should be stripped.
-define(ATTR_STRIP, [type, spec, opaque, export_type, import_type, callback]).

%% Instrumented auto-imported functions of 'erlang' module.
-define(INSTR_ERL_FUN,
        [{demonitor, 1},
         {demonitor, 2},
         {exit, 2},
         {halt, 0},
         {halt, 1},
         {is_process_alive, 1},
         {link, 1},
         {monitor, 2},
         {process_flag, 2},
         {register, 2},
         {spawn, 1},
         {spawn, 3},
         {spawn_link, 1},
         {spawn_link, 3},
         {spawn_monitor, 1},
         {spawn_monitor, 3},
         {spawn_opt, 2},
         {spawn_opt, 4},
         {unlink, 1},
         {unregister, 1},
         {port_command, 2},
         {port_command, 3},
         {port_control, 3},
         {apply, 3},
         {whereis, 1}]).

%% Instrumented functions called as erlang:FUNCTION.
-define(INSTR_ERL_MOD_FUN,
        [{erlang, send, 2},
         {erlang, send, 3},
         {erlang, send_after, 3},
         {erlang, start_timer, 3}] ++
            [{erlang, F, A} || {F, A} <- ?INSTR_ERL_FUN]).

%% Instrumented functions from ets module.
-define(INSTR_ETS_FUN,
        [{ets, insert_new, 2},
         {ets, lookup, 2},
         {ets, select_delete, 2},
         {ets, insert, 2},
         {ets, delete, 1},
         {ets, delete, 2},
         {ets, filter, 3},
         {ets, match, 2},
         {ets, match, 3},
         {ets, match_object, 2},
         {ets, match_object, 3},
         {ets, match_delete, 2},
         {ets, new, 2},
         {ets, info, 1},
         {ets, info, 2},
         {ets, foldl, 3}]).

%% Instrumented mod:fun.
-define(INSTR_MOD_FUN, ?INSTR_ERL_MOD_FUN ++ ?INSTR_ETS_FUN).

%% Key in ?NT_INSTR to use for temp directory.
-define(INSTR_TEMP_DIR, '_._instr_temp_dir').
%% Key in ?NT_INSTR to use for `fail-uninstrumented' flag.
-define(FAIL_BB, '_._instr_fail_bb').

%% -------------------------------------------------------------------
%% BIFs (taken from file `otp/erts/emulator/beam/bif.tab'
%% We don't care about `erlang' and `ets' BIFS as
%% we don't rename them anyway.
-define(PREDEF_BIFS,
    [% Bifs in `math' module
     {math, cos,    1},
     {math, cosh,   1},
     {math, sin,    1},
     {math, sinh,   1},
     {math, tan,    1},
     {math, tanh,   1},
     {math, acos,   1},
     {math, acosh,  1},
     {math, asin,   1},
     {math, asinh,  1},
     {math, atan,   1},
     {math, atanh,  1},
     {math, erf,    1},
     {math, erfc,   1},
     {math, exp,    1},
     {math, log,    1},
     {math, log10,  1},
     {math, sqrt,   1},
     {math, atan2,  2},
     {math, pow,    2},
     % Bifs in `os' module
     {os,   putenv,     2},
     {os,   getenv,     0},
     {os,   getenv,     1},
     {os,   getpid,     0},
     {os,   timestamp,  0},
     % Bifs in the `re' module
     {re,   compile,    1},
     {re,   compile,    2},
     {re,   run,        2},
     {re,   run,        3},
     % Bifs in the `lists' module
     {lists,    member,     2},
     {lists,    reverse,    2},
     {lists,    keymember,  3},
     {lists,    keysearch,  3},
     {lists,    keyfind,    3},
     % Bifs for `debugging'
     {erts_debug,   disassemble,    1},
     {erts_debug,   breakpoint,     2},
     {erts_debug,   same,           2},
     {erts_debug,   flat_size,      1},
     {erts_debug,   get_internal_state, 1},
     {erts_debug,   set_internal_state, 2},
     {erts_debug,   display,        1},
     {erts_debug,   dist_ext_to_term,   2},
     {erts_debug,   instructions,   0},
     % `Monitor testing' bif's
     {erts_debug,   dump_monitors,  1},
     {erts_debug,   dump_links,     1},
     % `Lock counter' bif's
     {erts_debug,   lock_counters,  1},
     % New Bifs in `R8'
     {code, get_chunk,  2},
     {code, module_md5, 1},
     {code, make_stub_module, 3},
     {code, is_module_native, 1},
     % New Bifs in `R10B'
     {string,   to_integer, 1},
     {string,   to_float,   1},
     % New Bifs in `R12B-5'
     {unicode,  characters_to_binary, 2},
     {unicode,  characters_to_list,   2},
     {unicode,  bin_is_7bit,          1},
     % New Bifs in `R13B-1'
     {net_kernel, dflag_unicode_io, 1},
     % The `binary' match bifs
     {binary,   compile_pattern,    1},
     {binary,   match,      2},
     {binary,   match,      3},
     {binary,   matches,    2},
     {binary,   matches,    3},
     {binary,   longest_common_prefix,  1},
     {binary,   longest_common_suffix,  1},
     {binary,   first,      1},
     {binary,   last,       1},
     {binary,   at,         2},
     {binary,   part,       2},
     {binary,   part,       3},
     {binary,   bin_to_list, 1},
     {binary,   bin_to_list, 2},
     {binary,   bin_to_list, 3},
     {binary,   list_to_bin, 1},
     {binary,   copy,       1},
     {binary,   copy,       2},
     {binary,   referenced_byte_size, 1},
     {binary,   encode_unsigned, 1},
     {binary,   encode_unsigned, 2},
     {binary,   decode_unsigned, 1},
     {binary,   decode_unsigned, 2},
     % Helpers for unicode filenames
     {file, native_name_encoding, 0}
    ]).
