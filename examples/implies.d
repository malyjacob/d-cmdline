module examples.implies;

import std.stdio;
import std.format;
import std.conv;
import cmdline;

void main(in string[] argv) {
    program.name("implies");
    program.option("--foo", "foo bool to be implied");
    program.option("--bar <int-num>", "bar for int implied", 0);

    auto im_opt = createOption!int("--imply <int-num>", "implier with int num");
    im_opt.choices(0, 1);

    im_opt.implies(["foo", "fox"]);
    im_opt.implies("bar", 13);
    im_opt.implies("baz", false);

    program.addOption(im_opt);

    program.parse(argv);

    OptsWrap opts = program.getOpts;
    auto im_raw = opts("imply");
    auto foo_raw = opts("foo");
    auto fox_raw = opts("fox");
    auto baz_raw = opts("baz");

    string bar_info = format!"set bar <%d>"(opts("bar").get!int);
    string im_info = im_raw.isValid ?
        format!"set imply <%d>"(im_raw.get!int) : ("unset imply");
    string foo_info = foo_raw.isValid ?
        format!"set foo `%s`"(foo_raw.get!bool
                .to!string) : ("unset foo");
    string fox_info = fox_raw.isValid ?
        format!"set fox `%s`"(fox_raw.get!bool
                .to!string) : ("unset fox");
    string baz_info = baz_raw.isValid ?
        format!"set baz %s"(baz_raw.get!bool
                .to!string) : ("unset baz");

    writefln("%s, %s, %s, %s, %s.", bar_info, im_info, foo_info, fox_info, baz_info);
}
