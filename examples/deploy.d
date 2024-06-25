module examples.deploy;
import cmdline;

import std.stdio;

void main(string[] argv) {
    program.name("deploy");
    program.setVersion("0.0.1");
    program.option("-c, --config <path>", "set config path", "./deploy.conf");

    Command setup = program.command!string("setup [env]").description("run setup commands for all envs");
    setup.argumentDesc("env", "the setup env");
    setup.option("-s, --setup-mode <mode>", "Which setup mode to use", "normal");
    setup.action((in opts, in _env) {
        string mode = opts("setup-mode").get!string;
        string env = _env ? _env.get!string : "env";
        writefln("read config from %s", program.opts["config"].get!string);
        writefln("setup for %s env(s) with %s mode", env, mode);
    });

    Command exec = program.command!string("exec <script>");
    exec.aliasName("ex");
    exec.description("execute the given remote cmd");
    exec.argumentDesc("script", "the script to be executed");
    exec.option("-e, --exec-mode <mode>", "Which exec mode to use", "fast");
    exec.action((opts, _script) {
        string config = program.opts["config"].get!string;
        string script = _script.get!string;
        string mode = opts("exec-mode").get!string;
        writefln("read config from %s", config);
        writefln("exec `%s` using %s mode and config %s", script, mode, config);
    });

    exec.addHelpText(
        AddHelpPos.After,
        `
Examples:
    $ deploy exec sequential
    $ deploy exec async`
    );

    program.parse(argv);
    // Option test_opt = createOption!int("-t, --test <test-num>");
    // test_opt.preset(12);
}
