module examples.calc;

import cmdline;
import std.stdio;

void main(in string[] argv) {
    program.name("calc");
    program.description("simple calculator for baisc binary computation");
    program.aliasName("cal");
    program.setVersion("1.0.1");

    Argument arg_first = createArgument!double("first");
    Argument arg_second = createArgument!double("second");
    arg_first.rangeOf(0.0, 1024.0);
    arg_second.rangeOf(0.0, 1024.0);
    program.addArgument(arg_first);
    program.addArgument(arg_second);
    program.argumentDesc([
        "first": "the first operand",
        "second": "the second operaand"
    ]);
    program.addHelpText(AddHelpPos.After, `
Examples:
    $ calc 12 13
    $ calc 23 45 -o
    $ calc 23.3 45 -o -
    $ calc 23.3 27.3 -o /
    $ calc -o 23.3 45
    $ calc -o * 23.3 45
    `);
    Option op_opt = createOption!string("-o, --operator [op]", "the operator of two double number");
    op_opt.choices("+", "-", "*", "/");
    op_opt.preset("*");
    op_opt.defaultVal("+");
    program.addOption(op_opt);

    program.action((opts, _first, _second) {
        double first = cast(double) _first;
        double second = cast(double) _second;
        string op = opts("operator").get!string;
        switch (op) {
        case "+":
            writefln("%4.4f %s %4.4f = %4.4f", first, op, second, first + second);
            break;
        case "-":
            writefln("%4.4f %s %4.4f = %4.4f", first, op, second, first - second);
            break;
        case "*":
            writefln("%4.4f %s %4.4f = %4.4f", first, op, second, first * second);
            break;
        default:
            writefln("%4.4f %s %4.4f = %4.4f", first, op, second, first / second);
            break;
        }
    });

    program.parse(argv);
}
