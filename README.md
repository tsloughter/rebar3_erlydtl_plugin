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
        {rebar3_erlydtl_plugin, ".*", {git, "https://github.com/tsloughter/rebar3_erlydtl_plugin.git", {branch, "master"}}}
    ]}.

Then just call your plugin directly in an existing application:


    $ rebar3 erlydtl compile
    ===> Fetching rebar3_erlydtl_plugin
    ===> Compiling rebar3_erlydtl_plugin

To have it invoked automatically when running `rebar3 compile` add it as a `provider_hooks`:

```
{provider_hooks, [
                 {pre, [{compile, {erlydtl, compile}}]}
                 ]}.
```

Any templates in 'priv/templates' will then be compiled, by default, but this location is configurable.
