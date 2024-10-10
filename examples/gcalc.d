module examples.gcalc;

import std.stdio;
import std.math : PI, sqrt;
import std.format;
import std.exception;
import cmdline;

version (CMDLINE_CLASSIC) {

}
else {
    @cmdline struct Gcalc {
        mixin BEGIN;
        mixin VERSION!"0.0.1";
        mixin DESC!"calculate data from various planar graphs";

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

        mixin CONFLICT_OPTS!(0, area, perim);
        mixin CONFLICT_OPTS!(1, rect, tr, circle);

        mixin GROUP_OPTS!(0, height, width);

        mixin NEED_ONEOF_OPTS!(0, data, height, radius);
        mixin NEED_ONEOF_OPTS!(1, data, width, radius);

        mixin END;

        void action() {
            auto target_ = target.get;
            auto graph_ = graph.get;
            size_t preci = cast(size_t) precision.get;
            size_t span_ = cast(size_t) span.get;
            string info;
            if (graph_ == "rect") {
                double h, w;
                if (data) {
                    auto data_ = data.get;
                    enforce(data_.length == 2, new CMDLineError("the length of data must be 2"));
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
                enforce(data_.length == 3, new CMDLineError("the length of data must be 3"));
                l1 = data_[0];
                l2 = data_[1];
                l3 = data_[2];
                enforce(l1 + l2 > l3 && l2 + l3 > l1 && l1 + l3 > l2,
                    new CMDLineError("the length of each edge in triangle must be less than the length of the other two total"));
                double semi_l = (l1 + l2 + l3) / 2;
                info = format("%*.*f", span_ + preci + 1, preci, target_ == "perim"
                        ? semi_l * 2 : (semi_l * (semi_l - l1) * (semi_l - l2) * (semi_l - l3))
                            .sqrt);
            }
            else {
                double r;
                if (data) {
                    auto data_ = data.get;
                    enforce(data_.length == 1, new CMDLineError("the length of data must be 1"));
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