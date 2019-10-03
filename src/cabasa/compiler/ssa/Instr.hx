package cabasa.compiler.ssa;

/**
 * A Single instructor struct
 */
typedef Instr = {
    /**
     * The value ID we are assigning to
     */
    ?target:TyValueID,
    ?op:String,
    ?immediates:Array<I64>,
    ?values:Array<TyValueID>
}