module examples.defcmd;

import std.stdio;
import cmdline;

version (CMDLINE_CLASSIC) {
    void main(in string[] argv) {
        program.name("defcmd");
        program.setConfigOption();

        program
            .command("build")
            .description("build web site for deployment")
            .action(() { writeln("build"); });

        program
            .command("deploy")
            .description("deploy web site to production")
            .action(() { writeln("deploy"); });

        program
            .command("serve", ["isDefault": true])
            .description("launch web serve")
            .option("-p, --port <port-num>", "web port", 8080)
            .action((opts) {
                writefln("serve on port %4d", opts("port").get!int);
            });

        program.addHelpText(AddHelpPos.Before, `
    Try the following:
        $ defcmd build
        $ defcmd serve -p 1234
        $ defcmd
        $ defcmd -p 2345
        `);

        program.parse(argv);
    }
}
else {
    struct DefcmdResult {
        mixin BEGIN;
        mixin CONFIG;
        mixin SUB_CMD!(BuildResult, DeployResult, ServeResult);
        mixin DEFAULT!ServeResult;
        mixin HELP_TEXT_BEFORE!(`
    Try the following:
        $ defcmd build
        $ defcmd serve -p 1234
        $ defcmd
        $ defcmd -p 2345
        `);
        mixin END;
    }

    struct BuildResult {
        mixin DESC!"build web site for deployment";
        void action() {
            writeln("build");
        }
    }

    struct DeployResult {
        mixin DESC!"launch web site to production";
        void action() {
            writeln("deploy");
        }
    }

    struct ServeResult {
        mixin DESC!"launch web serve";
        mixin DEF_OPT!(
            "port", int, "-p <port-num>", Desc_d!"web port", Default_d!8080
        );
        void action() {
            writefln("serve on port %4d", port.get);
        }
    }

    mixin CMDLINE_MAIN!DefcmdResult;
}
