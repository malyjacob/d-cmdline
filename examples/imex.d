module examples.imex;

import std.stdio;
import std.format;
import std.conv;
import std.algorithm;
import std.array;
import cmdline;

version(CMDLINE_CLASSIC) {

}
else {
    @cmdline struct Imex {
        mixin BEGIN;
        mixin DESC!"test import, export and passthrough";
        mixin VERSION!("0.0.1", "--version -v");

        mixin SORT_OPTS;
        mixin SORT_SUB_CMDS;
        mixin PASS_THROUGH;

        mixin SUB_CMD!Sub;

        mixin DEF_OPT!(
            "bar", int, "-r [int]", Desc_d!"the optional value flag in parent command",
            Default_d!0, Negate_d!("-B"), Preset_d!50, ToArg_d
        );

        mixin DEF_BOOL_OPT!(
            "foo", "-f", Desc_d!"the bool flag in parent command",
            Implies_d!("bar", -1), Negate_d!("-F")
        );

        mixin DEF_BOOL_OPT!(
            "goo", "-g", Desc_d!"confilicts with `--foo`",
            Conflicts_d!("foo"),
            Negate_d!("-G"),
            Implies_d!("bar", 1)
        );

        mixin DEF_BOOL_OPT!(
            "qua", "-q", Desc_d!"test new feature of imply and conflict when option is bool",
            Conflicts_d!("foo", "goo"),
            Negate_d!("-Q", "the negate of option `--qua -q`"),
            Implies_d!("bar", 100)
        );

        mixin END;

        void action() {
            auto foo_info = format("`foo` value is `%4s`", foo.get);
            auto goo_info = format("`goo` value is `%4s`", goo.get);
            auto bar_info = format("`bar` value is `%4d`", bar.get);
            auto qua_info = format("`qua` value is `%4s`", qua.get);
            writefln("In Command `%s`:", "imex");
            writefln("\t%s", foo_info);
            writefln("\t%s", goo_info);
            writefln("\t%s", bar_info);
            writefln("\t%s", qua_info);
        }
    }

    @cmdline struct Sub {
        mixin BEGIN;
        mixin DESC!"the sub command for test import, export and passthrough";
        
        mixin IMPORT!("foo", "--fuu");
        mixin IMPORT!("bar", "--brr", "--baa");
        mixin IMPORT!("goo", "--guu");
        mixin IMPORT!("qua", "--qaa");

        mixin DEF_VAR_OPT!(
            "baz", int, "-z [ints...]", Desc_d!"the optional variadic flag in sub command",
            DisableMerge_d, ToArg_d, Default_d!([0]), Preset_d!([1, 2, 3]), Negate_d!"-Z"
        );

        mixin END;

        void action() {
            Imex *parent = this.getParent!Imex;
            auto baz_info = format("`baz` value is `%s`", baz.get.to!string);
            parent.action;
            writefln("In Command `%s`:", "sub");
            writefln("\t%s", baz_info);
        }
    }

    mixin CMDLINE_MAIN!Imex;
}