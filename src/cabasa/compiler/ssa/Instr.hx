package cabasa.compiler.ssa;

import haxe.Int64;

/**
 * A Single instructor struct
 */
typedef TInstr = {
    /**
     * The value ID we are assigning to
     */
    ?target:TyValueID,
    ?op:String,
    ?immediates:Array<I64>,
    ?values:Array<TyValueID>
}


@:forward(target, op, immediates, values)
abstract Instr(TInstr) from TInstr to TInstr {

    public inline function branchTargets():Array<Int> {
        return switch this.op {
            case "jmp", "jmp_if", "jmp_table": {
                var ret:Array<Int> = [];
                for(i in 0...this.immediates.length){
                    var t = this.immediates[i];
                    ret.insert(i, Int64.toInt(t));
                }

                ret;
            }
            default: [];
        }
    }
}