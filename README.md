# d-cmdline

**A command line tool library to help construct a command line application easily.**

**Manly of the content in this library, including API design and interal implementation,  is drawn from learning from [commanderjs](https://github.com/tj/commander.js.git).**

## Quick Start

Firstly, before using this library, we should install it using dub.

```
dub add cmdline
```

And  then we just  `import cmdline`  so that we can use all the features that the library exposes to developers.

This library has preset `program` which is a variable with `Command` type.

The following is a simple command line application that have some simple string mutations including `split` and `join`.

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

And after compiling this command line application, we can run the following command lines to do some string mutations and display the help or version info.

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

## Options

Option is one of most important parts in command line. Through options, we can pass   infomation to the cmd-line application to process it, then make some action and output the result you want.

After parsing, the options' final inner values will be stored in key-value type. we can get the values according to their long flag names without `--`. 

Options have manly  type, including bool option, value option, variadic option and negative option.

In d-cmdline, the inner value must be among `int`, `double`, `bool`, `string` and their array type `int[]`, `double[]` and `string[]`, not supporting `bool[]`, since `bool` value are often used as a switch. It is not necessary to set `bool[]` as one of inner stored value type, which is the same case in `Argument` . 

We can use build-in trait function `isOptionValueType` to determine whether a type is legal option inner value type and use `isBaseOptionValue` to determine  whether a type is base option inner type, that is `int`, `double`, `bool` and `string`.

```d
    static assert(isOptionValueType!int);
    static assert(isOptionValueType!string);
    static assert(isOptionValueType!(int[]));
    static assert(isOptionValueType!(string[]));

    static assert(isBaseOptionValueType!int);
    static assert(isBaseOptionValueType!double);
    static assert(isBaseOptionValueType!bool);
    static assert(isBaseOptionValueType!string);

    static assert(!isOptionValueType!(bool[]));
    static assert(!isOptionValueType!float);
    static assert(!isBaseOptionValueType!(int[]));
```

Necessary to remember that the options's flag pattern must include its long flag, while the short flag is optional.

Here are two main way to create options and apply it to command line application.

1. using member functions like `Command.option` and `Command.requireOption`

2. using functions like `createOption` and `createNegateOption`  and then using member function `addOption` to apply them on a command variable.

```d
Command program = createCommand("program");
program.option("-f, --flag", "description"); // bool option
program.option("-o, --output <dest>", "description", "path-to-dest"); // string option

// variadic option
Option variadic_opt = createOption!int("-a|--array <numbers...>", "desc");
program.addOption(variadic_opt);

// negate option
NegateOption nopt = createNegateOption("-F --no-flag", "disable the `--flag`");
program.addOption(nopt);
```

### bool options

On the command line, bool options are often used to control the behavior of a program.

```shell
dotnet tool update dotnet-suggest --verbosity quiet --global
```

In this example,  `--global` is bool options. Bool arguments that usually default to true if the option is specified on the command line but no value is specified.

When bool flag specified then the value is `true`, otherwise the value is undefined and cannot be gotten.

Only its related negate option is specified, then the bool option's value is `false`.

 And when related bool option ihas been configured but  not specifled, then the bool option's value is `true` by default. 

The following is an example of bool options using  `d-cmdline`

```d
module examples.cheese;
import cmdline;
import std.stdio;

void main(in string[] argv) {
    Command program = createCommand("cheese");
    program.option("--sauce", "Add sauce");
    program.option("--no-sauce", "Remove sauce");

    program.parse(argv);

    OptsWrap opts = program.getOpts();
    bool has_sauce = opts("sauce").get!bool;
    if(has_sauce)
        writeln("Add sauce");
    else
        writeln("Remove sauce");
}
```

```bash
$ cheese # Add sauce
$ cheese --sauce # same as above
$ cheese --no-sauce # Remove sauce
```

### value options

On the command line,  the value options are always used to pass value to the program and its value stored in key-value structure, key is its name and value is its inner  value.

The flags of value options on command line are like `--flag value` , `-f value`, `--flag=value`, `-fvalue`.



In `d-cmdline` value options' inner sotred value type is among `int`, `double` and `string`.



Value options have two type, that is rquired value options and optional required value options. The required value options' flag pattern is like `--flag <value-name>`, while the optional value options' flag pattern is like `--flag [value-name]`.



For required value options, the inner value of the option must be valid if the flag of the options are found in command line, while the optional value options' ones need not.



And if the optional value option's flag is found while no value be found after it, then the optional value option's inner value would be `true`, instead of the registered type.



Let's see what the required/optional value options are like:

```d
module examples.greet;

import std.stdio;
import cmdline : program, OptsWrap, ArgWrap;

void main(in string[] argv) {
    program
        .name("greet")
        .description("a simple greeting program")
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
```

```bash
$ greet -g "how are you?" # Hello , how are you?
$ greet -g "how are you?" -p # Hello guy, how are you?
$ greet -g "how are you?" -pjack # Hello jack, how are you?
```

### variadic options

On the command line, the variadic options are always used to pass values to the program and its values stored in key-value structure, key is its name and value is stored as an array of the values you pass on command line.



The flags of variadic options on command line are like `--flag value1 value2` , `-f value1 value2`, `--flag=value1 --flag=value2`, `-fvalue1 -fvalue2`.



In `d-cmdline` variadic options' inner sotred value type is among `int[]`, `double[]` and `string[]`.



Variadic options have two type, that is rquired variadic options and optional required variadic options. The required variadic options' flag pattern is like `--flag <value-name...>`, while the optional variadic options' flag pattern is like `--flag [value-name...]`.



For required variadic options, the inner value of the option must be valid and its length must not be zero if the flag of the options are found in command line, while the optional value options' ones need not.



And if the optional variadic option's flag is found while no value be found after it, then the optional value option's inner value would be `true`, instead of the registered type.



Let's see what the required/optional variadic options are like:

```d
module examples.variadic;

import std.stdio;
import std.conv;
import cmdline : program, OptsWrap;


void main(in string[] argv) {
    program
        .name("variadic")
        .description("test the variadic option")
        .option!int("-r, --required <values...>", "")
        .option!(int[])("-o, --optional [values...]", "");
    
    program.parse(argv);
    
    OptsWrap opts = program.getOpts();
    auto raw_required = opts("required");
    auto raw_optional = opts("optional");

    string required = raw_required.isValid ?
            raw_required.get!(int[]).to!string : "no required";

    string optional = raw_optional.isValid ?
            raw_optional.verifyType!bool ? true.to!string
            : raw_optional.get!(int[]).to!string : "no optional";

    writefln("required: %s", required);
    writefln("optional: %s", optional);
}
```

```bash
$ variadic -r 12 13 -r14 -r15
# required: [12, 13, 14, 15]
# optional: no optional

$ variadic -r 12 13 -r14 -r15 -o
# required: [12, 13, 14, 15]
# optional: true

$ variadic -r 12 13 -r14 -r15 -o 34
# required: [12, 13, 14, 15]
# optional: [34]

$ variadic -r 12 13 -r14 -r15 -o34
# same as above

$ variadic -o 12 13 -o14 -o15
# required: no required
# optional: [12, 13, 14, 15]
```
