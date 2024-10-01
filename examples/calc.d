module examples.calc;
import cmdline;
import std.stdio;

version (CMDLINE_CLASSIC) {
    void main(in string[] argv) {
        program
            .name("calc")
            .setVersion("1.0.1")
            .showHelpAfterError
            .allowExcessArguments(false);

        Option operator_opt = createOption!string("--operator, -o [op]", "the operator of two double number");
        operator_opt
            .choices("add", "sub", "multi", "div")
            .preset("multi")
            .defaultVal("add");

        Option first_opt = createOption!double("--first, -f <fnum>", "the first operand");
        first_opt
            .rangeOf(0.0, 1024.0)
            .defaultVal(0.0);

        Option second_opt = createOption!double("--second, -s <fnum>", "the second operand");
        second_opt
            .rangeOf(0.0, 1024.0)
            .defaultVal(0.0);

        Option info_opt = createOption!string("--info, -i [info-str]", "the action option to info");

        program.addOptions(operator_opt, first_opt, second_opt);

        program.addActionOption(info_opt,
            (string[] vals...) {
            writefln("invoked info: `%s`", vals.length ? vals[0] : "");
        });

        program.argToOpt("operator", "first", "second");

        program.action((in OptsWrap opts) {
            string op = opts("operator").get!string;
            double f = opts("first").get!double;
            double s = opts("second").get!double;
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
        });

        program.parse(argv);
    }
}
else {
    @cmdline struct Calc {
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

        mixin DEF_OPT!(
            "info", string, "-i [info-str]",
            Desc_d!"the action option to info",
            Action_d!((string[] vals...) {
                writefln("invoked info: `%s`", vals.length ? vals[0] : "");
            })
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

    mixin CMDLINE_MAIN!Calc;
}
