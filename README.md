# d-cmdline



**A command line tool library to help construct a command line application easily.**



**Manly of the content in this library, including API design and interal implementation,  is drawn from learning from [commanderjs](https://github.com/tj/commander.js.git).**



## Quick Start



We just  `import cmdline`  so that can use all the features that the library exposes to developers.



This library has preset `program` which is a variable with `Command` type.



The following is a simple command line application that have some simple string mutation including `split` and `join`.

```d
module examples.str_util;

import std.stdio;
import std.string;
import cmdline;

void main(string[] argv) {
    program
        .name("str_util")
        .description("CLI to some string utilities")
        .setVersion("0.0.1");

    Command str_split = program.command("split");
    str_split.description("Split a string into substrings and display as an array.");
    str_split.argument!string("<str>", "string to split");
    str_split.option("-s, --seperator <char>", "separator character", ",");
    str_split.action((opts, _str) {
        string sp = opts("seperator").get!string;
        string str = _str.get!string;
        writeln(split(str, sp));
    });

    Command join = program.command("join");
    join.description("Join the command-arguments into a single string");
    join.argument!string("<strs...>", "one or more string");
    join.option("-s, --seperator <char>", "separator character", ",");
    join.action((in OptsWrap opts, in ArgWrap _strs) {
        string sp = opts("seperator").get!string;
        auto strs = cast(string[]) _strs;
        writeln(strs.join(sp));
    });

    program.parse(argv);
}
```

And after compiling this command line application, we can run the following command lines to do some string mutation.

```bash
$ str_util -V # show the version 
$ str_util --version # same as above 
$ str_util -h # display the help info 
$ str_util --help # same as above 
$ str_util help # same as above 
$ str_util help split # show the help info of sub command: split 
$ str_util split "everything is by design" -s " " # split a string by " " 
$ str_util split "maly,jacob" # split a string by "," 
$ str_util join "maly" "jacob" # join a strings with "," 
$ str_util join "maly" "jacob" -s " " # join a strings with " "`
```



[Here is the documentations in html](./doc/package.html), and you can read it by running it in browser.