-module(ets_global_global).

-compile(export_all).

%%------------------------------------------------------------------------------

scenarios() ->
  [ new_new
  , new_delete
  , new_exit
  , new_rename_free
  , new_rename_taken
  , rename_delete
  , rename_exit
  , rename_rename_free
  , rename_rename_taken
  ].

new_new() ->
  %% 2 cases: exactly one of P/Q succeed/fail
  P = self(),
  Fun =
    fun() ->
        ets_new_2(),
        P ! self(),
        receive ok -> ok end
    end,
  Q = spawn(Fun),
  R = spawn(Fun),
  receive
    Q ->
      receive
        R ->
          Q ! ok,
          R ! ok
      end
  end.

new_delete() ->
  %% 2 cases: child new before/after delete
  ets_new_2(),
  spawn(fun ets_new_2/0),
  ets_delete_1().

new_exit() ->
  %% 2 cases: child new before/after exit
  ets_new_2(),
  spawn(fun ets_new_2/0),
  exit(normal).

new_rename_free() ->
  %% 2 cases: exactly one of P/Q succeed/fail
  P = self(),
  FunQ =
    fun() ->
        ets_new_2(),
        ets_rename_2(),
        P ! self(),
        receive ok -> ok end
    end,
  FunR =
    fun() ->
        catch ets:new(new_name, [named_table, public]),
        P ! self(),
        receive ok -> ok end
    end,
  Q = spawn(FunQ),
  R = spawn(FunR),
  receive
    Q ->
      receive
        R ->
          Q ! ok,
          R ! ok
      end
  end.

new_rename_taken() ->
  %% 2 cases: exactly one of P/Q succeed/fail
  P = self(),
  FunQ =
    fun() ->
        ets_new_2(),
        P ! self(),
        ets_rename_2(),
        P ! self(),
        receive ok -> ok end
    end,
  FunR =
    fun() ->
        ets_new_2(),
        P ! self(),
        receive ok -> ok end
    end,
  Q = spawn(FunQ),
  receive Q -> ok end,
  R = spawn(FunR),
  receive
    Q ->
      receive
        R ->
          Q ! ok,
          R ! ok
      end
  end.

rename_delete() ->
  %% 2 cases: child rename before/after delete
  ets_new_2(),
  Fun =
    fun() ->
        ets:new(new_name, [named_table, public]),
        catch ets:rename(new_name, table)
    end,
  spawn(Fun),
  ets_delete_1().

rename_exit() ->
  %% 2 cases: child rename before/after delete
  ets_new_2(),
  Fun =
    fun() ->
        ets:new(new_name, [named_table, public]),
        catch ets:rename(new_name, table)
    end,
  spawn(Fun),
  exit(normal).

rename_rename_free() ->
  %% 2 cases: exactly one of P/Q succeed/fail
  P = self(),
  FunQ =
    fun() ->
        ets_new_2(),
        ets_rename_2(),
        P ! self(),
        receive ok -> ok end
    end,
  FunR =
    fun() ->
        ets:new(other_name, [named_table, public]),
        catch ets:rename(other_name, new_name),
        P ! self(),
        receive ok -> ok end
    end,
  Q = spawn(FunQ),
  R = spawn(FunR),
  receive
    Q ->
      receive
        R ->
          Q ! ok,
          R ! ok
      end
  end.

rename_rename_taken() ->
  %% 2 cases: exactly one of P/Q succeed/fail
  P = self(),
  FunQ =
    fun() ->
        ets_new_2(),
        P ! self(),
        ets_rename_2(),
        P ! self(),
        receive ok -> ok end
    end,
  FunR =
    fun() ->
        ets:new(other_name, [named_table, public]),
        catch ets:rename(other_name, new_name),
        P ! self(),
        receive ok -> ok end
    end,
  Q = spawn(FunQ),
  receive Q -> ok end,
  R = spawn(FunR),
  receive
    Q ->
      receive
        R ->
          Q ! ok,
          R ! ok
      end
  end.

%%------------------------------------------------------------------------------
%% Global Ops
%%------------------------------------------------------------------------------

ets_new_2() ->
  catch ets:new(table, [named_table, public]).

%%------------------------------------------------------------------------------

ets_delete_1() ->
  catch ets:delete(table).

%%------------------------------------------------------------------------------

ets_rename_2() ->
  catch ets:rename(table, new_name).
