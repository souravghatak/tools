%%
%% %CopyrightBegin%
%%
%% Copyright Ericsson AB 2005-2010. All Rights Reserved.
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
-module(emem_SUITE).

%%-define(line_trace, 1).

-export([init_per_suite/1, end_per_suite/1,
	 receive_and_save_trace/2, send_trace/2]).


-export([all/1, init_per_testcase/2, end_per_testcase/2]).

-export([live_node/1,
	 'sparc_sunos5.8_32b_emt2.0'/1,
	 'pc_win2000_32b_emt2.0'/1,
	 'pc.smp_linux2.2.19pre17_32b_emt2.0'/1,
	 'powerpc_darwin7.7.0_32b_emt2.0'/1,
	 'alpha_osf1v5.1_64b_emt2.0'/1,
	 'sparc_sunos5.8_64b_emt2.0'/1,
	 'sparc_sunos5.8_32b_emt1.0'/1,
	 'pc_win2000_32b_emt1.0'/1,
	 'powerpc_darwin7.7.0_32b_emt1.0'/1,
	 'alpha_osf1v5.1_64b_emt1.0'/1,
	 'sparc_sunos5.8_64b_emt1.0'/1]).

-include_lib("kernel/include/file.hrl").

-include("test_server.hrl").

-define(DEFAULT_TIMEOUT, ?t:minutes(5)).

-define(EMEM_64_32_COMMENT,
	"64 bit trace; this build of emem can only handle 32 bit traces").

-record(emem_res, {nodename,
		   hostname,
		   pid,
		   start_time,
		   trace_version,
		   max_word_size,
		   word_size,
		   last_values,
		   maximum,
		   exit_code}).

%%
%%
%% Exported suite functions
%%
%%

all(doc) -> [];
all(suite) ->
    case is_debug_compiled() of
	true -> {skipped, "Not run when debug compiled"};
	false -> test_cases()
    end.
		 
test_cases() ->
    [live_node,
     'sparc_sunos5.8_32b_emt2.0',
     'pc_win2000_32b_emt2.0',
     'pc.smp_linux2.2.19pre17_32b_emt2.0',
     'powerpc_darwin7.7.0_32b_emt2.0',
     'alpha_osf1v5.1_64b_emt2.0',
     'sparc_sunos5.8_64b_emt2.0',
     'sparc_sunos5.8_32b_emt1.0',
     'pc_win2000_32b_emt1.0',
     'powerpc_darwin7.7.0_32b_emt1.0',
     'alpha_osf1v5.1_64b_emt1.0',
     'sparc_sunos5.8_64b_emt1.0'].

init_per_testcase(Case, Config) when is_list(Config) ->
    case maybe_skip(Config) of
	{skip, _}=Skip -> Skip;
	ok ->
	    Dog = ?t:timetrap(?DEFAULT_TIMEOUT),

	    %% Until emem is completely stable we run these tests in a working
	    %% directory with an ignore_core_files file which will make the
	    %% search for core files ignore cores generated by this suite.
	    ignore_cores:setup(?MODULE,
			       Case,
			       [{watchdog, Dog}, {testcase, Case} | Config])
    end.

end_per_testcase(_Case, Config) when is_list(Config) ->
    ignore_cores:restore(Config),
    Dog = ?config(watchdog, Config),
    ?t:timetrap_cancel(Dog),
    ok.

maybe_skip(Config) ->
    DataDir = ?config(data_dir, Config),
    case filelib:is_dir(DataDir) of
	false ->
	    {skip, "No data directory"};
	true ->
	    case ?config(emem, Config) of
		undefined ->
		    {skip, "emem not found"};
		_ ->
		    ok
	    end
    end.

init_per_suite(Config) when is_list(Config) ->
    BinDir = filename:join([code:lib_dir(tools), "bin"]),
    Target = erlang:system_info(system_architecture),
    Res = (catch begin 
		     case check_dir(filename:join([BinDir, Target])) of
			 not_found -> ok;
			 TDir ->
			     check_emem(TDir, purecov),
			     check_emem(TDir, purify),
			     check_emem(TDir, debug),
			     check_emem(TDir, opt)
		     end,
		     check_emem(BinDir, opt),
		     ""
		 end),
    Res ++ ignore_cores:init(Config).

end_per_suite(Config) when is_list(Config) ->
    Config1 = lists:keydelete(emem, 1, Config),
    Config2 = lists:keydelete(emem_comment, 1, Config1),
    ignore_cores:fini(Config2).

%%
%%
%% Test cases
%%
%%

live_node(doc) -> [];
live_node(suite) -> [];
live_node(Config) when is_list(Config) ->
    ?line {ok, EmuFlag, Port} = start_emem(Config),
    ?line Nodename = mk_nodename(Config),
    ?line {ok, Node} = start_node(Nodename, EmuFlag),
    ?line NP = spawn(Node,
		     fun () ->
			     receive go -> ok end,
			     I = spawn(fun () -> ignorer end),
			     GC = fun () ->
					  GCP = fun (P) ->
							garbage_collect(P)
						end,
					  lists:foreach(GCP, processes())
				  end,
			     Seq = fun () -> I ! lists:seq(1, 1000000) end,
			     spawn_link(Seq),
			     B1 = <<0:10000000>>,
			     spawn_link(Seq),
			     B2 = <<0:10000000>>,
			     spawn_link(Seq),
			     B3 = <<0:10000000>>,
			     I ! {B1, B2, B3},
			     GC(),
			     GC(),
			     GC()
		     end),
    ?line MRef = erlang:monitor(process, NP),
    NP ! go,
    ?line receive
	      {'DOWN', MRef, process, NP, Reason} ->
		  ?line spawn(Node, fun () -> halt(17) end),
		  ?line normal = Reason
	  end,
    ?line Res = get_emem_result(Port),
    ?line {ok, Hostname} = inet:gethostname(),
    ?line ShortHostname = short_hostname(Hostname),
    ?line {true, _} = has_prefix(Nodename, Res#emem_res.nodename),
    ?line ShortHostname = short_hostname(Res#emem_res.hostname),
    ?line Bits = case erlang:system_info(wordsize) of
		     4 -> ?line "32 bits";
		     8 -> ?line "64 bits"
		 end,
    ?line Bits = Res#emem_res.word_size,
    ?line "17" = Res#emem_res.exit_code,
    ?line emem_comment(Config).

'sparc_sunos5.8_32b_emt2.0'(doc) -> [];
'sparc_sunos5.8_32b_emt2.0'(suite) -> [];
'sparc_sunos5.8_32b_emt2.0'(Config) when is_list(Config) ->
    ?line Res = run_emem_on_casefile(Config),
    ?line "test_server" = Res#emem_res.nodename,
    ?line "gorbag" = Res#emem_res.hostname,
    ?line "17074" = Res#emem_res.pid,
    ?line "2005-01-14 17:28:37.881980" = Res#emem_res.start_time,
    ?line "2.0" = Res#emem_res.trace_version,
    ?line "32 bits" = Res#emem_res.word_size,
    ?line ["15",
	   "2665739", "8992", "548986", "16131", "539994",
	   "4334192", "1", "99", "15", "98",
	   "0", "0", "49", "0", "49"] = Res#emem_res.last_values, 
    ?line ["5972061", "9662",
	   "7987824", "5",
	   "2375680", "3"] = Res#emem_res.maximum,
    ?line "0" = Res#emem_res.exit_code,
    ?line emem_comment(Config).

'pc_win2000_32b_emt2.0'(doc) -> [];
'pc_win2000_32b_emt2.0'(suite) -> [];
'pc_win2000_32b_emt2.0'(Config) when is_list(Config) ->
    ?line Res = run_emem_on_casefile(Config),
    ?line "test_server" = Res#emem_res.nodename,
    ?line "E-788FCF5191B54" = Res#emem_res.hostname,
    ?line "504" = Res#emem_res.pid,
    ?line "2005-01-24 17:27:28.224000" = Res#emem_res.start_time,
    ?line "2.0" = Res#emem_res.trace_version,
    ?line "32 bits" = Res#emem_res.word_size,
    ?line ["11",
	   "2932575", "8615", "641087", "68924", "632472"]
	= Res#emem_res.last_values, 
    ?line ["5434206", "9285"] = Res#emem_res.maximum,
    ?line "0" = Res#emem_res.exit_code,
    ?line emem_comment(Config).

'pc.smp_linux2.2.19pre17_32b_emt2.0'(doc) -> [];
'pc.smp_linux2.2.19pre17_32b_emt2.0'(suite) -> [];
'pc.smp_linux2.2.19pre17_32b_emt2.0'(Config) when is_list(Config) ->
    ?line Res = run_emem_on_casefile(Config),
    ?line "test_server" = Res#emem_res.nodename,
    ?line "four-roses" = Res#emem_res.hostname,
    ?line "20689" = Res#emem_res.pid,
    ?line "2005-01-20 13:11:26.143077" = Res#emem_res.start_time,
    ?line "2.0" = Res#emem_res.trace_version,
    ?line "32 bits" = Res#emem_res.word_size,
    ?line ["49",
	   "2901817", "9011", "521610", "10875", "512599",
	   "5392096", "2", "120", "10", "118",
	   "0", "0", "59", "0", "59"] = Res#emem_res.last_values,
    ?line ["6182918", "9681",
	   "9062112", "6",
	   "2322432", "3"] = Res#emem_res.maximum,
    ?line "0" = Res#emem_res.exit_code,
    ?line emem_comment(Config).


'powerpc_darwin7.7.0_32b_emt2.0'(doc) -> [];
'powerpc_darwin7.7.0_32b_emt2.0'(suite) -> [];
'powerpc_darwin7.7.0_32b_emt2.0'(Config) when is_list(Config) ->
    ?line Res = run_emem_on_casefile(Config),
    ?line "test_server" = Res#emem_res.nodename,
    ?line "grima" = Res#emem_res.hostname,
    ?line "13021" = Res#emem_res.pid,
    ?line "2005-01-20 15:08:17.568668" = Res#emem_res.start_time,
    ?line "2.0" = Res#emem_res.trace_version,
    ?line "32 bits" = Res#emem_res.word_size,
    ?line ["9",
	   "2784323", "8641", "531105", "15893", "522464"]
	= Res#emem_res.last_values,
    ?line ["6150376", "9311"] = Res#emem_res.maximum,
    ?line "0" = Res#emem_res.exit_code,
    ?line emem_comment(Config).

'alpha_osf1v5.1_64b_emt2.0'(doc) -> [];
'alpha_osf1v5.1_64b_emt2.0'(suite) -> [];
'alpha_osf1v5.1_64b_emt2.0'(Config) when is_list(Config) ->
    ?line Res = run_emem_on_casefile(Config),
    ?line "test_server" = Res#emem_res.nodename,
    ?line "thorin" = Res#emem_res.hostname,
    ?line "224630" = Res#emem_res.pid,
    ?line "2005-01-20 22:38:01.299632" = Res#emem_res.start_time,
    ?line "2.0" = Res#emem_res.trace_version,
    ?line "64 bits" = Res#emem_res.word_size,
    ?line case Res#emem_res.max_word_size of
	      "32 bits" ->
		  ?line emem_comment(Config, ?EMEM_64_32_COMMENT);
	      "64 bits" ->
		  ?line ["22",
			 "6591992", "8625", "516785", "14805", "508160",
			 "11429184", "5", "127", "254", "122",
			 "0", "0", "61", "0", "61"] = Res#emem_res.last_values,
		  ?line ["7041775", "9295",
			 "11593024", "7",
			 "2097152", "3"] = Res#emem_res.maximum,
		  ?line "0" = Res#emem_res.exit_code,
		  ?line emem_comment(Config)
	  end.

'sparc_sunos5.8_64b_emt2.0'(doc) -> [];
'sparc_sunos5.8_64b_emt2.0'(suite) -> [];
'sparc_sunos5.8_64b_emt2.0'(Config) when is_list(Config) ->
    ?line Res = run_emem_on_casefile(Config),
    ?line "test_server" = Res#emem_res.nodename,
    ?line "gorbag" = Res#emem_res.hostname,
    ?line "10907" = Res#emem_res.pid,
    ?line "2005-01-20 13:48:34.677068" = Res#emem_res.start_time,
    ?line "2.0" = Res#emem_res.trace_version,
    ?line "64 bits" = Res#emem_res.word_size,
    ?line case Res#emem_res.max_word_size of
	      "32 bits" ->
		  ?line emem_comment(Config, ?EMEM_64_32_COMMENT);
	      "64 bits" ->
		  ?line ["16",
			 "5032887", "8657", "530635", "14316", "521978",
			 "8627140", "5", "139", "19", "134",
			 "0", "0", "67", "0", "67"] = Res#emem_res.last_values,
		  ?line ["11695070", "9324",
			 "16360388", "10",
			 "4136960", "3"] = Res#emem_res.maximum,
		  ?line "0" = Res#emem_res.exit_code,
		  ?line emem_comment(Config)
	  end.

'sparc_sunos5.8_32b_emt1.0'(doc) -> [];
'sparc_sunos5.8_32b_emt1.0'(suite) -> [];
'sparc_sunos5.8_32b_emt1.0'(Config) when is_list(Config) ->
    ?line Res = run_emem_on_casefile(Config),
    ?line "" = Res#emem_res.nodename,
    ?line "" = Res#emem_res.hostname,
    ?line "" = Res#emem_res.pid,
    ?line "" = Res#emem_res.start_time,
    ?line "1.0" = Res#emem_res.trace_version,
    ?line "32 bits" = Res#emem_res.word_size,
    ?line ["11",
	   "2558261", "8643", "560610", "15325", "551967"]
	= Res#emem_res.last_values,
    ?line ["2791121", "9317"] = Res#emem_res.maximum,
    ?line "0" = Res#emem_res.exit_code,
    ?line emem_comment(Config).

'pc_win2000_32b_emt1.0'(doc) -> [];
'pc_win2000_32b_emt1.0'(suite) -> [];
'pc_win2000_32b_emt1.0'(Config) when is_list(Config) ->
    ?line Res = run_emem_on_casefile(Config),
    ?line "" = Res#emem_res.nodename,
    ?line "" = Res#emem_res.hostname,
    ?line "" = Res#emem_res.pid,
    ?line "" = Res#emem_res.start_time,
    ?line "1.0" = Res#emem_res.trace_version,
    ?line "32 bits" = Res#emem_res.word_size,
    ?line ["6",
	   "2965248", "8614", "640897", "68903", "632283"]
	= Res#emem_res.last_values,
    ?line ["3147090", "9283"] = Res#emem_res.maximum,
    ?line "0" = Res#emem_res.exit_code,
    ?line emem_comment(Config).


'powerpc_darwin7.7.0_32b_emt1.0'(doc) -> [];
'powerpc_darwin7.7.0_32b_emt1.0'(suite) -> [];
'powerpc_darwin7.7.0_32b_emt1.0'(Config) when is_list(Config) ->
    ?line Res = run_emem_on_casefile(Config),
    ?line "" = Res#emem_res.nodename,
    ?line "" = Res#emem_res.hostname,
    ?line "" = Res#emem_res.pid,
    ?line "" = Res#emem_res.start_time,
    ?line "1.0" = Res#emem_res.trace_version,
    ?line "32 bits" = Res#emem_res.word_size,
    ?line ["8",
	   "2852991", "8608", "529662", "15875", "521054"]
	= Res#emem_res.last_values,
    ?line ["3173335", "9278"] = Res#emem_res.maximum,
    ?line "0" = Res#emem_res.exit_code,
    ?line emem_comment(Config).

'alpha_osf1v5.1_64b_emt1.0'(doc) -> [];
'alpha_osf1v5.1_64b_emt1.0'(suite) -> [];
'alpha_osf1v5.1_64b_emt1.0'(Config) when is_list(Config) ->
    ?line Res = run_emem_on_casefile(Config),
    ?line "" = Res#emem_res.nodename,
    ?line "" = Res#emem_res.hostname,
    ?line "" = Res#emem_res.pid,
    ?line "" = Res#emem_res.start_time,
    ?line "1.0" = Res#emem_res.trace_version,
    ?line "64 bits" = Res#emem_res.word_size,
    ?line case Res#emem_res.max_word_size of
	      "32 bits" ->
		  ?line emem_comment(Config, ?EMEM_64_32_COMMENT);
	      "64 bits" ->
		  ?line ["22",
			 "6820094", "8612", "515518", "14812", "506906"]
		      = Res#emem_res.last_values,
		  ?line ["7292413", "9282"] = Res#emem_res.maximum,
		  ?line "0" = Res#emem_res.exit_code,
		  ?line emem_comment(Config)
	  end.

'sparc_sunos5.8_64b_emt1.0'(doc) -> [];
'sparc_sunos5.8_64b_emt1.0'(suite) -> [];
'sparc_sunos5.8_64b_emt1.0'(Config) when is_list(Config) ->
    ?line Res = run_emem_on_casefile(Config),
    ?line "" = Res#emem_res.nodename,
    ?line "" = Res#emem_res.hostname,
    ?line "" = Res#emem_res.pid,
    ?line "" = Res#emem_res.start_time,
    ?line "1.0" = Res#emem_res.trace_version,
    ?line "64 bits" = Res#emem_res.word_size,
    ?line case Res#emem_res.max_word_size of
	      "32 bits" ->
		  ?line emem_comment(Config, ?EMEM_64_32_COMMENT);
	      "64 bits" ->
		  ?line ["15",
			 "4965746", "8234", "543940", "14443", "535706"]
		      = Res#emem_res.last_values,
		  ?line ["11697645", "8908"] = Res#emem_res.maximum,
		  ?line "0" = Res#emem_res.exit_code,
		  ?line emem_comment(Config)
	  end.

%%
%%
%% Auxiliary functions
%%
%%

receive_and_save_trace(PortNumber, FileName) when is_integer(PortNumber),
						  is_list(FileName) ->
    {ok, F} = file:open(FileName, [write, compressed]),
    {ok, LS} = gen_tcp:listen(PortNumber, [inet, {reuseaddr,true}, binary]),
    {ok, S} = gen_tcp:accept(LS),
    gen_tcp:close(LS),
    receive_loop(S,F).

receive_loop(Socket, File) ->
    receive
	{tcp, Socket, Data} ->
	    ok = file:write(File, Data),
	    receive_loop(Socket, File);
	{tcp_closed, Socket} ->
	    file:close(File),
	    ok;
	{tcp_error, Socket, Reason} ->
	    file:close(File),
	    {error, Reason}
    end.

send_trace({Host, PortNumber}, FileName) when is_list(Host),
					      is_integer(PortNumber),
					      is_list(FileName) ->
    ?line {ok, F} = file:open(FileName, [read, compressed]),
    ?line {ok, S} = gen_tcp:connect(Host, PortNumber, [inet,{packet, 0}]),
    ?line send_loop(S, F);
send_trace(EmuFlag, FileName) when is_list(EmuFlag),
				   is_list(FileName) ->
    ?line ["+Mit", IpAddrStr, PortNoStr] = string:tokens(EmuFlag, " :"),
    ?line send_trace({IpAddrStr, list_to_integer(PortNoStr)}, FileName).

send_loop(Socket, File) ->
    ?line case file:read(File, 128) of
	      {ok, Data} ->
		  ?line case gen_tcp:send(Socket, Data) of
			    ok -> ?line send_loop(Socket, File);
			    Error ->
				?line gen_tcp:close(Socket),
				?line file:close(File),
				Error
			end;
	      eof ->
		  ?line gen_tcp:close(Socket),
		  ?line file:close(File),
		  ?line ok;
	      Error ->
		  ?line gen_tcp:close(Socket),
		  ?line file:close(File),
		  ?line Error
	  end.

check_emem(Dir, Type) when is_atom(Type) ->
    ExeSuffix = case ?t:os_type() of
		    {win32, _} -> ".exe";
		    _ -> ""
		end,
    TypeSuffix = case Type of
		     opt -> "";
		     _ -> "." ++ atom_to_list(Type)
		 end,
    Emem = "emem" ++ TypeSuffix ++ ExeSuffix,
    case check_file(filename:join([Dir, Emem])) of
	not_found -> ok;
	File ->
	    Comment = case Type of
			  opt -> "";
			  _ -> "[emem " ++ atom_to_list(Type) ++ " compiled]"
		      end,
	    throw([{emem, File}, {emem_comment, Comment}])
    end.

check_dir(DirName) ->
    case file:read_file_info(DirName) of
	{ok, #file_info {type = directory, access = A}} when A == read;
							     A == read_write ->
	    DirName;
	_ ->
	    not_found
    end.

check_file(FileName) ->
    case file:read_file_info(FileName) of
	{ok, #file_info {type = regular, access = A}} when A == read;
							   A == read_write ->
	    ?line FileName;
	_ ->
	    ?line not_found
    end.

emem_comment(Config) when is_list(Config) ->
    emem_comment(Config, "").

emem_comment(Config, ExtraComment)
  when is_list(Config), is_list(ExtraComment) ->
    case {?config(emem_comment, Config), ExtraComment} of
	{"", ""} -> ?line ok;
	{"", XC} -> ?line {comment, XC};
	{EmemC, ""} -> ?line {comment, EmemC};
	{EmemC, XC} -> ?line {comment, EmemC ++ " " ++ XC}
    end.

run_emem_on_casefile(Config) ->
    CaseName = atom_to_list(?config(testcase, Config)),
    ?line File = filename:join([?config(data_dir, Config), CaseName ++ ".gz"]),
    ?line case check_file(File) of
	      not_found ->
		  ?line ?t:fail({error, {filenotfound, File}});
	      _ ->
		  ?line ok
	  end,
    ?line {ok, EmuFlag, Port} = start_emem(Config),
    ?line Parent = self(),
    ?line Ref = make_ref(),
    ?line spawn_link(fun () ->
			     SRes = send_trace(EmuFlag, File),
			     Parent ! {Ref, SRes}
		     end),
    ?line Res = get_emem_result(Port),
    ?line receive
	      {Ref, ok} ->
		  ?line ok;
	      {Ref, SendError} ->
		  ?line ?t:format("Send result: ~p~n", [SendError])
	  end,
    ?line Res.

get_emem_result(Port) ->
    ?line {Res, LV} = get_emem_result(Port, {#emem_res{}, []}),
    ?line Res#emem_res{last_values = string:tokens(LV, " ")}.

get_emem_result(Port, {_EmemRes, _LastValues} = Res) ->
    ?line case get_emem_line(Port) of
	      eof ->
		  ?line Res;
	      Line ->
		  ?line get_emem_result(Port, parse_emem_line(Line, Res))
	  end.

parse_emem_main_header_footer_line(Line, {ER, LV} = Res) ->

    %% Header
    ?line case has_prefix("> Nodename:", Line) of
	      {true, NN} ->
		  ?line throw({ER#emem_res{nodename = strip(NN)}, LV});
	      false -> ?line ok
	  end,
    ?line case has_prefix("> Hostname:", Line) of
	      {true, HN} ->
		  ?line throw({ER#emem_res{hostname = strip(HN)}, LV});
	      false -> ?line ok
	  end,
    ?line case has_prefix("> Pid:", Line) of
	      {true, P} ->
		  ?line throw({ER#emem_res{pid = strip(P)}, LV});
	      false -> ?line ok
	  end,
    ?line case has_prefix("> Start time (UTC):", Line) of
	      {true, ST} ->
		  ?line throw({ER#emem_res{start_time = strip(ST)}, LV});
	      false -> ?line ok
	  end,
    ?line case has_prefix("> Actual trace version:", Line) of
	      {true, TV} ->
		  ?line throw({ER#emem_res{trace_version = strip(TV)}, LV});
	      false -> ?line ok
	  end,
    ?line case has_prefix("> Maximum trace word size:", Line) of
	      {true, MWS} ->
		  ?line throw({ER#emem_res{max_word_size = strip(MWS)}, LV});
	      false -> ?line ok
	  end,
    ?line case has_prefix("> Actual trace word size:", Line) of
	      {true, WS} ->
		  ?line throw({ER#emem_res{word_size = strip(WS)}, LV});
	      false -> ?line ok
	  end,

    %% Footer
    ?line case has_prefix("> Maximum:", Line) of
	      {true, M} ->
		  ?line throw({ER#emem_res{maximum = string:tokens(M," ")}, LV});
	      false -> ?line ok
	  end,
    ?line case has_prefix("> Emulator exited with code:", Line) of
	      {true, EC} ->
		  ?line throw({ER#emem_res{exit_code = strip(EC)}, LV});
	      false -> ?line ok
	  end,
    ?line Res.

parse_emem_header_line(_Line, {_ER, _LV} = Res) ->
    ?line Res.
    
parse_emem_value_line(Line, {EmemRes, _OldLastValues}) ->
    ?line {EmemRes, Line}.

parse_emem_line("", Res) ->
    ?line Res;
parse_emem_line(Line, Res) ->
    ?line [Prefix | _] = Line,
    case Prefix of
	$> -> ?line catch parse_emem_main_header_footer_line(Line, Res);
	$| -> ?line catch parse_emem_header_line(Line, Res);
	_ -> ?line catch parse_emem_value_line(Line, Res)
    end.

start_emem(Config) when is_list(Config) ->
    ?line Emem = ?config(emem, Config),
    ?line Cd = case ignore_cores:dir(Config) of
		   false -> [];
		   Dir -> [{cd, Dir}]
	       end,
    ?line case open_port({spawn, Emem ++ " -t -n -o -i 1"},
			 Cd ++ [{line, 1024}, eof]) of
	      Port when is_port(Port) -> ?line {ok, read_emu_flag(Port), Port};
	      Error -> ?line ?t:fail(Error)
	  end.

read_emu_flag(Port) ->
    ?line Line = case get_emem_line(Port) of
		     eof -> ?line ?t:fail(unexpected_end_of_file);
		     L -> ?line L
		 end,
    ?line case has_prefix("> Emulator command line argument:", Line) of
	      {true, EmuFlag} -> EmuFlag;
	      false -> ?line read_emu_flag(Port)
	  end.

get_emem_line(Port, Acc) ->
    ?line receive
	      {Port, {data, {eol, Data}}} ->
		  ?line Res = case Acc of
				  [] -> ?line Data;
				  _ -> ?line lists:flatten([Acc|Data])
			      end,
		  ?line ?t:format("~s", [Res]),
		  ?line Res;
	      {Port, {data, {noeol, Data}}} ->
		  ?line get_emem_line(Port, [Acc|Data]);
	      {Port, eof} ->
		  ?line port_close(Port),
		  ?line eof
	  end.

get_emem_line(Port) ->
    ?line get_emem_line(Port, []).

short_hostname([]) ->
    [];
short_hostname([$.|_]) ->
    [];
short_hostname([C|Cs]) ->
    [C | short_hostname(Cs)].

has_prefix([], List) when is_list(List) ->
    {true, List};
has_prefix([P|Xs], [P|Ys]) ->
    has_prefix(Xs, Ys);
has_prefix(_, _) ->
    false.

strip(Str) -> string:strip(Str).
    
mk_nodename(Config) ->
    {A, B, C} = now(),
    atom_to_list(?MODULE)
	++ "-" ++ atom_to_list(?config(testcase, Config))
	++ "-" ++ integer_to_list(A*1000000000000 + B*1000000 + C).

start_node(Name, Args) ->
    ?line Pa = filename:dirname(code:which(?MODULE)),
    ?line ?t:start_node(Name, peer, [{args, Args ++ " -pa " ++ Pa}]).

% stop_node(Node) ->
%     ?t:stop_node(Node).

is_debug_compiled() ->
    is_debug_compiled(erlang:system_info(system_version)).

is_debug_compiled([$d,$e,$b,$u,$g | _]) ->
    true;
is_debug_compiled([ _, _, _, _]) ->
    false;
is_debug_compiled([]) ->
    false;
is_debug_compiled([_|Rest]) ->
    is_debug_compiled(Rest).
