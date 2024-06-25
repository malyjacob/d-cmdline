module examples.str_util;

import std.stdio;
import std.string;
import cmdline;

void main(string[] argv) {
    program
        .name("str_util")
        .description("CLI to some string utilities")
        .setVersion("0.0.1");

    Command str_split = program.command("split");
    str_split.description("Split a string into substrings and display as an array.");
    str_split.argument!string("<str>", "string to split");
    str_split.option("-s, --seperator <char>", "separator character", ",");
    str_split.action((opts, _str) {
        string sp = opts("seperator").get!string;
        string str = _str.get!string;
        writeln(split(str, sp));
    });

    Command join = program.command("join");
    join.description("Join the command-arguments into a single string");
    join.argument!string("<strs...>", "one or more string");
    join.option("-s, --seperator <char>", "separator character", ",");
    join.action((in OptsWrap opts, in ArgWrap _strs) {
        string sp = opts("seperator").get!string;
        auto strs = _strs.get!(string[]);
        writeln(typeof(strs).stringof);
        writeln(strs.join(sp));
    });

    program.parse(argv);
}
