module examples.calc;

import cmdline;
import std.stdio;

// void main(in string[] argv) {
//     program.name("calc");
//     program.description("simple calculator for baisc binary computation");
//     program.aliasName("cal");
//     program.setVersion("1.0.1");

//     Argument arg_first = createArgument!double("first");
//     Argument arg_second = createArgument!double("second");
//     arg_first.rangeOf(0.0, 1024.0);
//     arg_second.rangeOf(0.0, 1024.0);
//     program.addArgument(arg_first);
//     program.addArgument(arg_second);
//     program.argumentDesc([
//         "first": "the first operand",
//         "second": "the second operaand"
//     ]);
//     program.addHelpText(AddHelpPos.After, `
// Examples:
//     $ calc 12 13
//     $ calc 23 45 -o
//     $ calc 23.3 45 -o -
//     $ calc 23.3 27.3 -o /
//     $ calc -o 23.3 45
//     $ calc -o * 23.3 45
//     `);
//     Option op_opt = createOption!string("-o, --operator [op]", "the operator of two double number");
//     op_opt.choices("+", "-", "*", "/");
//     op_opt.preset("*");
//     op_opt.defaultVal("+");
//     program.addOption(op_opt);

//     program.action((opts, _first, _second) {
//         double first = cast(double) _first;
//         double second = cast(double) _second;
//         string op = opts("operator").get!string;
//         switch (op) {
//         case "+":
//             writefln("%4.4f %s %4.4f = %4.4f", first, op, second, first + second);
//             break;
//         case "-":
//             writefln("%4.4f %s %4.4f = %4.4f", first, op, second, first - second);
//             break;
//         case "*":
//             writefln("%4.4f %s %4.4f = %4.4f", first, op, second, first * second);
//             break;
//         default:
//             writefln("%4.4f %s %4.4f = %4.4f", first, op, second, first / second);
//             break;
//         }
//     });

//     program.parse(argv);
// }

struct CalcResult {
    mixin BEGIN;
    mixin DESC!"simple calculator for baisc binary computation";
    mixin VERSION!"1.0.1";

    mixin SHOW_HELP_AFTER_ERR;
    mixin DISALLOW_EXCESS_ARGS;

    mixin DEF_OPT!(
        "operator", string, "-o [op]",
        Desc_d!"the operator of two double number",
        Choices_d!("add", "sub", "multi", "div"),
        Preset_d!"multi",
        Default_d!"add",
        ToArg_d,
    );

    mixin DEF_OPT!(
        "first", double, "-f <fnum>",
        Desc_d!"the first operand",
        Range_d!(0.0, 1024.0),
        Default_d!0.0,
        ToArg_d,
    );

    mixin DEF_OPT!(
        "second", double, "-s <snum>",
        Desc_d!"the second operand",
        Range_d!(0.0, 1024.0),
        Default_d!1.0,
        ToArg_d,
    );

    mixin END;

    void action() {
        auto f = first.get;
        auto s = second.get;
        auto op = operator.get;
        auto op_map = [
            "add": "+",
            "sub": "-",
            "multi": "*",
            "div": "/"
        ];
        switch (op) {
        case "add":
            writefln("%4.4f %s %4.4f = %4.4f", f, op_map[op], s, f + s);
            break;
        case "sub":
            writefln("%4.4f %s %4.4f = %4.4f", f, op_map[op], s, f - s);
            break;
        case "multi":
            writefln("%4.4f %s %4.4f = %4.4f", f, op_map[op], s, f * s);
            break;
        case "div":
            writefln("%4.4f %s %4.4f = %4.4f", f, op_map[op], s, f / s);
            break;
        default:
            break;
        }
    }
}

void main(in string[] argv) {
    argv.run!CalcResult;
}
