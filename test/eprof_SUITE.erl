%%
%% %CopyrightBegin%
%%
%% Copyright Ericsson AB 1996-2011. All Rights Reserved.
%%
%% The contents of this file are subject to the Erlang Public License,
%% Version 1.1, (the "License"); you may not use this file except in
%% compliance with the License. You should have received a copy of the
%% Erlang Public License along with this software. If not, it can be
%% retrieved online at http://www.erlang.org/.
%%
%% Software distributed under the License is distributed on an "AS IS"
%% basis, WITHOUT WARRANTY OF ANY KIND, either express or implied. See
%% the License for the specific language governing rights and limitations
%% under the License.
%%
%% %CopyrightEnd%
%%
-module(eprof_SUITE).

-include_lib("test_server/include/test_server.hrl").

-export([all/0, suite/0,groups/0,init_per_suite/1, end_per_suite/1, 
	 init_per_group/2,end_per_group/2,tiny/1,eed/1,basic/1]).

suite() -> [{ct_hooks,[ts_install_cth]}].

all() -> 
    [basic, tiny, eed].

groups() -> 
    [].

init_per_suite(Config) ->
    Config.

end_per_suite(_Config) ->
    ok.

init_per_group(_GroupName, Config) ->
    Config.

end_per_group(_GroupName, Config) ->
    Config.


basic(suite) -> [];
basic(Config) when is_list(Config) ->

    %% load eprof_test and change directory

    {ok, OldCurDir} = file:get_cwd(),
    Datadir = ?config(data_dir, Config),
    Privdir = ?config(priv_dir, Config),
    {ok,eprof_test} = compile:file(filename:join(Datadir, "eprof_test"),
					       [trace,{outdir, Privdir}]),
    ok = file:set_cwd(Privdir),
    code:purge(eprof_test),
    {module,eprof_test} = code:load_file(eprof_test),

    %% rootset profiling

    ensure_eprof_stopped(),
    profiling = eprof:profile([self()]),
    {error, already_profiling} = eprof:profile([self()]),
    profiling_stopped = eprof:stop_profiling(),
    profiling_already_stopped = eprof:stop_profiling(),
    profiling = eprof:start_profiling([self(),self(),self()]),
    profiling_stopped = eprof:stop_profiling(),

    %% with patterns

    profiling = eprof:start_profiling([self()], {?MODULE, '_', '_'}),
    {error, already_profiling} = eprof:start_profiling([self()], {?MODULE, '_', '_'}),
    profiling_stopped = eprof:stop_profiling(),
    profiling = eprof:start_profiling([self()], {?MODULE, start_stop, '_'}),
    profiling_stopped = eprof:stop_profiling(),
    profiling = eprof:start_profiling([self()], {?MODULE, start_stop, 1}),
    profiling_stopped = eprof:stop_profiling(),

    %% with fun

    {ok, _} = eprof:profile(fun() -> eprof_test:go(10) end),
    profiling = eprof:profile([self()]),
    {error, already_profiling} = eprof:profile(fun() -> eprof_test:go(10) end),
    profiling_stopped = eprof:stop_profiling(),
    {ok, _} = eprof:profile(fun() -> eprof_test:go(10) end),
    {ok, _} = eprof:profile([], fun() -> eprof_test:go(10) end),
    Pid     = whereis(eprof),
    {ok, _} = eprof:profile(erlang:processes() -- [Pid], fun() -> eprof_test:go(10) end),
    {ok, _} = eprof:profile([], fun() -> eprof_test:go(10) end, {eprof_test, '_', '_'}),
    {ok, _} = eprof:profile([], fun() -> eprof_test:go(10) end, {eprof_test, go, '_'}),
    {ok, _} = eprof:profile([], fun() -> eprof_test:go(10) end, {eprof_test, go, 1}),
    {ok, _} = eprof:profile([], fun() -> eprof_test:go(10) end, {eprof_test, dec, 1}),

    %% error case

    error     = eprof:profile([Pid], fun() -> eprof_test:go(10) end),
    Pid       = whereis(eprof),
    error     = eprof:profile([Pid], fun() -> eprof_test:go(10) end),
    A         = spawn(fun() -> receive _ -> ok end end),
    profiling = eprof:profile([A]),
    true      = exit(A, kill_it),
    profiling_stopped = eprof:stop_profiling(),
    {error,_} = eprof:profile(fun() -> a = b end),

    %% with mfa

    {ok, _} = eprof:profile([], eprof_test, go, [10]),
    {ok, _} = eprof:profile([], eprof_test, go, [10], {eprof_test, dec, 1}),

    %% dump

    {ok, _} = eprof:profile([], fun() -> eprof_test:go(10) end, {eprof_test, '_', '_'}),
    [{_, Mfas}] = eprof:dump(),
    Dec_mfa = {eprof_test, dec, 1},
    Go_mfa  = {eprof_test, go,  1},
    {value, {Go_mfa,  { 1, _Time1}}} = lists:keysearch(Go_mfa,  1, Mfas),
    {value, {Dec_mfa, {11, _Time2}}} = lists:keysearch(Dec_mfa, 1, Mfas),

    %% change current working directory

    ok = file:set_cwd(OldCurDir),
    stopped = eprof:stop(),
    ok.

tiny(suite) -> [];
tiny(Config) when is_list(Config) -> 
    ensure_eprof_stopped(),
    {ok, OldCurDir} = file:get_cwd(),
    Datadir = ?config(data_dir, Config),
    Privdir = ?config(priv_dir, Config),
    TTrap=?t:timetrap(60*1000),
    % (Trace)Compile to priv_dir and make sure the correct version is loaded.
    {ok,eprof_suite_test} = compile:file(filename:join(Datadir,
							     "eprof_suite_test"),
					       [trace,{outdir, Privdir}]),
    ok = file:set_cwd(Privdir),
    code:purge(eprof_suite_test),
    {module,eprof_suite_test} = code:load_file(eprof_suite_test),
    {ok,_Pid} = eprof:start(),
    nothing_to_analyze = eprof:analyze(),
    nothing_to_analyze = eprof:analyze(total),
    eprof:profile([], eprof_suite_test, test, [Config]),
    ok = eprof:analyze(),
    ok = eprof:analyze(total),
    ok = eprof:log("eprof_SUITE_logfile"),
    stopped = eprof:stop(),
    ?t:timetrap_cancel(TTrap),
    ok = file:set_cwd(OldCurDir),
    ok.

eed(suite) -> [];
eed(Config) when is_list(Config) ->
    ensure_eprof_stopped(),
    Datadir = ?config(data_dir, Config),
    Privdir = ?config(priv_dir, Config),
    TTrap=?t:timetrap(5*60*1000),

    %% (Trace)Compile to priv_dir and make sure the correct version is loaded.
    code:purge(eed),
    {ok,eed} = c:c(filename:join(Datadir, "eed"), [trace,{outdir,Privdir}]),
    {ok,_Pid} = eprof:start(),
    Script = filename:join(Datadir, "ed.script"),
    ok = file:set_cwd(Datadir),
    {T1,_} = statistics(runtime),
    ok = eed:file(Script),
    ok = eed:file(Script),
    ok = eed:file(Script),
    ok = eed:file(Script),
    ok = eed:file(Script),
    ok = eed:file(Script),
    ok = eed:file(Script),
    ok = eed:file(Script),
    ok = eed:file(Script),
    ok = eed:file(Script),
    {T2,_} = statistics(runtime),
    {ok,ok} = eprof:profile([], eed, file, [Script]),
    {T3,_} = statistics(runtime),
    profiling_already_stopped = eprof:stop_profiling(),
    ok = eprof:analyze(),
    ok = eprof:analyze(total),
    ok = eprof:log("eprof_SUITE_logfile"),
    stopped = eprof:stop(),
    ?t:timetrap_cancel(TTrap),
    try
	S = lists:flatten(io_lib:format("~p times slower",
					[10*(T3-T2)/(T2-T1)])),
	{comment,S}
    catch
	error:badarith ->
	    {comment,"No time elapsed. Bad clock? Fast computer?"}
    end.

ensure_eprof_stopped() ->
    Pid = whereis(eprof),
    case whereis(eprof) of
	undefined ->
	    ok;
	Pid ->
	    stopped=eprof:stop()
    end.
