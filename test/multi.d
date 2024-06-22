module multi;

import cmdline;
import std.stdio;
import std.format;
import std.process;
import std.algorithm;
import std.array;
import std.conv;
import std.process;
import std.range;

void main(string[] argv) {
    Command program = createCommand("program");
    program.allowExcessArguments(false);
    program.setVersion("0.0.1");

    Option opt = createOption!string("-g, --greeting <str>");
    program.addActionOption(opt, (string[] vals...) {
        writeln("GREETING:\t", vals[0]);
    });
    program.option("-f, --first <num>", "test", 13);
    program.option("-s, --second <num>", "test", 12);
    program.option("-m, --multi <num>", "multi", 4);
    program.option("-M, --no-multi", "disable the option multi and make the multi num as 1");
    program.option("-N, --no-positive", "set the final result to the negate one");
    program.action((args, optMap) {
        auto fnum = optMap["first"].get!int;
        auto snum = optMap["second"].get!int;
        int multi = 1;
        bool pos;
        if (auto ptr = "multi" in optMap)
            multi = (*ptr).get!int;
        if (auto ptr = "positvie" in optMap)
            pos = (*ptr).get!bool;
        if (!pos)
            multi = -multi;
        writeln(format("%4d * (%4d + %4d) = %4d", multi, fnum, snum, (fnum + snum) * multi));
    });

    program
        .command("list")
        .aliasName("ls")
        .argument("[dir-path]", "dir path", ".")
        .option("-a, --all", "do not ignore entries starting with .")
        .option("-l, --long", "use a long listing format")
        .option("-s, --size", "print the allocated size of each file, in blocks", true)
        .action((args, opts) {
            auto dir = args[0].get!string;
            string l, a, s;
            if ("all" in opts)
                a = opts["all"].get!bool ? "-a" : a;
            if ("long" in opts)
                l = opts["long"].get!bool ? "-l" : l;
            if ("size" in opts)
                s = opts["size"].get!bool ? "-s" : s;
            auto flags = (["ls"] ~ [l, a, s, dir]).filter!(str => str.length).array.join(" ");
            writeln("RUNNING:\t", flags);
            auto result = executeShell(flags);
            writeln(result[1]);
        });

    program
        .command!(string, string)("greet <name> [greetings...]")
        .argumentDesc("name", "the one you greet to")
        .argumentDesc("greetings", "the sequence of greeting senences")
        .description('x'.repeat(200).array) // .description("greeting to some one")
        .aliasName("grt")
        .action((args, opts) {
            string name = args[0].get!string;
            string[] greetings;
            if (args.length > 1) {
                greetings = args[1].get!(string[]);
            }
            writeln(format("hello %s, %s", name, greetings.join(", ")));
        });

    Option header_opt = createOption!string("-H, --header <header-str>");
    header_opt.env("HEADER");

    program
        .command("calculate", ["hidden": true])
        .aliasName("cal")
        .argument("tag", "tag", "Tag")
        .option!int("-m, --multi <value>", "multi value")
        .option!int("-n, --nums <numbers...>", "numbers value")
        .addOption(header_opt)
        .action((args, opts) {
            int multi = opts["multi"].get!int;
            int[] nums = opts["nums"].get!(int[]);
            string tag = args[0].get!string;
            string header = opts["header"].get!string;
            int result = reduce!((a, b) => a + b)(0, nums) * multi;
            string nums_str = nums.map!(n => n.to!string).join(" + ");
            writefln("HEADER:\t%8s", header);
            writeln(format("%8s: %d * (%s) = %d", tag, multi, nums_str, result));
        });

    environment["HEADER"] = "Hello! Guy!";
    environment["YOUR_FRIEND"] = "jack";

    Option method_opt = createOption!string("-m, --method <method>", 'x'.repeat(70).array);
    method_opt.choices("email", "web");
    method_opt.preset("email");
    method_opt.defaultVal("web");
    Option name_opt = createOption!string("-n, --name [name]", "specify the name that your message aiming for.");
    name_opt.env("YOUR_FRIEND");
    name_opt.preset("MY_FRIEND");
    name_opt.implies("suffix", "YOUR_FRIEND_IMPLY");
    name_opt.implies(["paris", "london", "tokyo"]);

    Option suffix_opt = createOption!string("-x, --suffix <suffix>", "the suffix of the path");

    program
        .command!(string)("send <msg>")
        .description("send the msssage to someone by email or website")
        .addOption(method_opt)
        .addOption(name_opt)
        .addOption(suffix_opt)
        .action((args, opts) {
            string msg = args[0].get!string;
            string method;
            string name;
            string suffix;
            bool paris, london, tokyo;

            if ("method" in opts)
                method = opts["method"].get!string;
            if ("name" in opts)
                name = opts["name"].get!string;
            if ("suffix" in opts)
                suffix = opts["suffix"].get!string;

            if (auto ptr = "paris" in opts)
                paris = ptr.get!bool;
            if (auto ptr = "london" in opts)
                london = ptr.get!bool;
            if (auto ptr = "tokyo" in opts)
                tokyo = ptr.get!bool;
            writefln("send msg: %16s to %8s, using mwthod: %8s and the suffix is: %8s", msg, name, method, suffix);
            assert(paris && london && tokyo);
        });

    Command palu = program.command("palu").description("test the member fn `.arguments!Arg`");
    palu.setVersion("0.0.1");
    palu.arguments!(bool, int, double, string)("<required-1> required-2 [optional] [variadic...]");
    palu.action((args, opts) {
        bool req_1 = args[0].get!bool;
        int req_2 = args[1].get!int;
        double op_1 = 0.0;
        string[] var;
        if (args.length > 2)
            op_1 = args[2].get!double;
        if (args.length > 3)
            var = args[3].get!(string[]);
        
        writefln("%6s, %6d, %6f, %s", req_1, req_2, op_1, var);
    });
    palu.argumentDesc([
        "required-1": "required_1",
        "required-2": "required_2",
        "optional": "optional",
        "variadic": "variadic"
    ]);
    writeln(program._outputConfiguration.getOutHelpWidth());
    program.parse(argv);
}
