module examples.variadic;

import std.stdio;
import std.conv;
import cmdline;

version (CMDLINE_CLASSIC) {
    void main(in string[] argv) {
        program
            .name("variadic")
            .description("test the variadic option")
            .option!int("-r, --required <values...>", "")
            .option!(string[])("-o, --optional [values...]", "");

        program.parse(argv);

        OptsWrap opts = program.getOpts();
        auto raw_required = opts("required");
        auto raw_optional = opts("optional");

        string required = raw_required.isValid ?
            raw_required.get!(int[])
                .to!string : "no required";

        string optional = raw_optional.isValid ?
            raw_optional.verifyType!bool ? true.to!string : raw_optional.get!(string[])
                .to!string : "no optional";

        writefln("required: %s", required);
        writefln("optional: %s", optional);
    }
}
else {
    struct VariadicResult {
        mixin BEGIN;
        mixin DESC!"test the variadic option";
        mixin DEF_VAR_OPT!(
            "required", int, "-r <values...>"
        );
        mixin DEF_VAR_OPT!(
            "optional", string, "-o [values...]"
        );
        mixin END;

        void action() {
            string required_ = required ? required.get.to!string : "no required";
            string optional_ = optional ? optional.isBool ? optional.getBool.to!string
                : optional.get.to!string : "no optional";
            writefln("required: %s", required_);
            writefln("optional: %s", optional_);
        }
    }
    mixin CMDLINE_MAIN!VariadicResult;
}
