module examples.env;

import std.stdio;
import std.conv;
import std.process;

import cmdline;

void main(in string[] argv) {
    environment["BAR"] = "env";

    program.name("env");

    Option env_opt = createOption!string("-f, --foo <required-arg>");
    env_opt.env("BAR");

    program.addOption(env_opt);
    program.addHelpText(AddHelpPos.Before, `
Try the following:
    $ env
    $ env -fxx
    `);

    program.parse(argv);

    OptsWrap opts = program.getOpts;
    string foo = opts("foo").get!string;
    auto src = program.getOptionValSource("foo");
    writefln("-f, --foo <%s>, from %s", foo, src.to!string);
}