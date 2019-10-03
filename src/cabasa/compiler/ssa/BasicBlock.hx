package cabasa.compiler.ssa;

typedef BasicBlock = {
	?code:Array<Instr>,
	?jmpKind:TyJmpKind,
	?jmpTargets:Array<Int>,
	?jmpCond:TyValueID,
	?yieldValue:TyValueID
}
