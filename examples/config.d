module examples.config;

import std.stdio;

import cmdline;

version (CMDLINE_CLASSIC) {
    void main(in string[] argv) {
        program
            .name("config")
            .description("test the feature  of config option")
            .setConfigOption
            .showGlobalOptions
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
}

else {
    struct ConfigResult {
        mixin BEGIN;
        mixin DESC!"test the feature  of config option";
        mixin CONFIG;
        mixin SHOW_GLOBAL_OPTS;

        mixin SUB_CMD!(SubResult);

        mixin DEF_ARG!(
            "first", int, Desc_d!"the first num",
            Default_d!65
        );

        mixin DEF_ARG!(
            "second", int, Desc_d!"the second num",
            Default_d!35
        );

        mixin DEF_OPT!(
            "multi", int, "-m <num>",
            Desc_d!"the multi num", Default_d!12
        );

        mixin DEF_BOOL_OPT!(
            "negate", "-N", Desc_d!"decide to negate"
        );

        mixin END;

        void action() {
            int first_ = first.get;
            int second_ = second.get;
            int multi_ = multi.get;
            bool is_negate = negate;
            multi_ = is_negate ? -multi_ : multi_;
            writefln("%d * (%d + %d) = %d", multi_, first_, second_,
                multi_ * (first_ + second_));
        }
    }

    struct SubResult {
        mixin BEGIN;
        mixin DESC!"sub the two nums";

        mixin DEF_OPT!(
            "first", int, "-f <int>",
            Desc_d!"the first num",
            Default_d!65
        );

        mixin DEF_OPT!(
            "second", int, "-s <int>",
            Desc_d!"the second num",
            Default_d!35
        );

        mixin END;

        void action() {
            int first_ = first.get;
            int second_ = second.get;
            writefln("sub:\t%d - %d = %d", first_, second_, first_ - second_);
        }
    }

    mixin CMDLINE_MAIN!ConfigResult;
}
