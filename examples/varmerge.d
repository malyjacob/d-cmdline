module examples.varmerge;

import cmdline;
import std.stdio;
import std.conv;
import std.process;

void main(in string[] argv) {
    program
        .name("varmerge")
        .description("test the variadic merge feature")
        .setVersion("1.1.0")
        .setConfigOption
        .option!(int[])("-n, --nums <ns...>", "", [12, 13, 14]);

    Option iopt = createOption("-f, --flag");
    iopt.implies("strs", ["ninja", "scons"]);

    Option xopt = createOption!string("-s, --strs [ss...]");
    xopt.preset(["xmake"]);
    xopt.defaultVal("make", "cmake");

    environment["CONFIG_" ~ "VARMERGE"] = "meson;ms-build;waf";
    xopt.env("CONFIG_" ~ "VARMERGE");

    program
        .addOption(iopt)
        .addOption(xopt);

    program.argToOpt("-s");

    program.addHelpText(AddHelpPos.After, `
Try to run:
    $ varmerge --flag -n99 -n59 -s maly jacob -- arg to opt
    `);
    
    program.action((opts) {
        auto nresult = opts("nums").get!(int[]);
        auto sresult = opts("strs").get!(string[]);
        auto fresult = opts("flag");
        writefln("nums:\t%s", nresult.to!string);
        writefln("strs:\t%s", sresult.to!string);
        writefln("--flag:\t%s", fresult.isValid ? fresult.get!bool.to!string : "unset");
    });

    program.parse(argv);
}
