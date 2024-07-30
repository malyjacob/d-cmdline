module examples.strutil;

import std.stdio;
import std.string;
import cmdline;

mixin template ConfigCmd() {
    mixin DESC!("CLI to some string utilities");
    mixin VERSION!("0.0.1");

    JoinResult* joinSub;
    SplitResult* splitSub;
}

mixin template ConfigSplitCmd() {
    mixin BEGIN;
    mixin DESC!("Split a string into substrings and display as an array.");

    ArgVal!string str;
    mixin DESC!(str, "string to split");

    OptVal!(string, "-s <char>") separator;
    mixin DESC!(separator, "separator character");
    mixin DEFAULT!(separator, ",");

    mixin OPT_TO_ARG!(separator);

    static void action(string sp, string s) {
        writeln(split(s, sp));
    }

    mixin END;
}

mixin template ConfigJoinCmd() {
    mixin BEGIN;
    mixin DESC!("Join the command-arguments into a single string.");

    ArgVal!(string[]) strs;
    mixin DESC!(strs, "one or more string");

    OptVal!(string, "-s <char>") separator;
    mixin DESC!(separator, "separator character");
    mixin DEFAULT!(separator, ",");

    static void action(string sp, string[] ss) {
        writeln(ss.join(sp));
    }

    mixin END;
}

struct SplitResult {
    mixin ConfigSplitCmd;
}

struct JoinResult {
    mixin ConfigJoinCmd;
}

struct StrUtilResult {
    mixin ConfigCmd;
}

void main(in string[] argv) {
    StrUtilResult output = parse!StrUtilResult(argv);
    if (auto jr = output.subResult!JoinResult) {
        jr.action(jr.separator.get, jr.strs.get);
    }
    else if (auto spl = output.subResult!SplitResult) {
        spl.action(spl.separator.get, spl.str.get);
    }
}
