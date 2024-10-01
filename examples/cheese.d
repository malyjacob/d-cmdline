module examples.cheese;

import std.stdio;
import cmdline;

version (CMDLINE_CLASSIC) {
    void main(in string[] argv) {
        program.name("cheese");
        program.sortOptions();

        program.option("--no-sauce", "Remove sauce");
        program.option("--cheese <flavor>", "cheese flavor", "mozzarella");
        program.option("--no-cheese", "plain with no cheese");

        program.action((opts) {
            string sause_str = opts("sauce") ? "sauce" : "no sauce";
            string cheese_str = opts("cheese").isValid ?
                opts("cheese")
                    .get!string ~ " cheese" : "no cheese";
            writefln("You ordered apizza with %s and %s", sause_str, cheese_str);
        });

        program.addHelpText(AddHelpPos.Before, `
    Try the following:
        $ cheese
        $ cheese --sauce
        $ cheese --cheese=blue
        $ cheese --no-sauce --no-cheese
    `);

        program.parse(argv);
    }

}
else {
    @cmdline struct Cheese {
        mixin BEGIN;
        mixin SORT_OPTS;

        mixin HELP_TEXT_BEFORE!(`
    Try the following:
        $ cheese
        $ cheese --sauce
        $ cheese --cheese=blue
        $ cheese --no-sauce --no-cheese
        `);

        mixin DEF_OPT!(
            "cheese", string, "<flavor>",
            Desc_d!"cheese flavor",
            Default_d!("mozzarella"),
            Negate_d!("", "plain with no cheese")
        );

        mixin DEF_BOOL_OPT!(
            "sauce", "",
            Negate_d!("", "Remove sauce")
        );

        mixin END;

        void action() {
            string sause_str = sauce.get ? "sauce" : "no sauce";
            string cheese_str = cheese ? cheese.get[0] ~ " cheese" : "no cheese";
            writefln("You ordered apizza with %s and %s", sause_str, cheese_str);
        }
    }

    mixin CMDLINE_MAIN!Cheese;
}
