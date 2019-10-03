package cabasa.compiler.ssa;

typedef Location = {
    ?codePos:Int,
    ?stackDepth:Int,
    ?brHead:Bool,
    ?preserveTop:Bool,
    ?loopPreserveTop:Bool,
    ?fixupList:Array<FixupInfo>,
    ?ifBlock:Bool
}