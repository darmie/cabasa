package cabasa.compiler.ssa;

import haxe.Int64;

/**
 * Describes the Control Flow Graph
 */
class CFG {
	public var blocks:Array<BasicBlock>;

	public function new() {}

	public function toInsSeq():Array<Instr> {
		var out:Array<Instr> = [];
		var blockRelocs = [];
		var blockEnds = [];

		for (bb in blocks) {
			blockRelocs.push(out.length);
			for (op in bb.code) {
				out.push(op);
			}
			out.push({}); // jmp placeholder
			blockEnds.push(out.length);
		}

		for (bb in blocks) {
			var i = blocks.indexOf(bb);
			var jmpIns = out[blockEnds[i] - 1];
			jmpIns.immediates = [];
			for (target in bb.jmpTargets) {
				var j = bb.jmpTargets.indexOf(target);
				jmpIns.immediates[j] = Int64.ofInt(blockRelocs[target]);
			}
			switch bb.jmpKind {
				case JmpUndef:
					throw "got JmpUndef";
				case JmpUncond:
					{
						jmpIns.op = "jmp";
						jmpIns.values = [bb.yieldValue];
					}
				case JmpEither:
					{
						jmpIns.op = "jmp_either";
						jmpIns.values = [bb.jmpCond, bb.yieldValue];
					}
				case JmpTable:
					{
						jmpIns.op = "jmp_table";
						jmpIns.values = [bb.jmpCond, bb.yieldValue];
					}
				case JmpReturn:
					{
						jmpIns.op = "jmp_return";
						if (bb.yieldValue != 0) {
							jmpIns.values = [bb.yieldValue];
						}
					}
				default:
					throw "unreachable";
			}
		}

		return out;
	}
}
