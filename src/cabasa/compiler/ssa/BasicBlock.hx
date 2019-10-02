package cabasa.compiler.ssa;

typedef BasicBlock = {
	var code:Array<Instr>;
	var jmpKind:TyJmpKind;
	var jmpTargets:Array<Int>;
	var jmpCond:TyValueID;
	var yieldValue:TyValueID;
}