module examples.defaultval;

import std.stdio;
import cmdline;

void main(in string[] argv) {
    program
        .name("defaultval")
        .option(
            "-c, --cheese <type>",
            "Add the specified type of cheese",
            "blue"// default value, autodetect the option value type is `string`
        
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
