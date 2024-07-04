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

### negate options

Negate options are a kind of  special option type that don't store any inner value. A negate option is just a switch related to the option that has same name.



Negate options flag is similar to bool options, but their flags start with `--no-`.



When we add a negate option, a related bool option would be  added and be set default value `true` if this related bool option is not added before, or a related bool option would be set default value `true` if this related bool option is added before.



If a related value or variadic option is added before, this value or variadic option would be disable, that is being removed from the options list of command, when we add a negate option. Therefore, it is better not  to add a option after its related negate option is specified on command line.



Here is an example of the usage of negate options:

```d
module examples.cheese;

import std.stdio;
import cmdline;

void main(in string[] argv) {
    program.name("cheese");
    program.sortOptions();

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
```




```bash
$ cheese
# You ordered apizza with sauce and mozzarella cheese
$ cheese --sauce
# You ordered apizza with sauce and mozzarella cheese
$ cheese --cheese=blue
# You ordered apizza with sauce and blue cheese
$ cheese --no-sauce --no-cheese
# You ordered apizza with no sauce and no cheese
```



### the ways to assign value  to option

There are manly other ways to assign value to option except for command line.



The option will decide the final inner value based on the priorities of these way after being initialized. And you can use `Command.getOptionValSource` to get a enum `Source` to see the final inner value is obtained from which source/way. 



The definition of enum `Source` is below:

```d
/// the source of the final option value gotten
enum Source {
    /// default value
    None,
    /// from client terminal
    Cli,
    /// from env
    Env,
    /// from impled value by other options
    Imply,
    /// from config file
    Config,
    /// from the value that is set by user using `defaultVal` 
    Default,
    /// from the value that is set by user using `preset`
    Preset
}
```

I will introduce these ways to you.

#### Option.defaultVal

We can use `Option.defaultVal` to set a default value to a option (not negate option).



if the flag of an option does not exist on command line, no amy other way to assign value to it, and its default value is set, then the final inner value would be the default value and its source is `Source.Default`.



Since setting default value to a option is often to be used, we can use `Command.option` or `Command.requiredOption` to add n option and set its default value at the same time. 



For value options and variadic options, we cannot set their default value `bool` type.



Here is an example about the usage of setting default value of options:

```d
module examples.defaultval;

import std.stdio;
import cmdline;


void main(in string[] argv) {
    program
        .name("defaultval")
        .option(
            "-c, --cheese <type>",
            "Add the specified type of cheese",
            "blue" 
            // default value, autodetect the option value type is `string`
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
```

```bash
$ defaultval
# You ordered apizza with pepper and blue cheese
$ defaultval -ckabpa
# You ordered apizza with pepper and kabpa cheese
$ default -ckabpa -smint
# You ordered apizza with mint and kabpa cheese 
```

#### Option.env

`Option.env` can assign value to option via environment variable. when we pass a key of an environment variable, this option will automatically parse the environment variable in `string` type to its inner value type and assign this parsed value.



Here is an example about `Option.env`:

```d
module examples.env;

import std.stdio;
import std.conv;
import std.process;

import cmdline;

void main(in string[] argv) {
    environment["BAR"] = "env";

    program.name("env");

    Option env_opt = createOption!string("-f, --foo <required-arg>");
    env_opt.env("BAR");

    program.addOption(env_opt);
    program.addHelpText(AddHelpPos.Before, `
Try the following:
    $ env
    $ env -fxx
    `);

    program.parse(argv);

    OptsWrap opts = program.getOpts;
    string foo = opts("foo").get!string;
    auto src = program.getOptionValSource("foo");
    writefln("-f, --foo <%s>, from %s", foo, src.to!string);
}
```

```bash
$ env
# -f, --foo <env>, from Env
$ env -fxx
# -f, --foo <xx>, from Cli
```

#### Option.implies
