/++
## the command line tool library to help construct a command line application easily.

License: MIT

Authors: 笑愚(xiaoyu)

Date: 6.29  2024

Submodlues:

this module consists of the following submodules export:

## [cmdline.error](./error.html)
## [cmdline.option](./option.html)
## [cmdline.argument](./argument.html)
## [cmdline.command](./command.html)
## [cmdline.ext](./ext.html)
+/

module cmdline;

public import cmdline.error;
public import cmdline.option;
public import cmdline.argument;
public import cmdline.command;
public import cmdline.ext;

/// the default command given, which you can make it as a rooot command to construct a command line program.
public Command program;

static this() {
    program = createCommand("program");
}