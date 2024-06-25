module cmdline;

public import cmdline.option;
public import cmdline.error;
public import cmdline.argument;
public import cmdline.command;

public Command program;

static this() {
    program = createCommand("program");
}