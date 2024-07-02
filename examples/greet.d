module examples.greet;

import std.stdio;
import cmdline : program, OptsWrap, ArgWrap;

void main(in string[] argv) {
    program.name("greet");
    program
        .option!string("-p, --person [name]", "the persion you greet to")
        .option!string("-g, --greeting <str>", "the greeting string");

    program.parse(argv);

    OptsWrap opts = program.getOpts();
    ArgWrap raw_person = opts("person");
    bool person_is_bool = raw_person.verifyType!bool;
    string person = raw_person.isValid ?
        person_is_bool ? "guy" : raw_person.get!string : "";
    string greeting = opts("greeting").get!string;

    writefln("Hello %s, %s", person, greeting);
}
