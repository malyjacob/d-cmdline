module cmdline.error;


class CMDLineError : Error {
    enum string name = typeof(this).stringof;

    string code;
    ubyte exitCode;

    this(string msg = "", ubyte exitCode = 1, string code = "", Throwable nextInChain = null) pure nothrow @nogc @safe {
        super(msg, nextInChain);
        this.exitCode = exitCode;
        this.code = code;
    }
}

class InvalidArgumentError : CMDLineError {
    enum string name = typeof(this).stringof;

    this(string msg = "", string code = "") {
        super(msg, 1, code);
    }
}

class InvalidOptionError : CMDLineError {
    enum string name = typeof(this).stringof;

    this(string msg = "", string code = "") {
        super(msg, 1, code);
    }
}

class InvalidFlagError : CMDLineError {
    enum string name = typeof(this).stringof;

    this(string msg = "") {
        super(msg, 1, "CMDLine."~name);
    }
}

class ImplyOptionError : CMDLineError {
    enum string name = typeof(this).stringof;

    this(string msg = "") {
        super(msg, 1, "CMDLine."~name);
    }
}

class OptionFlagsError : CMDLineError {
    enum string name = typeof(this).stringof;

    this(string msg = "") {
        super(msg, 1, "CMDLine."~name);
    }
}

class OptionMemberFnCallError : CMDLineError {
    enum string name = typeof(this).stringof;

    this(string msg = "") {
        super(msg, 1, "CMDLine."~name);
    }
}