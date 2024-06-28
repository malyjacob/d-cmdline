module examples.cheese;

import std.stdio;
import cmdline;

void main(in string[] argv) {
    program.name("cheese");

    program.option("--no-sauce", "Remove sauce");
    program.option("--cheese <flavor>", "cheese flavor", "mozzarella");
    program.option("--no-cheese", "plain with no cheese");

    program.action((opts) {
        string sause_str = opts("sauce") ? "sauce" : "no sauce";
        string cheese_str = opts("cheese").isValid ?
            opts("cheese").get!string ~ " cheese" : "no cheese";
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
