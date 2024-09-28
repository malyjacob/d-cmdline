module examples.deploy;
import cmdline;

import std.stdio;

version (CMDLINE_CLASSIC) {
    void main(string[] argv) {
        program.name("deploy");
        program.setVersion("0.0.1");
        program.showHelpAfterError;
        program.option("-c, --config <path>", "set config path", "./deploy.conf");
        program.exportAs("config");
        program.commandX("calc", "simple calculator for baisc binary computation", [
            "file": "calc"
        ]);
        program.aliasName("cal");

        Command setup = program.command!string("setup [env]")
            .description("run setup commands for all envs");
        setup.argumentDesc("env", "the setup env");
        setup.option("-s, --setup-mode <mode>", "Which setup mode to use", "normal");
        setup.action((in opts, in _env) {
            string mode = opts("setup-mode").get!string;
            string env = _env.isValid ? cast(string) _env : "env";
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
            string script = cast(string) _script;
            string mode = opts("exec-mode").get!string;
            writefln("read config from %s", config);
            writefln("exec `%s` using %s mode and config %s", script, mode, config);
        });

        exec.addHelpText(
            AddHelpPos.After, `
    Examples:
        $ deploy exec sequential
        $ deploy exec async`
        );

        program.parse(argv);
    }
}
else {
    struct DeployResult {
        mixin BEGIN;
        mixin VERSION!"0.0.1";
        mixin SHOW_HELP_AFTER_ERR;
        mixin SUB_CMD!(SetupResult, ExecResult);
        mixin EXT_SUB_CMD!(
            "calc", "simple calculator for baisc binary computation",
            "calc", "./", "cal"
        );
        mixin DEF_OPT!(
            "config", string, "-c <path>", Desc_d!"set config path", Default_d!"./deploy.conf",
            Export_d
        );
        mixin END;
    }

    struct SetupResult {
        mixin BEGIN;
        mixin DESC!"run setup commands for all envs";
        mixin DEF_ARG!(
            "env", string, Optional_d, Desc_d!"the setup env"
        );
        mixin DEF_OPT!(
            "setupMode", string, "-s <mode>", Desc_d!"Which setup mode to use", Default_d!"normal"
        );
        mixin END;

        void action() {
            string mode_ = setupMode.get;
            string env_ = env ? env.get : "env";
            writefln("read config from %s", this.getParent!DeployResult.config.get);
            writefln("setup for %s env(s) with %s mode", env_, mode_);
        }
    }

    struct ExecResult {
        mixin BEGIN;
        mixin DESC!"execute the given remote cmd";
        mixin ALIAS!"ex";
        mixin HELP_TEXT_AFTER!`
    Examples:
        $ deploy exec sequential
        $ deploy exec async
        `;
        mixin DEF_ARG!(
            "script", string, Desc_d!"the script to be executed"
        );
        mixin DEF_OPT!(
            "execMode", string, "-e <mode>", Desc_d!"Which exec mode to use", Default_d!"fast"
        );
        mixin END;

        void action() {
            string config_ = this.getParent!DeployResult.config.get;
            string script_ = script.get;
            string mode_ = execMode.get;
            writefln("read config from %s", config_);
            writefln("exec `%s` using %s mode and config %s", script_, mode_, config_);
        }
    }

    mixin CMDLINE_MAIN!DeployResult;
}
