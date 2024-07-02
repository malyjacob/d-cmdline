module examples.variadic;

import std.stdio;
import std.conv;
import cmdline : program, OptsWrap;


void main(in string[] argv) {
    program
        .name("variadic")
        .description("test the variadic option")
        .option!int("-r, --required <values...>", "")
        .option!(int[])("-o, --optional [values...]", "");
    
    program.parse(argv);
    
    OptsWrap opts = program.getOpts();
    auto raw_required = opts("required");
    auto raw_optional = opts("optional");

    string required = raw_required.isValid ?
            raw_required.get!(int[]).to!string : "no required";

    string optional = raw_optional.isValid ?
            raw_optional.verifyType!bool ? true.to!string
            : raw_optional.get!(int[]).to!string : "no optional";

    writefln("required: %s", required);
    writefln("optional: %s", optional);
}

