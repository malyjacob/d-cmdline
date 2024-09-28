module examples.implies;

import std.stdio;
import std.format;
import std.conv;
import cmdline;

version (CMDLINE_CLASSIC) {
    void main(in string[] argv) {
        program.name("implies");
        program.option("--foo -f", "foo bool to be implied", false);
        program.option("--bar -r <num>", "bar for int implied", 0);
        
        Option baz_opt = createOption!(int[])("--baz -z <ints...>", "baz for int[] implied");
        baz_opt.merge(false).defaultVal([0]);
        Option qua_opt = createOption!(string[])("--qua -q [strs...]", "qua for string[] implied");
        qua_opt.defaultVal(["default"]).preset(["preset"]);
        
        auto imply_opt = createOption("--imply -i", "implier");
        imply_opt.implies(["foo"]);
        imply_opt.implies("qua", ["imply"]);
        imply_opt.implies("bar", 12);
        imply_opt.implies("baz", [1, 2, 3]);

        program.addOptions(baz_opt, qua_opt, imply_opt);

        program.action((in OptsWrap opts) {
            string foo_info = opts("foo").isValid
                ? format!"foo is (%s) from [%s]"(opts("foo").get!bool.to!string, program.getOptionValSource("foo"))
                : "foo is (false)";
            string imply_info = opts("imply").isValid 
                ? format!"imply is (%s) from [%s]"(true.stringof, program.getOptionValSource("imply"))
                : "imply is (false)";
            string bar_info = format!"bar is (%d) from [%s]"(opts("bar").get!int, program.getOptionValSource("bar")); 
            string baz_info = format("baz is (%s) from [%s]", opts("baz").get!(int[]).to!string, program.getOptionValSource("baz"));
            string qua_info = format("qua is (%s) from [%s]", opts("qua").get!(string[]).to!string, program.getOptionValSource("qua"));
            writeln(imply_info);
            writeln(foo_info);
            writeln(bar_info);
            writeln(baz_info);
            writeln(qua_info);
        });

        program.parse(argv);
    }
}
else {
    struct ImpliesResult {
        mixin BEGIN;
        mixin DEF_BOOL_OPT!(
            "foo", "-f", Desc_d!"foo bool to be implied", Default_d!false
        );
        mixin DEF_OPT!(
            "bar", int, "-r <num>", Desc_d!"bar for int implied", Default_d!0
        );
        mixin DEF_VAR_OPT!(
            "baz", int, "-z <ints...>", Desc_d!"baz for int[] implied", DisableMerge_d, Default_d!([0])
        );
        mixin DEF_VAR_OPT!(
            "qua", string, "-q [strs...]", Desc_d!"qua for string[] implied",
            Default_d!(["default"]), Preset_d!(["preset"]) 
        );
        mixin DEF_BOOL_OPT!(
            "imply", "-i", Desc_d!"implier",
            ImpliesTrue_d!("foo"),
            Implies_d!("qua", "imply"),
            Implies_d!("bar", 12),
            Implies_d!("baz", 1, 2, 3)
        );
        mixin END;

        void action() {
            const Command cmd = getInnerCmd(this);
            string foo_info = foo 
                ? format!"foo is (%s) from [%s]"(foo.get.to!string, cmd.getOptionValSource("foo"))
                : "foo is (false)";
            string imply_info = imply 
                ? format!"imply is (%s) from [%s]"(true.stringof, cmd.getOptionValSource("imply"))
                : "imply is (false)";
            string bar_info = format!"bar is (%d) from [%s]"(bar.get, cmd.getOptionValSource("bar")); 
            string baz_info = format("baz is (%s) from [%s]", baz.get.to!string, cmd.getOptionValSource("baz"));
            string qua_info = format("qua is (%s) from [%s]", qua.get.to!string, cmd.getOptionValSource("qua"));
            writeln(imply_info);
            writeln(foo_info);
            writeln(bar_info);
            writeln(baz_info);
            writeln(qua_info);
        }
    }

    mixin CMDLINE_MAIN!ImpliesResult;
}
