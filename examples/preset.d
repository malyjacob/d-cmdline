module examples.preset;

import std.stdio;

import cmdline;

version (CMDLINE_CLASSIC) {
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
        writefln("--pre [%s], from <%s>", pre_info, program.getOptionValSource("pre"));
    }
}
else {
    struct PresetResult {
        mixin BEGIN;
        mixin HELP_TEXT_BEFORE!`
    Try the following:
        $ preset
        $ preset --pre
        $ preset -prdmd
        `;
        mixin DEF_OPT!(
            "pre", string, "-p [name]",
            Default_d!"dmd", Preset_d!"dub"
        );
        mixin END;

        void action() {
            auto cmd = getInnerCmd(this);
            writefln("--pre [%s], from <%s>", pre.get, cmd.getOptionValSource("pre"));
        }
    }
    mixin CMDLINE_MAIN!PresetResult;
}
