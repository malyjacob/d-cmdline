module examples.config;

import std.stdio;

import cmdline;

void main(in string[] argv) {

    program
        .name("config")
        .description("test the feature  of config option")
        .setConfigOption
        .arguments!(int, int)("<first> <second>")
        .argumentDesc("first", "the  first num")
        .argumentDesc("second", "the  second num")
        .option("-m|--multi <num>", "the multi num", 12)
        .option("-N, --negate", "decide to negate", false)
        .action((opts, fst, snd) {
            int first = fst.get!int;
            int second = snd.get!int;
            int multi = opts("multi").get!int;
            bool negate = opts("negate").get!bool;
            multi = negate ? -multi : multi;
            writefln("%d * (%d + %d) = %d", multi, first, second,
                multi * (first + second));
        });

    auto farg = program.findArgument("first");
    auto sarg = program.findArgument("second");
    farg.defaultVal(65);
    sarg.defaultVal(35);

    program
        .command("sub")
        .description("sub the two numbers")
        .option("-f, --first <int>", "", 65)
        .option("-s, --second <int>", "", 35)
        .action((opts) {
            int first = opts("first").get!int;
            int second = opts("second").get!int;
            writefln("sub:\t%d - %d = %d", first, second, first - second);
        });

    program.parse(argv);
}
