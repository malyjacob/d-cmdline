module examples.defaultval;

import std.stdio;
import cmdline;

version (CMDLINE_CLASSIC) {
    void main(in string[] argv) {
        program
            .name("defaultval")
            .option(
                "-c, --cheese <type>",
                "Add the specified type of cheese",
                "blue" // default value, autodetect the option value type is `string`
            );

        Option sauce_opt = createOption!string("-s, --sauce <intig>");
        sauce_opt.description("Add the specified type of sauce");
        sauce_opt.defaultVal("pepper");

        program.addOption(sauce_opt);

        program.parse(argv);

        auto opts = program.getOpts();
        string cheese = opts("cheese").get!string;
        string sauce = opts("sauce").get!string;
        writefln("You ordered apizza with %s and %s cheese", sauce, cheese);
    }
}
else {
    struct DefaultvalResult {
        mixin BEGIN;

        mixin DEF_OPT!(
            "cheese", string, "-c <type>",
            Desc_d!"Add the specified type of cheese",
            Default_d!"blue"
        );

        mixin DEF_OPT!(
            "sauce", string, "-s <intig>",
            Desc_d!"Add the specified type of sauce",
            Default_d!"pepper"
        );

        mixin END;

        void action() {
            string cheese_ = cheese.get;
            string sauce_ = sauce.get;
            writefln("You ordered apizza with %s and %s cheese", sauce_, cheese_);
        }
    }

    mixin CMDLINE_MAIN!DefaultvalResult;
}
