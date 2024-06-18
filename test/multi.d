module multi;

import cmdline;
import std.stdio;
import std.format;

void main(string[] argv) {
    Command program = createCommand("program");
    program.setVersion("0.0.1");
    program.allowExcessArguments(false);
    program.option("-f, --first <num>", "test", 13);
    program.option("-s, --second <num>", "test", 12);
    program.argument("[multi]", "乘数", 4);
    program.action((args, optMap) {
        auto fnum = optMap["first"].get!int;
        auto snum = optMap["second"].get!int;
        int multi = 1;
        if (args.length)
            multi = args[0].get!int;
        writeln(format("%4d * (%4d + %4d) = %4d", multi, fnum, snum, (fnum + snum) * multi));
    });
    program.parse(argv);
}
