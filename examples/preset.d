module examples.preset;

import std.stdio;

import cmdline;

void main(in string[] argv) {
    program.name("preset");
    
    Option pre_opt = createOption!string("-p,--pre [name]");
    pre_opt.defaultVal("dmd");
    pre_opt.preset("dub");
    program.addOption(pre_opt);

    program.addHelpText(AddHelpPos.Before, `
Try the following:
    $ preset
    $ preset --pre
    $ preset -prdmd
    `);

    program.parse(argv);

    OptsWrap opts = program.getOpts;
    string pre_info = opts("pre").get!string;
    writefln("--pre [%s]", pre_info);
}