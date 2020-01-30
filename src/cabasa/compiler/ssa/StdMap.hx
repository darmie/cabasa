package cabasa.compiler.ssa;

#if cpp
@:unreflective
@:include("map")
@:include("iterator")
@:native('std::map<::cpp::UInt64, ::cpp::UInt64>')
@:structAccess
extern class TStdMap{}



@:unreflective
@:structAccess
@:include("map")
@:include("iterator")
abstract StdMap(TStdMap) from TStdMap to TStdMap {
    public inline  function  new() {
        untyped __cpp__('std::map<::cpp::UInt64, ::cpp::UInt64> valuemap');
        this = untyped __cpp__('valuemap');
    }

    // public inline function copy(a:StdMap):StdMap {
    //     untyped __cpp__('std::copy(std::begin({0}), std::end({0}), std::begin({1}))', a, this);
    //     return untyped __cpp__('{0}', this);
    // }

    public inline function length():Int return untyped __cpp__('{0}.size()', this);
    public inline function empty():Bool return untyped __cpp__('{0}.empty()', this) == 1;

    @:arrayAccess public function get(i:U64):U64 {
        var index = i;
        return untyped __cpp__('{0}.at({1})', this, index);
    }

    @:arrayAccess public inline function set(i:U64, v:U64):Void {
        untyped __cpp__('{0}.insert(std::pair<const ::cpp::UInt64, ::cpp::UInt64>({1}, {2}))', this,  i, v);
    }
}
#end