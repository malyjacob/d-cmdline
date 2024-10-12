module examples.gcalc;

import std.stdio;
import std.math : PI, sqrt;
import std.format;
import cmdline;

enum TXT = q{
Author: maly jacob (笑愚)
About: https://github.com/malyjacob/d-cmdline
Try:
    $ gcalc -s4 -p2 -AR -H12 -W5    # calculate the area of a rectangle with height 12 and width 5
    $ gcalc -s4 -p2 -PR -H12 -W5    # calculate the perimeter of a rectangle with height 12 and width 5
    $ gcalc -s2 -AC -B2             # calculate the area of a circle with the radius 2
    $ gcalc -s2 -p2 -AT -d 5 12 13  # calculate the area of a triangle with the edges 5, 12 and 13
};

version (CMDLINE_CLASSIC) {
    void main(in string[] argv) {
        program
            .addHelpText(AddHelpPos.Before, TXT)
            .description("calculate data from various planar graphs")
            .setVersion("0.0.1");
        
        Option target_opt, area_opt, perim_opt, graph_opt, data_opt,
            rect_opt, tr_opt, circle_opt, height_opt, width_opt,
            radius_opt, precision_opt, span_opt;
        
        target_opt = createOption!string("--target -t <target>", "set the target")
            .choices("area", "perim")
            .makeMandatory;
        
        area_opt = createOption("--area -A", "set the target area")
            .implies("target", "area");

        perim_opt = createOption("--perim -P", "set the target perim")
            .implies("target", "perim");
        
        graph_opt = createOption!string("--graph -g <graph>", "set the graph")
            .choices("rect", "tr", "circle")
            .makeMandatory;
        
        data_opt = createOption!double("--data -d <data...>", "set the data")
            .rangeOf(0.0, 1024.0)
            .needs("graph");

        rect_opt = createOption("--rect -R", "set the graph rectangle")
            .implies("graph", "rect")
            .needOneOf("data", "height");

        tr_opt = createOption("--tr -T", "set the graph triangle")
            .implies("graph", "tr")
            .needs("data");

        circle_opt = createOption("--circle, -C", "set the graph circle")
            .implies("graph", "circle")
            .needOneOf("data", "radius");

        height_opt = createOption!double("--height -H <height>", "set the height for rect")
            .rangeOf(0.0, 1024.0)
            .needs("rect");

        width_opt = createOption!double("--width -W <width>", "set the width for rect")
            .rangeOf(0.0, 1024.0)
            .needs("rect");

        radius_opt = createOption!double("--radius -B <radius>", "set the radius for circle")
            .rangeOf(0.0, 1024.0)
            .needs("circle");

        precision_opt = createOption!int("--precision -p <dig>", "set the precision")
            .rangeOf(1, 6)
            .defaultVal(6);

        span_opt = createOption!int("--span -s <len>", "set the span")
            .rangeOf(1, 6)
            .defaultVal(6);
        
        program.addOptions(target_opt, area_opt, perim_opt, graph_opt, data_opt,
            rect_opt, tr_opt, circle_opt, height_opt, width_opt,
            radius_opt, precision_opt, span_opt);

        program
            .needOneOfOptions("data", "height", "radius")
            .needOneOfOptions("data", "width", "radius")
            .groupOptions("height", "width")
            .conflictOptions("rect", "tr", "circle")
            .conflictOptions("area", "perim");

        program.action((in OptsWrap opts) {
            auto target = opts("target").get!string;
            auto graph = opts("graph").get!string;
            size_t preci = cast(size_t) opts("precision").get!int;
            size_t span = cast(size_t) opts("span").get!int;
            ArgWrap data_r = opts("data");
            string info;
            if (graph == "rect") {
                double h, w;
                if (data_r.isValid) {
                    auto data = data_r.get!(double[]);
                    if (data.length != 2)
                        program.parsingError("the length of data must be 2");
                    h = data[0];
                    w = data[1];
                }
                else {
                    h = opts("height").get!double;
                    w = opts("width").get!double;
                }
                info = format("%*.*f", span + preci + 1, preci, target == "perim"
                        ? 2 * (h + w) : h * w);
            }
            else if (graph == "tr") {
                double l1, l2, l3;
                auto data = data_r.get!(double[]);
                if (data.length != 3)
                    program.parsingError("the length of data must be 3");
                l1 = data[0];
                l2 = data[1];
                l3 = data[2];
                if (l1 + l2 < l3 || l2 + l3 < l1 || l1 + l3 < l2)
                    program.parsingError("the length of each edge in triangle must be less than the length of the other two total");
                double semi_l = (l1 + l2 + l3) / 2;
                info = format("%*.*f", span + preci + 1, preci, target == "perim"
                        ? semi_l * 2 : (semi_l * (semi_l - l1) * (semi_l - l2) * (semi_l - l3)).sqrt);
            }
            else {
                double r;
                if (data_r.isValid) {
                    auto data = data_r.get!(double[]);
                    if (data.length != 1)
                        program.parsingError("the length of data must be 1");
                    r = data[0];
                }
                else
                    r = opts("radius").get!double;
                info = format("%*.*f", span + preci + 1, preci, target == "perim"
                        ? 2 * PI * r : PI * r * r);
            }
            info.writeln;
        });

        program.parse(argv);
    }
}
else {
    @cmdline struct Gcalc {
        mixin BEGIN;
        mixin VERSION!"0.0.1";
        mixin DESC!"calculate data from various planar graphs";

        mixin HELP_TEXT_BEFORE!TXT;

        mixin DEF_OPT!(
            "target", string, "-t <target>", Desc_d!"set the target",
            Mandatory_d,
            Choices_d!("area", "perim")
        );

        mixin DEF_BOOL_OPT!(
            "area", "-A", Desc_d!"set the target area",
            Implies_d!("target", "area")
        );

        mixin DEF_BOOL_OPT!(
            "perim", "-P", Desc_d!"set the target perim",
            Implies_d!("target", "perim")
        );

        mixin DEF_OPT!(
            "graph", string, "-g <graph>", Desc_d!"set the graph",
            Mandatory_d,
            Choices_d!("rect", "tr", "circle")
        );

        mixin DEF_VAR_OPT!(
            "data", double, "-d <data...>", Desc_d!"set the data",
            Range_d!(0.0, 1024.0),
            Needs_d!"graph"
        );

        mixin DEF_BOOL_OPT!(
            "rect", "-R", Desc_d!"set the graph rectangle",
            Implies_d!("graph", "rect"),
            NeedOneOf_d!("data", "height")
        );

        mixin DEF_BOOL_OPT!(
            "tr", "-T", Desc_d!"set the graph triangle",
            Implies_d!("graph", "tr"),
            Needs_d!"data"
        );

        mixin DEF_BOOL_OPT!(
            "circle", "-C", Desc_d!"set the graph circle",
            Implies_d!("graph", "circle"),
            NeedOneOf_d!("data", "radius")
        );

        mixin DEF_OPT!(
            "height", double, "-H <height>", Desc_d!"set the height for rect",
            Range_d!(0.0, 1024.0),
            Needs_d!"rect"
        );

        mixin DEF_OPT!(
            "width", double, "-W <width>", Desc_d!"set the width for rect",
            Range_d!(0.0, 1024.0),
            Needs_d!"rect"
        );

        mixin DEF_OPT!(
            "radius", double, "-B <banjin>", Desc_d!"set the radius for circle",
            Range_d!(0.0, 1024.0),
            Needs_d!"circle"
        );

        mixin DEF_OPT!(
            "precision", int, "-p <dig>", Desc_d!"set the precision",
            Range_d!(1, 6),
            Default_d!6
        );

        mixin DEF_OPT!(
            "span", int, "-s <len>", Desc_d!"set the span",
            Range_d!(1, 6),
            Default_d!6
        );

        mixin CONFLICT_OPTS!(area, perim);
        mixin CONFLICT_OPTS!(rect, tr, circle);

        mixin GROUP_OPTS!(height, width);

        mixin NEED_ONEOF_OPTS!(data, height, radius);
        mixin NEED_ONEOF_OPTS!(data, width, radius);

        mixin END;

        void action() {
            auto target_ = target.get;
            auto graph_ = graph.get;
            size_t preci = cast(size_t) precision.get;
            size_t span_ = cast(size_t) span.get;
            string info;
            const Command cmd = this.getInnerCmd;
            if (graph_ == "rect") {
                double h, w;
                if (data) {
                    auto data_ = data.get;
                    if (data_.length != 2)
                        cmd.parsingError("the length of data must be 2");
                    h = data_[0];
                    w = data_[1];
                }
                else {
                    h = height.get;
                    w = width.get;
                }
                info = format("%*.*f", span_ + preci + 1, preci, target_ == "perim"
                        ? 2 * (h + w) : h * w);
            }
            else if (graph_ == "tr") {
                double l1, l2, l3;
                auto data_ = data.get;
                if (data_.length != 3)
                    cmd.parsingError("the length of data must be 3");
                l1 = data_[0];
                l2 = data_[1];
                l3 = data_[2];
                if (l1 + l2 < l3 || l2 + l3 < l1 || l1 + l3 < l2)
                    cmd.parsingError("the length of each edge in triangle must be less than the length of the other two total");
                double semi_l = (l1 + l2 + l3) / 2;
                info = format("%*.*f", span_ + preci + 1, preci, target_ == "perim"
                        ? semi_l * 2 : (semi_l * (semi_l - l1) * (semi_l - l2) * (semi_l - l3)).sqrt);
            }
            else {
                double r;
                if (data) {
                    auto data_ = data.get;
                    if (data_.length != 1)
                        cmd.parsingError("the length of data must be 1");
                    r = data_[0];
                }
                else
                    r = radius.get;
                info = format("%*.*f", span_ + preci + 1, preci, target_ == "perim"
                        ? 2 * PI * r : PI * r * r);
            }
            writeln(info);
        }
    }

    mixin CMDLINE_MAIN!Gcalc;
}