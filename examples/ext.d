module examples.ext;
import cmdline;

import std.stdio;

version (CMDLINE_CLASSIC) {
    void main(in string[] argv) {
        program
            .name("ext")
            .description("test the `ext_sub_cmd`")
            .setVersion("0.0.1")
            .showHelpAfterError
            .sortSubCommands;

        program
            .command("greet", ["isDefault": true])
            .requiredOption!string("--talk, -t <str>", "the sentance to greet")
            .argToOpt("talk")
            .action((in OptsWrap opts) {
                string talk = opts("talk").get!string;
                writefln("greet:\t%s", talk);
            });
        program
            .commandX("calc", "external command `calc` as sub command", [
                "file": "calc"
        ])
            .commandX("cheese", "external command `cheese` as sub command", [
                "file": "cheese"
        ])
            .commandX("config", "external command `config` as sub command", [
                "file": "config"
        ])
            .commandX("defaultval", "external command `defaultval` as sub command", [
                "file": "defaultval"
        ])
            .commandX("defcmd", "external command `defcmd` as sub command", [
                "file": "defcmd"
        ])
            .commandX("deploy", "external command `deploy` as sub command", [
                "file": "deploy"
        ])
            .commandX("implies", "external command `implies` as sub command", [
                "file": "implies"
        ])
            .commandX("inject", "external command `inject` as sub command", [
                "file": "inject"
        ])
            .commandX("env", "external command `env` as sub command", [
                "file": "env"
        ])
            .commandX("tell", "external command `greet` as sub command", [
                "file": "greet"
        ])
            .commandX("jread", "external command `jread` as sub command", [
                "file": "jread"
        ])
            .commandX("optx", "external command `optx` as sub command", [
                "file": "optx"
        ])
            .commandX("preset", "external command `preset` as sub command", [
                "file": "preset"
        ])
            .commandX("variadic", "external command `variadic` as sub command", [
                "file": "variadic"
        ])
            .commandX("varmerge", "external command `varmerge` as sub command", [
                "file": "varmerge"
        ])
            .commandX("strutil", "external command `strutil` as sub command", [
                "file": "strutil"
        ]);

        program.parse(argv);
    }
}
else {
    struct ExtResult {
        mixin BEGIN;
        mixin DESC!("test the `ext_sub_cmd`");
        mixin VERSION!("0.0.1");

        mixin SHOW_HELP_AFTER_ERR;
        mixin SORT_SUB_CMDS;

        mixin SUB_CMD!(GreetResult);
        mixin DEFAULT!(GreetResult);

        mixin EXT_SUB_CMD!(
            "calc", "external command `calc` as sub command"
        );

        mixin EXT_SUB_CMD!(
            "cheese", "external command `cheese` as sub command"
        );

        mixin EXT_SUB_CMD!(
            "config", "external command `config` as sub command"
        );

        mixin EXT_SUB_CMD!(
            "defaultval", "external command `defaultval` as sub command"
        );

        mixin EXT_SUB_CMD!(
            "defcmd", "external command `defcmd` as sub command"
        );

        mixin EXT_SUB_CMD!(
            "deploy", "external command `deploy` as sub command"
        );

        mixin EXT_SUB_CMD!(
            "env", "external command `env` as sub command"
        );

        mixin EXT_SUB_CMD!(
            "tell", "external command `greet` as sub command", "greet"
        );

        mixin EXT_SUB_CMD!(
            "implies", "external command `implies` as sub command"
        );

        mixin EXT_SUB_CMD!(
            "inject", "external command `inject` as sub command"
        );

        mixin EXT_SUB_CMD!(
            "jread", "external command `jread` as sub command"
        );

        mixin EXT_SUB_CMD!(
            "optx", "external command `optx` as sub command"
        );

        mixin EXT_SUB_CMD!(
            "preset", "external command `preset` as sub command"
        );

        mixin EXT_SUB_CMD!(
            "variadic", "external command `variadic` as sub command"
        );

        mixin EXT_SUB_CMD!(
            "varmerge", "external command `varmerge` as sub command"
        );

        mixin EXT_SUB_CMD!(
            "strutil", "external command `strutil` as sub command",
        );

        mixin END;
    }

    struct GreetResult {
        mixin BEGIN;
        mixin DESC!("the sub cmd of `ext` to greet");

        mixin DEF_OPT!(
            "talk", string, "-t <str>",
            Desc_d!"the sentance to greet",
            Mandatory_d,
            ToArg_d
        );

        mixin END;

        void action() {
            writefln("greet:\t%s", talk.get);
        }
    }

    mixin CMDLINE_MAIN!ExtResult;
}
