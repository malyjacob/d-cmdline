module examples.cstruct;
import cmdline;

import std.stdio;

struct SubResult {
    mixin DESC!("this is sub command");
    mixin ALIAS!("sb");
    OptVal!(bool, "-f") subFlag;
    mixin DESC!(subFlag, "Sub:\tsub flag desc");
    mixin NEGATE!(subFlag, "-S", "without sub flag");
}

struct ExtResult {
    mixin DESC!("this is ext command");
    mixin ALIAS!("ex");

    ArgVal!(string, true) arg;
    mixin DESC!(arg, "the arg operand");
    mixin CHOICES!(arg, "a", "b", "c", "d");
    mixin DEFAULT!(arg, "a");
}

struct MainResult {
    mixin BEGIN;
    mixin DESC!("this is main command");
    mixin VERSION!("1.0.1");

    SubResult* sub;
    ExtResult* ext;

    // mixin DEFAULT!(sub);

    OptVal!(int, "-i [num]") intNum;
    mixin DESC!(intNum, "Main:\tint num desc");
    mixin PRESET!(intNum, 12);
    mixin DEFAULT!(intNum, 23);

    ArgVal!(int, true) first;
    ArgVal!(int, true) second;
    ArgVal!(string, true) str;

    mixin RANGE!(first, 0, 1024);
    mixin RANGE!(second, 0, 1024);
    mixin DEFAULT!(first, 12);
    mixin DEFAULT!(second, 13);
    mixin DESC!(first, "the first operand");
    mixin DESC!(second, "the second operand");
    mixin DESC!(str, "Main:\tstring str desc");
    mixin DEFAULT!(str, "default");

    mixin OPT_TO_ARG!(intNum);
    mixin END;
}

mixin template INSERT() {
    enum bool __SPECIAL__ = true;
    alias __SELF__ = __traits(parent, __SPECIAL__);
    static assert(is(typeof(__SELF__.stint) == int));
}

mixin template EINSERT() {
    static assert(is(__SELF__));
}

struct Ax {
    enum bool AXY = true;
    static int stint = 12;
    mixin INSERT;
    mixin EINSERT;
}

void main(in string[] argv) {
    static assert(is(Ax.__SELF__ == Ax));

    MainResult output = parse!(MainResult)(argv);

    auto inum = output.intNum.get;
    auto str = output.str.get;
    auto first = output.first.get;
    auto second = output.second.get;
    writeln(MainResult.stringof);
    writeln("\t", inum.stringof, ":\t", inum);
    writeln("\t", str.stringof, ":\t", str);
    writeln("\t", first.stringof, ":\t", first);
    writeln("\t", second.stringof, ":\t", second);

    if (output.ready!SubResult) {
        const(SubResult)* sub_output = output.subResult!SubResult;
        auto subFlag = sub_output.subFlag.get;
        writeln(SubResult.stringof);
        writeln("\t", subFlag.stringof, ":\t", subFlag);
    }
    if (output.ready!ExtResult) {
        const(ExtResult)* ext_output = output.subResult!ExtResult;
        auto arg = ext_output.arg.get;
        writeln(ExtResult.stringof);
        writeln("\t", arg.stringof, ":\t", arg);
    }
}
