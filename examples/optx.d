module examples.optx;

import std.stdio;
import std.conv;
import cmdline;

version (CMDLINE_CLASSIC) {
    void main(in string[] argv) {
        program
            .name("optx")
            .description("test the value trait of options");

        auto range_opt = createOption!int("-r, --rgnum <num>");
        range_opt.rangeOf(0, 9);
        range_opt.defaultVal(0);
        range_opt.parser!((string s) => s.to!int);
        range_opt.processor!((int v) => cast(int) v + 1);

        auto choice_opt = createOption!string("-c, --chstr <str>");
        choice_opt.choices("a", "b", "c", "d", "e", "f", "g", "h");
        choice_opt.defaultVal("a");
        choice_opt.processor!((string v) => v ~ "+");

        auto reduce_opt = createOption!int("-n, --nums <numbers...>");
        reduce_opt.defaultVal(12, 13, 14);
        reduce_opt.processReducer!((int a, int b) => a + b);

        program
            .addOption(range_opt)
            .addOption(choice_opt)
            .addOption(reduce_opt);

        program.argToOpt("-c", "-n");

        program.parse(argv);

        int range_int = program.getOptVal!int("-r");
        string choice_str = program.getOptVal!string("-c");
        int reduce_int = program.getOptVal!int("nums");

        writefln("%d, %s, %d", range_int, choice_str, reduce_int);
    }
}
else  {
    @cmdline struct Optx {
        mixin BEGIN;
        mixin DESC!"test the value trait of options";

        mixin DEF_OPT!(
            "rgnum", int, "-r <num>",
            Range_d!(0, 9), Default_d!0,
            Parser_d!((string s) => s.to!int),
            Processor_d!((int v) => cast(int) v + 1)
        );

        mixin DEF_OPT!(
            "chstr", string, "-c <str>",
            Choices_d!("a", "b", "c", "d", "e", "f", "g", "h"),
            Default_d!"a",
            Processor_d!((string v) => v ~ "+"),
            ToArg_d
        );

        mixin DEF_VAR_OPT!(
            "nums", int, "-n <numbers...>",
            Default_d!([12, 13, 14]),
            Reducer_d!((int a, int b) => a + b),
            ToArg_d
        );

        // mixin PARSER!(rgnum, (string s) => s.to!int);
        // mixin PROCESSOR!(rgnum, (int v) => cast(int) v + 1);
        // mixin PROCESSOR!(chstr, (string v) => v ~ "+");
        // mixin REDUCER!(nums, (int a, int b) => a + b);

        mixin END;

        void action() {
            int rgnum_ = rgnum.get;
            string chstr_ = chstr.get;
            int rdnum_ = nums.get!int;
            writefln("%d, %s, %d", rgnum_, chstr_, rdnum_);
        }
    }

    mixin CMDLINE_MAIN!Optx;
}
