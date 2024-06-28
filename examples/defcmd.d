module examples.defcmd;

import std.stdio;
import cmdline;

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
        .action((opts) { writefln("serve on port %4d", opts("port").get!int); });

    program.addHelpText(AddHelpPos.Before, `
Try the following:
    $ defcmd build
    $ defcmd serve -p 1234
    $ defcmd
    $ defcmd -p 2345
    `);

    program.parse(argv);
}
