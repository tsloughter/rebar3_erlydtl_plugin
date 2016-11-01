%% -*- erlang-indent-level: 4;indent-tabs-mode: nil -*-
%% ex: ts=4 sw=4 et
%% -------------------------------------------------------------------
%%
%% rebar: Erlang Build Tools
%%
%% Copyright (c) 2009 Dave Smith (dizzyd@dizzyd.com),
%%                    Bryan Fink (bryan@basho.com)
%%
%% Permission is hereby granted, free of charge, to any person obtaining a copy
%% of this software and associated documentation files (the "Software"), to deal
%% in the Software without restriction, including without limitation the rights
%% to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
%% copies of the Software, and to permit persons to whom the Software is
%% furnished to do so, subject to the following conditions:
%%
%% The above copyright notice and this permission notice shall be included in
%% all copies or substantial portions of the Software.
%%
%% THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
%% IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
%% FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
%% AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
%% LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
%% OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
%% THE SOFTWARE.
%% -------------------------------------------------------------------

%% The rebar_erlydtl_compiler module is a plugin for rebar that compiles
%% ErlyDTL templates.  By default, it compiles all priv/templates/*.dtl
%% to ebin/*_dtl.beam.
%%
%% Configuration options should be placed in rebar.config under
%% 'erlydtl_opts'.  It can be a list of name-value tuples or a list of
%% lists of name-value tuples if you have multiple template directories
%% that need to have different settings (see example below).
%%
%% Available options include:
%%
%%  doc_root: where to find templates to compile
%%            "priv/templates" by default
%%
%%  out_dir: where to put compiled template beam files
%%           "ebin" by default
%%
%%  source_ext: the file extension the template sources have
%%              ".dtl" by default
%%
%%  module_ext: characters to append to the template's module name
%%              "_dtl" by default
%%
%%  recursive: boolean that determines if doc_root(s) need to be
%%             scanned recursively for matching template file names
%%             (default: true).
%% For example, if you had:
%%   /t_src/
%%          base.html
%%          foo.html
%%
%% And you wanted them compiled to:
%%   /priv/
%%         base.beam
%%         foo.beam
%%
%% You would add to your rebar.config:
%%   {erlydtl_opts, [
%%               {doc_root,   "t_src"},
%%               {out_dir,    "priv"},
%%               {source_ext, ".html"},
%%               {module_ext, ""}
%%              ]}.
%%
%% The default settings are the equivalent of:
%%   {erlydtl_opts, [
%%               {doc_root,   "priv/templates"},
%%               {out_dir,    "ebin"},
%%               {source_ext, ".dtl"},
%%               {module_ext, "_dtl"}
%%              ]}.
%%
%% The following example will compile the following templates:
%% "src/*.dtl" files into "ebin/*_dtl.beam" and
%% "priv/templates/*.html" into "ebin/*.beam". Note that any tuple option
%% (such as 'out_dir') in the outer list is added to each inner list:
%%   {erlydtl_opts, [
%%      {out_dir, "ebin"},
%%      {recursive, false},
%%      [
%%          {doc_root, "src"}, {module_ext, "_dtl"}
%%      ],
%%      [
%%          {doc_root, "priv/templates"}, {module_ext, ""}, {source_ext, ".html"}
%%      ]
%%   ]}.
-module(rebar3_erlydtl_plugin).

-behaviour(provider).

-export([init/1,
         do/1,
         format_error/1]).

-define(PROVIDER, erlydtl).
-define(DEPS, [{default, compile}]).

%% ===================================================================
%% Public API
%% ===================================================================

-spec init(rebar_state:t()) -> {ok, rebar_state:t()}.
init(State) ->
    State1 = rebar_state:add_provider(State, providers:create([{name, ?PROVIDER},
                                                               {module, ?MODULE},
                                                               %% {namespace, erlydtl},
                                                               %% {bare, false},
                                                               {deps, ?DEPS},
                                                               {example, "rebar3 erlydtl compile"},
                                                               {short_desc, "Compile erlydtl templates."},
                                                               {desc, "Compile erlydtl templates."},
                                                               {opts, []}])),
    {ok, State1}.

expand_opts(Opts) ->
    SharedOpts = lists:filter(fun(X) -> is_tuple(X) end, Opts),
    OptsLists  = case lists:filter(fun(X) -> is_list(X) end, Opts) of
                   [] -> [[]];
                   L  -> L
                 end,
    lists:map(fun(X) -> lists:ukeymerge(1, proplists:unfold(X), SharedOpts) end, OptsLists).

do(State) ->
    rebar_api:info("Running erlydtl...", []),
    Apps = case rebar_state:current_app(State) of
               undefined ->
                   rebar_state:project_apps(State);
               AppInfo ->
                   [AppInfo]
           end,
    [begin
         Opts = rebar_app_info:opts(AppInfo),
         Dir = rebar_app_info:dir(AppInfo),
         OutDir = rebar_app_info:ebin_dir(AppInfo),

         DtlOpts1 = proplists:unfold(rebar_opts:get(Opts, erlydtl_opts, [])),
         lists:foreach(fun(DtlOpts) ->
             TemplateDir = filename:join(Dir, option(doc_root, DtlOpts)),
             DtlOpts2 = [{doc_root, TemplateDir} | proplists:delete(doc_root, DtlOpts)],
             TagDir = filename:join(Dir, option(custom_tags_dir, DtlOpts2)),
             DtlOpts3 = [{custom_tags_dir, TagDir} | proplists:delete(custom_tags_dir, DtlOpts2)],
             filelib:ensure_dir(filename:join(OutDir, "dummy.beam")),

             rebar_base_compiler:run(Opts,
                                     [],
                                     TemplateDir,
                                     option(source_ext, DtlOpts3),
                                     OutDir,
                                     option(module_ext, DtlOpts3) ++ ".beam",
                                     fun(S, T, C) ->
                                             compile_dtl(C, S, T, DtlOpts3, Dir, OutDir)
                                     end,
                                     [{check_last_mod, false},
                                      {recursive, option(recursive, DtlOpts3)}])
          end, expand_opts(DtlOpts1))
     end || AppInfo <- Apps],

    {ok, State}.

-spec format_error(any()) ->  iolist().
format_error(Reason) ->
    io_lib:format("~p", [Reason]).

%% ===================================================================
%% Internal functions
%% ===================================================================

option(Opt, DtlOpts) ->
    proplists:get_value(Opt, DtlOpts, default(Opt)).

default(app) -> undefined;
default(doc_root) -> "priv/templates";
default(source_ext) -> ".dtl";
default(module_ext) -> "_dtl";
default(custom_tags_dir) -> "";
default(compiler_options) -> [debug_info, return];
default(recursive) -> true.

compile_dtl(_, Source, Target, DtlOpts, Dir, OutDir) ->
    case needs_compile(Source, Target, DtlOpts) of
        true ->
            do_compile(Source, Target, DtlOpts, Dir, OutDir);
        false ->
            skipped
    end.

do_compile(Source, Target, DtlOpts, Dir, OutDir) ->
    CompilerOptions = option(compiler_options, DtlOpts),

    Sorted = proplists:unfold(
               lists:sort(
                 [{out_dir, OutDir},
                  {doc_root, filename:join(Dir, option(doc_root, DtlOpts))},
                  {custom_tags_dir, option(custom_tags_dir, DtlOpts)},
                  {compiler_options, CompilerOptions}])),

    %% ensure that doc_root and out_dir are defined,
    %% using defaults if necessary
    Opts = lists:ukeymerge(1, DtlOpts, Sorted),
    rebar_api:debug("Compiling \"~s\" -> \"~s\" with options:~n    ~s",
                    [Source, Target, io_lib:format("~p", [Opts])]),
    case erlydtl:compile_file(ec_cnv:to_list(Source),
                              list_to_atom(module_name(Target)),
                              Opts) of
        {ok, _Mod} ->
            ok;
        {ok, _Mod, Ws} ->
            rebar_base_compiler:ok_tuple(Source, Ws);
        error ->
            rebar_base_compiler:error_tuple(Source, [], [], Opts);
        {error, Es, Ws} ->
            rebar_base_compiler:error_tuple(Source, Es, Ws, Opts)
    end.

module_name(Target) ->
    filename:rootname(filename:basename(Target), ".beam").

needs_compile(Source, Target, DtlOpts) ->
    LM = filelib:last_modified(Target),
    LM < filelib:last_modified(Source) orelse
        lists:any(fun(D) -> LM < filelib:last_modified(D) end,
                  referenced_dtls(Source, DtlOpts)).

referenced_dtls(Source, DtlOpts) ->
    DtlOpts1 = lists:keyreplace(doc_root, 1, DtlOpts,
        {doc_root, filename:dirname(Source)}),
    Set = referenced_dtls1([Source], DtlOpts1,
                           sets:add_element(Source, sets:new())),
    sets:to_list(sets:del_element(Source, Set)).

referenced_dtls1(Step, DtlOpts, Seen) ->
    ExtMatch = re:replace(option(source_ext, DtlOpts), "\.", "\\\\\\\\.",
                          [{return, list}]),

    ShOpts = [{use_stdout, false}, return_on_error],
    AllRefs =
        lists:append(
          [begin
               Cmd = lists:flatten(["grep -o [^\\\"]*\\",
                                    ExtMatch, "[^\\\"]* ", F]),
               case rebar_utils:sh(Cmd, ShOpts) of
                   {ok, Res} ->
                       string:tokens(Res, "\n");
                   {error, _} ->
                       ""
               end
           end || F <- Step]),
    DocRoot = option(doc_root, DtlOpts),
    WithPaths = [ filename:join([DocRoot, F]) || F <- AllRefs ],
    rebar_api:debug("All deps: ~p\n", [WithPaths]),
    Existing = [F || F <- WithPaths, filelib:is_regular(F)],
    New = sets:subtract(sets:from_list(Existing), Seen),
    case sets:size(New) of
        0 -> Seen;
        _ -> referenced_dtls1(sets:to_list(New), DtlOpts,
                              sets:union(New, Seen))
    end.
