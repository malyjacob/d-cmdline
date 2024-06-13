module cmdline.event;

alias EventCallbaclk = void delegate(string val);

class EventManager {
private:
    EventCallbaclk[string] eventMap;

public:
    alias Self = typeof(this);

protected:
    Self on(string eventName, EventCallbaclk callback) {
        auto ptr = eventName in eventMap;
        assert(!ptr);
        eventMap[eventName] = callback;
        return this;
    }

    bool emit(string eventName, string val = "") {
        auto fn_ptr = eventName in eventMap;
        if (!fn_ptr)
            return false;
        auto fn = *fn_ptr;
        fn(val);
        return true;
    }
}

unittest {
    import std.conv;
    int count = 0;
    bool fn1_called, fn2_called;
    auto fn1 = (string val) { count += val.to!int; fn1_called = true; };
    auto fn2 = (string val) { count -= val.to!int; fn2_called = true; };

    EventManager em = new EventManager;
    em.on("fn1", fn1);
    em.on("fn2", fn2);

    em.emit("fn1", "11");
    em.emit("fn2", "11");
    assert(fn1_called && fn2_called && count == 0);
}
