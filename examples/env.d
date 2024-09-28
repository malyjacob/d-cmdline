module examples.env;

import std.stdio;
import std.conv;
import std.process;
import cmdline;

version (CMDLINE_CLASSIC) {
    void main(in string[] argv) {
        environment["BAR"] = "env";

        program.name("env");

        Option env_opt = createOption!string("-f, --foo <required-arg>");
        env_opt.env("BAR");

        program.addOption(env_opt);
        program.addHelpText(AddHelpPos.Before, `
    Try the following:
        $ env
        $ env -fxx
        `);

        program.parse(argv);

        OptsWrap opts = program.getOpts;
        string foo = opts("foo").get!string;
        auto src = program.getOptionValSource("foo");
        writefln("-f, --foo <%s>, from %s", foo, src.to!string);
    }
}
else {
    struct EnvResult {
        mixin BEGIN;
        mixin HELP_TEXT_BEFORE!`
    Try the following:
        $ env
        $ env -fxx
        `;
        mixin DEF_OPT!(
            "foo", string, "-f <required-arg>", Env_d!"BAR"
        );
        mixin END;

        void action() {
            string foo_ = foo.get;
            auto src = this.getInnerCmd.getOptionValSource("foo");
            writefln("-f, --foo <%s>, from %s", foo_, src.to!string);
        }
    }

    void main(in string[] argv) {
        environment["BAR"] = "env";
        argv.run!EnvResult;
    }
}