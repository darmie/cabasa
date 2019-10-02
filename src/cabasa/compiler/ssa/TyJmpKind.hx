package cabasa.compiler.ssa;

enum abstract TyJmpKind(Int) from Int to Int {
	var JmpUndef;
	var JmpUncond;
	var JmpEither;
	var JmpTable;
	var JmpReturn;
}
