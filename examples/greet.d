module examples.greet;

import std.stdio;
import cmdline;

version (CMDLINE_CLASSIC) {
    void main(in string[] argv) {
        program.name("greet");
        program
            .option!string("-p, --person [name]", "the persion you greet to")
            .option("-g, --greeting <str>", "the greeting string", "");

        program.parse(argv);

        OptsWrap opts = program.getOpts();
        ArgWrap raw_person = opts("person");
        bool person_is_bool = raw_person.verifyType!bool;
        string person = raw_person.isValid ?
            person_is_bool ? "guy" : raw_person.get!string : "";
        string greeting = opts("greeting").get!string;

        writefln("Hello %s, %s", person, greeting);
    }
}
else {
    struct GreetResult {
        mixin BEGIN;
        mixin DEF_OPT!(
            "person", string, "-p [name]", Desc_d!"the persion you greet to", Preset_d!"guy"
        );
        mixin DEF_OPT!(
            "greeting", string, "-g <str>", Desc_d!"the greeting string"
        );
        mixin END;

        void action() {
            string person_ = person ? person.get : "";
            string greeting_ = greeting ? greeting.get : "";
            writefln("Hello %s, %s", person_, greeting_);
        }
    }

    mixin CMDLINE_MAIN!GreetResult;
}
