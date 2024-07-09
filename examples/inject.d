module examples.inject;
import cmdline;

import std.stdio;
import std.conv;

void main(in string[] argv) {
    program.name("inject");
    program.allowExposeOptionValue(true);
    program.setVersion("1.1.0");
    program
        .option("--global-bool", "", false)
        .option("--global-int <num>", "", 13)
        .option("--global-variadic <nums...>", "", [1, 2, 3, 4])
        .provides("global-bool")
        .providesAs(["global-int": "gint", "global-variadic": "gvar"])
        .argToOpt("global-bool", "global-int")
        .action(() { writefln("call main program:%s", program.name); });

    auto sub_cmd = program.command("sub");

    sub_cmd
        .option("--sub-bool", "", true)
        .option("--sub-int <num>", "", 34)
        .injects("global-bool", "gint")
        .injectsAs("gvar", "svar")
        .action((opts) {
            bool sbool = opts("sub-bool").get!bool;
            bool gbool = opts("global-bool").get!bool;
            int sint = opts("sub-int").get!int;
            int gint = opts("gint").get!int;
            int[] svar = opts("svar").get!(int[]);

            writefln("sbool: %s, gbool: %s, sint: %d, gint: %d, svar: %s", sbool, gbool, sint, gint, svar
                .to!string);
            writefln("%s\t%s", "global-variadic", opts(":global-variadic").get!(int[])
                .to!string);
        });

    program.parse(argv);
}
