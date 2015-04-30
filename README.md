rebar3_erlydtl_plugin
=====

A rebar plugin

Build
-----

    $ rebar3 compile

Use
---

Add the plugin to your rebar config:

    {plugins, [
        {rebar3_erlydtl_plugin, ".*", {git, "git://github.com:tsloughter/rebar3_erlydtl_plugin.git", {tag, "0.1.0"}}}
    ]}.

Then just call your plugin directly in an existing application:


    $ rebar3 erlydtl compile
    ===> Fetching rebar3_erlydtl_plugin
    ===> Compiling rebar3_erlydtl_plugin
