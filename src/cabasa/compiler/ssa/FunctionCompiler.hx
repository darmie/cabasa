package cabasa.compiler.ssa;

import haxe.io.BytesBuffer;
import wasp.io.Read;
import haxe.io.BytesInput;
import wasp.io.LittleEndian;
import haxe.io.BytesOutput;
import wasp.types.FunctionSig;
import wasp.types.BlockType;
import haxe.io.FPHelper;
import haxe.Int64;
import wasp.Module;
import wasp.disasm.Disassembly;
import haxe.io.Bytes;

using cabasa.compiler.Opcodes;

/**
 * FunctionCompiler represents a compiler which translates a WebAssembly module's
 * intepreted code into a Static-Single-Assignment-based intermediate representation.
 */
class FunctionCompiler {
	public var module:Module;
	public var source:Disassembly;

	public var code:Array<Instr>;
	public var stack:Array<TyValueID>;
	public var locations:Array<Location>;

	public var callIndexOffset:Int;
	public var stackValueSets:Map<Int, Array<TyValueID>>;
	public var usedValueIDs:Map<TyValueID, Dynamic>;
	public var valueID:TyValueID;

	public var pushStack:Dynamic = null;

	public function new(m:Module, d:Disassembly) {
		module = m;
		source = d;
		code = [];
		stack = [];
		locations = [];
		stackValueSets = new Map<Int, Array<TyValueID>>();
		usedValueIDs = new Map<TyValueID, Dynamic>();

		pushStack = Reflect.makeVarArgs(ppushBack);
	}

	public function nextValueID():TyValueID {
		this.valueID++;
		return this.valueID;
	}

	public function popStack(n:Int):Array<TyValueID> {
		if (this.stack.length < n) {
			throw "stack underflow";
		}

		var ret:Array<TyValueID> = [];

		var pos:Int = stack.length - n;

		ret = stack.slice(pos);
		stack = stack.slice(0, pos);

		return ret;
	}

	function ppushBack(values:Array<Dynamic>) {
		for (i in 0...values.length) {
			var id:TyValueID = cast values[i];
			if (usedValueIDs.exists(id)) {
				throw "pushing a value ID twice is not supported yet";
			}
			usedValueIDs.set(id, {});
			stackValueSets.get(stack.length + i).push(id);
		}

		stack.concat([for (value in values) cast value]);
	}

	public function fixupLocationRef(loc:Location, wasUnreachable:Bool) {
		if (loc.preserveTop || loc.loopPreserveTop) {
			if (wasUnreachable) {
				code.push(buildInstr(0, "jmp", [Int64.ofInt(code.length + 1)], [0]));
			} else {
				code.push(buildInstr(0, "jmp", [Int64.ofInt(code.length + 1)], popStack(1)));
			}
		}

		var innerBrTarget:I64 = 0;
		if (loc.brHead) {
			innerBrTarget = Int64.ofInt(loc.codePos);
		} else {
			innerBrTarget = Int64.ofInt(code.length);
		}

		for (info in loc.fixupList) {
			code[info.codePos].immediates[info.tablePos] = innerBrTarget;
		}

		if (loc.preserveTop || loc.loopPreserveTop) {
			var retId = nextValueID();
			code.push(buildInstr(retId, "phi", null, null));
			pushStack(retId);
		}
	}

	public function filterFloatingPoint() {
		for (i in 0...code.length) {
			var ins = code[i];
			if (StringTools.startsWith(ins.op, "f32.")
				|| StringTools.startsWith(ins.op, "f64.")
				|| StringTools.startsWith(ins.op, "/f32.")
				|| StringTools.startsWith(ins.op, "/f64.")) {
				if (StringTools.contains(ins.op, ".reinterpret/") || StringTools.contains(ins.op, ".const")) {
					continue;
				}
				code[i] = buildInstr(ins.target, "fp_disabled_error", null, null);
			}
		}
	}

	/**
	 * compiles an interpreted WebAssembly modules source code into
	 * a Static-Single-Assignment-based intermediate representation.
	 * @param importTypeIDs
	 */
	public function compile(importTypeIDs:Array<Int>) {
		locations.push({
			codePos: 0,
			stackDepth: 0
		});

		var unreachableDepth = 0;

		for (ins in source.code) {
			var op:wasp.operators.Ops = ins.op;
			var wasUnreachable = false;

			if (unreachableDepth != 0) {
				wasUnreachable = true;

				switch op {
					case Block | Loop | If:
						{
							unreachableDepth++;
						}
					case End:
						{
							unreachableDepth--;
						}
					case _:
				}

				if (unreachableDepth == 1 && op == Else) {
					unreachableDepth--;
				}

				if (unreachableDepth != 0) {
					continue;
				}
			}

			switch op {
				case Nop:
				case Unreachable:
					{
						code.push(buildInstr(0, op.toString(), null, null));
						unreachableDepth = 1;
					}
				case Select:
					{
						var retID = nextValueID();
						code.push(buildInstr(retID, op.toString(), null, popStack(3)));
						pushStack(retID);
					}
				case I32Const:
					{
						var retID = nextValueID();
						code.push(buildInstr(retID, op.toString(), [Int64.ofInt(ins.immediates[0])], null));
						pushStack(retID);
					}
				case I64Const:
					{
						var retID = nextValueID();
						code.push(buildInstr(retID, op.toString(), [ins.immediates[0]], null));
						pushStack(retID);
					}
				case F32Const:
					{
						var retID = nextValueID();
						code.push(buildInstr(retID, op.toString(), [Int64.fromFloat(ins.immediates[0])], null));
						pushStack(retID);
					}
				case F64Const:
					{
						var retID = nextValueID();
						var val = FPHelper.doubleToI64(ins.immediates[0]);
						code.push(buildInstr(retID, op.toString(), [val], null));
						pushStack(retID);
					}
				case I32Add | I32Sub | I32Mul | I32DivS | I32DivU | I32RemS | I32RemU | I32And | I32Or | I32Xor | I32Shl | I32ShrS | I32ShrU | I32Rotl | I32Rotr | I32Eq | I32Ne | I32LtS | I32LtU | I32LeS | I32LeU | I32GtS | I32GtU | I32GeU | I32GeS | I64Add | I64Sub | I64Mul | I64DivS | I64DivU | I64RemS | I64RemU | I64And | I64Or | I64Xor | I64Shl | I64ShrS | I64ShrU | I64Rotl | I64Rotr | I64Eq | I64Ne | I64LtS | I64LtU | I64LeS | I64LeU | I64GtS | I64GtU | I64GeU | I64GeS | F32Add | F32Sub | F32Mul | F32Div | F32Min | F32Max | F32Copysign | F32Eq | F32Ne | F32Lt | F32Le | F32Gt | F32Ge | F64Add | F64Sub | F64Mul | F64Div | F64Min | F64Max | F64Copysign | F64Eq | F64Ne | F64Lt | F64Le | F64Gt | F64Ge:
					{
						var retID = nextValueID();
						code.push(buildInstr(retID, op.toString(), null, popStack(2)));
						pushStack(retID);
					}
				case I32Clz | I32Ctz | I32Popcnt | I32Eqz | I64Clz | I64Ctz | I64Popcnt | I64Eqz | F32Sqrt | F32Ceil | F32Floor | F32Trunc | F32Nearest | F32Abs | F32Neg | F64Sqrt | F64Ceil | F64Floor | F64Trunc | F64Nearest | F64Abs | F64Neg | I32WrapI64 | I64ExtendUI32 | I64ExtendSI32 | I32TruncUF32 | I32TruncUF64 | I64TruncUF32 | I64TruncUF64 | I32TruncSF32 | I32TruncSF64 | I64TruncSF32 | I64TruncSF64 | F32DemoteF64 | F64PromoteF32 | F32ConvertUI32 | F32ConvertUI64 | F64ConvertUI32 | F64ConvertUI64 | F32ConvertSI32 | F32ConvertSI64 | F64ConvertSI32 | F64ConvertSI64 | I32ReinterpretF32 | I64ReinterpretF64 | F32ReinterpretI32 | F64ReinterpretI64:
					{
						var retID = nextValueID();
						code.push(buildInstr(retID, op.toString(), null, popStack(1)));
						pushStack(retID);
					}
				case Drop:
					popStack(1);
				case I32Load | I64Load | I32Load8s | I32Load16s | I64Load8s | I64Load16s | I64Load32s | I32Load8u | I32Load16u | I64Load8u | I64Load16u | I64Load32u | F32Load | F64Load:
					{
						var retID = nextValueID();
						var v:U32 = cast ins.immediates[0];
						var v1:U32 = cast ins.immediates[1];
						#if cs
						var val = untyped __cs__('System.Convert.ToInt64({0})', v);
						var val1 = untyped __cs__('System.Convert.ToInt64({0})', v1);
						#elseif java
						var val = Int64.ofInt(v.toInt());
						var val1 = Int64.ofInt(v1.toInt());
						#elseif cpp
						var val = untyped __cpp__('(int64_t){0}', v);
						var val1 = untyped __cpp__('(int64_t){0}', v1);
						#end
						code.push(buildInstr(retID, op.toString(), [val, val1], popStack(1)));
						pushStack(retID);
					}
				case I32Store | I32Store8 | I32Store16 | I64Store | I64Store8 | I64Store16 | I64Store32 | F32Store | F64Store:
					{
						var v:U32 = cast ins.immediates[0];
						var v1:U32 = cast ins.immediates[1];
						#if cs
						var val = untyped __cs__('System.Convert.ToInt64({0})', v);
						var val1 = untyped __cs__('System.Convert.ToInt64({0})', v1);
						#elseif java
						var val = Int64.ofInt(v.toInt());
						var val1 = Int64.ofInt(v1.toInt());
						#elseif cpp
						var val = untyped __cpp__('(int64_t){0}', v);
						var val1 = untyped __cpp__('(int64_t){0}', v1);
						#end
						code.push(buildInstr(0, op.toString(), [val, val1], popStack(2)));
					}
				case GetLocal | GetGlobal:
					{
						var retID = nextValueID();
						var v:U32 = cast ins.immediates[0];
						#if cs
						var val = untyped __cs__('System.Convert.ToInt64({0})', v);
						#elseif java
						var val = Int64.ofInt(v.toInt());
						#elseif cpp
						var val = untyped __cpp__('(int64_t){0}', v);
						#end
						code.push(buildInstr(retID, op.toString(), [val], null));
						pushStack(retID);
					}
				case SetLocal | SetGlobal:
					{
						var v:U32 = cast ins.immediates[0];
						#if cs
						var val = untyped __cs__('System.Convert.ToInt64({0})', v);
						#elseif java
						var val = Int64.ofInt(v.toInt());
						#elseif cpp
						var val = untyped __cpp__('(int64_t){0}', v);
						#end
						code.push(buildInstr(0, op.toString(), [val], popStack(1)));
					}
				case TeeLocal:
					{
						var v:U32 = cast ins.immediates[0];
						#if cs
						var val = untyped __cs__('System.Convert.ToInt64({0})', v);
						#elseif java
						var val = Int64.ofInt(v.toInt());
						#elseif cpp
						var val = untyped __cpp__('(int64_t){0}', v);
						#end
						code.push(buildInstr(0, 'set_local', [val], [this.stack[this.stack.length - 1]]));
					}
				case Block:
					{
						locations.push({
							codePos: code.length,
							stackDepth: stack.length,
							preserveTop: ins.block.signature != BlockType.BlockTypeEmpty
						});
					}
				case Loop:
					{
						locations.push({
							codePos: code.length,
							stackDepth: stack.length,
							loopPreserveTop: ins.block.signature != BlockType.BlockTypeEmpty,
							brHead: true
						});
					}
				case If:
					{
						var cond = popStack(1)[0];
						locations.push({
							codePos: code.length,
							stackDepth: stack.length,
							preserveTop: ins.block.signature != BlockType.BlockTypeEmpty,
							ifBlock: true
						});
						code.push(buildInstr(0, 'jmp_if', [Int64.ofInt(code.length + 2)], [cond, 0]));
						code.push(buildInstr(0, 'jmp', [Int64.ofInt(-1)], [0]));
					}
				case Else:
					{
						var loc = locations[locations.length - 1];
						if (!loc.ifBlock) {
							throw "expected if block";
						}
						if (loc.fixupList == null)
							loc.fixupList = [];
						loc.fixupList.push({
							codePos: code.length
						});

						if (loc.preserveTop) {
							if (!wasUnreachable) {
								code.push(buildInstr(0, 'jmp', [Int64.ofInt(-1)], popStack(1)));
							} else {
								code.push(buildInstr(0, 'jmp', [Int64.ofInt(-1)], [0]));
							}
						} else {
							code.push(buildInstr(0, 'jmp', [Int64.ofInt(-1)], [0]));
						}
						if (wasUnreachable) {
							stack = stack.slice(0, loc.stackDepth); // undwind stack
						}
						code[loc.codePos + 1].immediates[0] = Int64.ofInt(code.length);
						loc.ifBlock = false;
					}
				case End:
					{
						var loc = locations[locations.length - 1];
						locations = locations.slice(0, locations.length - 1);

						if (loc.ifBlock) {
							if (loc.preserveTop) {
								throw "if block without an else cannot yield values";
							}
							if (loc.fixupList == null)
								loc.fixupList = [];
							loc.fixupList.push({
								codePos: loc.codePos + 1
							});
						}
						if (!wasUnreachable) {
							if (((loc.preserveTop || loc.loopPreserveTop) && stack.length == loc.stackDepth + 1)
								|| (!(loc.preserveTop || loc.loopPreserveTop) && stack.length == loc.stackDepth)) {} else {
								throw 'inconsistent stack pattern: pt = ${loc.preserveTop}, lpt = ${loc.loopPreserveTop}, ls= ${stack.length}, sd = ${loc.stackDepth}';
							}
						} else {
							stack = stack.slice(0, loc.stackDepth);
						}
						fixupLocationRef(loc, wasUnreachable);
					}
				case Br:
					{
						var _label:U32 = ins.immediates[0];
						var label:Int = cast _label;

						var loc = this.locations[this.locations.length - 1 - label];

						var fixupInfo:FixupInfo = {
							codePos: code.length
						};

						var brValues:Array<TyValueID> = [0];

						if (loc.preserveTop) {
							brValues[0] = stack[stack.length - 1];
						}

						if (loc.fixupList == null)
							loc.fixupList = [];
						loc.fixupList.push(fixupInfo);
						code.push(buildInstr(0, "jmp", [-1], brValues));
						unreachableDepth = 1;
					}
				case BrIf:
					{
						var brValues = [popStack(1)[0], 0];
						var _label:U32 = ins.immediates[0];
						var label:Int = cast _label;

						var loc = this.locations[this.locations.length - 1 - label];
						var fixupInfo:FixupInfo = {
							codePos: code.length
						};

						if (loc.preserveTop) {
							brValues[1] = stack[stack.length - 1];
						}

						if (loc.fixupList == null)
							loc.fixupList = [];
						loc.fixupList.push(fixupInfo);
						code.push(buildInstr(0, "jmp_if", [-1], brValues));
					}
				case BrTable:
					{
						var _count:U32 = ins.immediates[0];
						var count:Int = cast _count;
						var brCount = count + 1;
						var brTargets:Array<I64> = [];
						var brValues = [popStack(1)[0], 0];

						var preserveTop = false;

						for (i in 0...brCount) {
							var _label:U32 = ins.immediates[0];
							var label:Int = _label;
							var loc = locations[locations.length - 1 - label];

							if (loc.preserveTop) {
								preserveTop = true;
							}

							var fixupInfo:FixupInfo = {
								codePos: code.length,
								tablePos: i
							};

							if (loc.fixupList == null)
								loc.fixupList = [];
							loc.fixupList.push(fixupInfo);

							brTargets[i] = -1;
						}

						if (preserveTop) {
							brTargets[1] = cast stack[stack.length - 1];
						}

						code.push(buildInstr(0, "jmp_table", brTargets, brValues));
						unreachableDepth = 1;
					}
				case Return:
					{
						if (stack.length != 0) {
							code.push(buildInstr(0, "return", null, popStack(1)));
						} else {
							code.push(buildInstr(0, "return", null, null));
						}
						unreachableDepth = 1;
					}
				case Call:
					{
						var _targetID:U32 = ins.immediates[0];
						var targetID:Int = cast _targetID;

						var targetSig = new FunctionSig();

						if ((targetID - callIndexOffset) >= 0) { // virtual function
							targetSig = module.functionIndexSpace[targetID - callIndexOffset].sig;
						} else { // import function
							var tyID = importTypeIDs[targetID];
							targetSig = module.types.entries[tyID];
						}

						var params = popStack(targetSig.paramTypes.length);
						var targetValueID:TyValueID = 0;

						if (targetSig.returnTypes.length > 0) {
							targetValueID = nextValueID();
						}

						code.push(buildInstr(targetValueID, "call", [Int64.ofInt(targetID)], params));
						if (targetValueID != 0) {
							pushStack(targetValueID);
						}
					}
				case CallIndirect:
					{
						var _typeID:U32 = ins.immediates[0];
						var typeID:Int = cast _typeID;
						var sig = module.types.entries[typeID];

						var targetWithParams = popStack(sig.paramTypes.length + 1);
						var targetValueID:TyValueID = 0;

						if (sig.returnTypes.length > 0) {
							targetValueID = nextValueID();
						}

						code.push(buildInstr(targetValueID, "call_indirect", [Int64.ofInt(typeID)], targetWithParams));
						if (targetValueID != 0) {
							pushStack(targetValueID);
						}
					}
				case CurrentMemory:
					{
						var retID = nextValueID();
						code.push(buildInstr(retID, op.toString(), null, null));
						pushStack(retID);
					}
				case GrowMemory:
					{
						var retID = nextValueID();
						code.push(buildInstr(retID, op.toString(), null, popStack(1)));
						pushStack(retID);
					}
				default:
					throw 'invalid opcode ${op.toString()}';
			}
		}

		fixupLocationRef(locations[0], false);
		if (stack.length != 0) {
			code.push(buildInstr(0, 'return', null, popStack(1)));
		} else {
			code.push(buildInstr(0, 'return', null, null));
		}
	}

	/**
	 * Convert to Control Flow Graph
	 * @return CFG
	 */
	public function toCFG():CFG {
		var g = new CFG();
		var insLabels = new Map<Int, Int>();
		insLabels.set(0, 0);

		var nextLabel = 1;

		for (i in 0...code.length) {
			var ins = code[0];
			switch ins.op {
				case "jmp" | "jmp_if" | "jmp_either" | "jmp_table":
					{
						for (target in ins.immediates) {
							if (insLabels.exists(Int64.toInt(target))) {
								insLabels[Int64.toInt(target)] = nextLabel;
								nextLabel++;
							}
						}

						if (insLabels.exists(i + 1)) {
							insLabels[i + 1] = nextLabel;
							nextLabel++;
						}
					}
				case "return":
					{
						if (insLabels.exists(i + 1)) {
							insLabels[i + 1] = nextLabel;
							nextLabel++;
						}
					}
			}
		}

		g.blocks = [];

		var currentBlock:BasicBlock = {
			code: [],
			jmpTargets: []
		};

		for (i in 0...code.length) {
			var ins = code[0];

			var label = insLabels.get(i);
			if (label != null) {
				if (currentBlock != null) {
					currentBlock.jmpKind = JmpUncond;
					currentBlock.jmpTargets = [label];
				}
				currentBlock = g.blocks[label];
			}

			switch ins.op {
				case "jmp":
					{
						currentBlock.jmpKind = JmpUncond;
						currentBlock.jmpTargets = [insLabels.get(Int64.toInt(ins.immediates[0]))];
						currentBlock.yieldValue = ins.values[0];
						currentBlock = null;
					}
				case "jmp_if":
					{
						currentBlock.jmpKind = JmpEither;
						currentBlock.jmpTargets = [insLabels.get(Int64.toInt(ins.immediates[0])), insLabels.get(i + 1)];
						currentBlock.jmpCond = ins.values[0];
						currentBlock.yieldValue = ins.values[1];
						currentBlock = null;
					}
				case "jmp_either":
					{
						currentBlock.jmpKind = JmpEither;
						currentBlock.jmpTargets = [
							insLabels.get(Int64.toInt(ins.immediates[0])),
							insLabels.get(Int64.toInt(ins.immediates[1]))
						];
						currentBlock.jmpCond = ins.values[0];
						currentBlock.yieldValue = ins.values[1];
						currentBlock = null;
					}
				case "jmp_table":
					{
						currentBlock.jmpKind = JmpTable;
						currentBlock.jmpTargets = [];
						for (j in 0...ins.immediates.length) {
							var imm = ins.immediates[0];
							currentBlock.jmpTargets[j] = insLabels[Int64.toInt(imm)];
						}
						currentBlock.jmpCond = ins.values[0];
						currentBlock.yieldValue = ins.values[1];
						currentBlock = null;
					}
				case "return":
					{
						currentBlock.jmpKind = JmpReturn;
						if (ins.values.length > 0) {
							currentBlock.yieldValue = ins.values[0];
						}
						currentBlock = null;
					}
				default:
					currentBlock.code.push(ins);
			}
		}

		var label = insLabels.get(code.length);
		if (label != null) {
			var lastBlock = g.blocks[label];
			if (lastBlock.jmpKind != JmpUndef) {
				throw "last block should always have an undefined jump target";
			}
			lastBlock.jmpKind = JmpReturn;
		}

		return g;
	}

	function buildInstr(target:TyValueID, op:String, immediates:Array<I64>, values:Array<TyValueID>):Instr {
		return {
			target: target,
			op: op,
			immediates: immediates,
			values: values
		};
	}

	/**
	 * FIXME: The current RegAlloc is based on wasm stack info and we probably
	 * want a real one (in addition to this) with liveness analysis.
	 * Returns the total number of registers used.
	 * https://github.com/perlin-network/life/blob/master/compiler/liveness.go
	 * @return Int
	 */
	public function regAlloc():Int {
		var regID:TyValueID = 1;

		var valueRelocs = new Map<TyValueID, TyValueID>();

		for (values in stackValueSets) {
			for (v in values) {
				valueRelocs.set(v, regID);
			}
			regID++;
		}

		for (i in 0...code.length) {
			var ins = code[i];
			if (ins.target != 0) {
				var reg = valueRelocs.get(ins.target);
				if (reg != null) {
					ins.target = reg;
				} else {
					throw "Register not found for target";
				}
			}

			for (j in 0...ins.values.length) {
				var v = ins.values[j];
				if (v != 0) {
					var reg = valueRelocs.get(v);
					if (reg != null) {
						ins.values[j] = reg;
					} else {
						throw "Register not found for value";
					}
				}
			}
		}

		var ret:Int = cast regID;
		return ret;
	}

	/**
	 * serializes a set of SSA-form instructions into a byte array
	 * for execution with an exec.VirtualMachine.
	 *
	 * Instruction encoding:
	 * Value ID (4 bytes) | Opcode (1 byte) | Operands
	 *
	 * Types are erased in the generated code.
	 * Example: float32/float64 are represented as uint32/uint64 respectively.
	 * @return Bytes
	 */
	public function serialize():Bytes {
		var buf = new BytesOutput();
		var insRelocs:Array<Int> = [];
		var reloc32Targets:Array<Int> = [];

		for (i in 0...code.length) {
			var ins = code[i];

			insRelocs[i] = buf.length;
			LittleEndian.PutUint32(buf, cast ins.target);

			switch ins.op {
				case "unreachable":
					buf.writeByte(Unreachable);
				case "select":
					{
						buf.writeByte(Select);
						for (k in 0...3) {
							LittleEndian.PutUint32(buf, cast ins.values[k]);
						}
					}

				// for int32
				case "i32.const" | "f32.const":
					{
						buf.writeByte(I32Const);
						buf.writeInt32(cast ins.immediates[0]);
					}
				case "i32.add":
					{
						buf.writeByte(I32Add);
						LittleEndian.PutUint32(buf, cast ins.values[0]);
						LittleEndian.PutUint32(buf, cast ins.values[1]);
					}
				case "i32.sub":
					{
						buf.writeByte(I32Sub);
						LittleEndian.PutUint32(buf, cast ins.values[0]);
						LittleEndian.PutUint32(buf, cast ins.values[1]);
					}
				case "i32.mul":
					{
						buf.writeByte(I32Mul);
						LittleEndian.PutUint32(buf, cast ins.values[0]);
						LittleEndian.PutUint32(buf, cast ins.values[1]);
					}
				case "i32.div_s":
					{
						buf.writeByte(I32DivS);
						LittleEndian.PutUint32(buf, cast ins.values[0]);
						LittleEndian.PutUint32(buf, cast ins.values[1]);
					}
				case "i32.div_u":
					{
						buf.writeByte(I32DivU);
						LittleEndian.PutUint32(buf, cast ins.values[0]);
						LittleEndian.PutUint32(buf, cast ins.values[1]);
					}
				case "i32.rem_s":
					{
						buf.writeByte(I32RemS);
						LittleEndian.PutUint32(buf, cast ins.values[0]);
						LittleEndian.PutUint32(buf, cast ins.values[1]);
					}
				case "i32.rem_u":
					{
						buf.writeByte(I32RemU);
						LittleEndian.PutUint32(buf, cast ins.values[0]);
						LittleEndian.PutUint32(buf, cast ins.values[1]);
					}
				case "i32.and":
					{
						buf.writeByte(I32And);
						LittleEndian.PutUint32(buf, cast ins.values[0]);
						LittleEndian.PutUint32(buf, cast ins.values[1]);
					}
				case "i32.or":
					{
						buf.writeByte(I32Or);
						LittleEndian.PutUint32(buf, cast ins.values[0]);
						LittleEndian.PutUint32(buf, cast ins.values[1]);
					}
				case "i32.xor":
					{
						buf.writeByte(I32Xor);
						LittleEndian.PutUint32(buf, cast ins.values[0]);
						LittleEndian.PutUint32(buf, cast ins.values[1]);
					}
				case "i32.shl":
					{
						buf.writeByte(I32Shl);
						LittleEndian.PutUint32(buf, cast ins.values[0]);
						LittleEndian.PutUint32(buf, cast ins.values[1]);
					}
				case "i32.shr_s":
					{
						buf.writeByte(I32ShrS);
						LittleEndian.PutUint32(buf, cast ins.values[0]);
						LittleEndian.PutUint32(buf, cast ins.values[1]);
					}
				case "i32.shr_u":
					{
						buf.writeByte(I32ShrU);
						LittleEndian.PutUint32(buf, cast ins.values[0]);
						LittleEndian.PutUint32(buf, cast ins.values[1]);
					}
				case "i32.rotl":
					{
						buf.writeByte(I32Rotl);
						LittleEndian.PutUint32(buf, cast ins.values[0]);
						LittleEndian.PutUint32(buf, cast ins.values[1]);
					}
				case "i32.rotr":
					{
						buf.writeByte(I32Rotr);
						LittleEndian.PutUint32(buf, cast ins.values[0]);
						LittleEndian.PutUint32(buf, cast ins.values[1]);
					}
				case "i32.clz":
					{
						buf.writeByte(I32Clz);
						LittleEndian.PutUint32(buf, cast ins.values[0]);
					}
				case "i32.ctz":
					{
						buf.writeByte(I32Ctz);
						LittleEndian.PutUint32(buf, cast ins.values[0]);
					}
				case "i32.popcnt":
					{
						buf.writeByte(I32PopCnt);
						LittleEndian.PutUint32(buf, cast ins.values[0]);
					}
				case "i32.eqz":
					{
						buf.writeByte(I32EqZ);
						LittleEndian.PutUint32(buf, cast ins.values[0]);
					}
				case "i32.eq":
					{
						buf.writeByte(I32Eq);
						LittleEndian.PutUint32(buf, cast ins.values[0]);
						LittleEndian.PutUint32(buf, cast ins.values[1]);
					}
				case "i32.ne":
					{
						buf.writeByte(I32Ne);
						LittleEndian.PutUint32(buf, cast ins.values[0]);
						LittleEndian.PutUint32(buf, cast ins.values[1]);
					}
				case "i32.lt_s":
					{
						buf.writeByte(I32LtS);
						LittleEndian.PutUint32(buf, cast ins.values[0]);
						LittleEndian.PutUint32(buf, cast ins.values[1]);
					}
				case "i32.lt_u":
					{
						buf.writeByte(I32LtU);
						LittleEndian.PutUint32(buf, cast ins.values[0]);
						LittleEndian.PutUint32(buf, cast ins.values[1]);
					}
				case "i32.le_s":
					{
						buf.writeByte(I32LeS);
						LittleEndian.PutUint32(buf, cast ins.values[0]);
						LittleEndian.PutUint32(buf, cast ins.values[1]);
					}
				case "i32.le_u":
					{
						buf.writeByte(I32LeU);
						LittleEndian.PutUint32(buf, cast ins.values[0]);
						LittleEndian.PutUint32(buf, cast ins.values[1]);
					}
				case "i32.gt_s":
					{
						buf.writeByte(I32GtS);
						LittleEndian.PutUint32(buf, cast ins.values[0]);
						LittleEndian.PutUint32(buf, cast ins.values[1]);
					}
				case "i32.gt_u":
					{
						buf.writeByte(I32GtU);
						LittleEndian.PutUint32(buf, cast ins.values[0]);
						LittleEndian.PutUint32(buf, cast ins.values[1]);
					}
				case "i32.ge_s":
					{
						buf.writeByte(I32GeS);
						LittleEndian.PutUint32(buf, cast ins.values[0]);
						LittleEndian.PutUint32(buf, cast ins.values[1]);
					}
				case "i32.ge_u":
					{
						buf.writeByte(I32GeU);
						LittleEndian.PutUint32(buf, cast ins.values[0]);
						LittleEndian.PutUint32(buf, cast ins.values[1]);
					}

				// for int64
				case "i64.const" | "f64.const":
					{
						buf.writeByte(I64Const);
						buf.writeDouble(FPHelper.i64ToDouble(ins.immediates[0].low, ins.immediates[0].high));
					}
				case "i64.add":
					{
						buf.writeByte(I64Add);
						LittleEndian.PutUint32(buf, cast ins.values[0]);
						LittleEndian.PutUint32(buf, cast ins.values[1]);
					}
				case "i64.sub":
					{
						buf.writeByte(I64Add);
						LittleEndian.PutUint32(buf, cast ins.values[0]);
						LittleEndian.PutUint32(buf, cast ins.values[1]);
					}
				case "i64.mul":
					{
						buf.writeByte(I64Mul);
						LittleEndian.PutUint32(buf, cast ins.values[0]);
						LittleEndian.PutUint32(buf, cast ins.values[1]);
					}
				case "i64.div_s":
					{
						buf.writeByte(I64DivS);
						LittleEndian.PutUint32(buf, cast ins.values[0]);
						LittleEndian.PutUint32(buf, cast ins.values[1]);
					}
				case "i64.div_u":
					{
						buf.writeByte(I64DivU);
						LittleEndian.PutUint32(buf, cast ins.values[0]);
						LittleEndian.PutUint32(buf, cast ins.values[1]);
					}
				case "i64.rem_s":
					{
						buf.writeByte(I64RemS);
						LittleEndian.PutUint32(buf, cast ins.values[0]);
						LittleEndian.PutUint32(buf, cast ins.values[1]);
					}
				case "i64.rem_u":
					{
						buf.writeByte(I64RemU);
						LittleEndian.PutUint32(buf, cast ins.values[0]);
						LittleEndian.PutUint32(buf, cast ins.values[1]);
					}
				case "i64.and":
					{
						buf.writeByte(I64And);
						LittleEndian.PutUint32(buf, cast ins.values[0]);
						LittleEndian.PutUint32(buf, cast ins.values[1]);
					}
				case "i64.or":
					{
						buf.writeByte(I64Or);
						LittleEndian.PutUint32(buf, cast ins.values[0]);
						LittleEndian.PutUint32(buf, cast ins.values[1]);
					}
				case "i64.xor":
					{
						buf.writeByte(I64Xor);
						LittleEndian.PutUint32(buf, cast ins.values[0]);
						LittleEndian.PutUint32(buf, cast ins.values[1]);
					}
				case "i64.shl":
					{
						buf.writeByte(I64Shl);
						LittleEndian.PutUint32(buf, cast ins.values[0]);
						LittleEndian.PutUint32(buf, cast ins.values[1]);
					}
				case "i64.shr_s":
					{
						buf.writeByte(I64ShrS);
						LittleEndian.PutUint32(buf, cast ins.values[0]);
						LittleEndian.PutUint32(buf, cast ins.values[1]);
					}
				case "i64.shr_u":
					{
						buf.writeByte(I64ShrU);
						LittleEndian.PutUint32(buf, cast ins.values[0]);
						LittleEndian.PutUint32(buf, cast ins.values[1]);
					}
				case "i64.rotl":
					{
						buf.writeByte(I64Rotl);
						LittleEndian.PutUint32(buf, cast ins.values[0]);
						LittleEndian.PutUint32(buf, cast ins.values[1]);
					}
				case "i64.rotr":
					{
						buf.writeByte(I64Rotr);
						LittleEndian.PutUint32(buf, cast ins.values[0]);
						LittleEndian.PutUint32(buf, cast ins.values[1]);
					}
				case "i64.clz":
					{
						buf.writeByte(I64Clz);
						LittleEndian.PutUint32(buf, cast ins.values[0]);
					}
				case "i64.ctz":
					{
						buf.writeByte(I64Ctz);
						LittleEndian.PutUint32(buf, cast ins.values[0]);
					}
				case "i64.popcnt":
					{
						buf.writeByte(I64PopCnt);
						LittleEndian.PutUint32(buf, cast ins.values[0]);
					}
				case "i64.eqz":
					{
						buf.writeByte(I64EqZ);
						LittleEndian.PutUint32(buf, cast ins.values[0]);
					}
				case "i64.eq":
					{
						buf.writeByte(I64Eq);
						LittleEndian.PutUint32(buf, cast ins.values[0]);
						LittleEndian.PutUint32(buf, cast ins.values[1]);
					}
				case "i64.ne":
					{
						buf.writeByte(I64Ne);
						LittleEndian.PutUint32(buf, cast ins.values[0]);
						LittleEndian.PutUint32(buf, cast ins.values[1]);
					}
				case "i64.lt_s":
					{
						buf.writeByte(I64LtS);
						LittleEndian.PutUint32(buf, cast ins.values[0]);
						LittleEndian.PutUint32(buf, cast ins.values[1]);
					}
				case "i64.lt_u":
					{
						buf.writeByte(I64LtU);
						LittleEndian.PutUint32(buf, cast ins.values[0]);
						LittleEndian.PutUint32(buf, cast ins.values[1]);
					}
				case "i64.le_s":
					{
						buf.writeByte(I64LeS);
						LittleEndian.PutUint32(buf, cast ins.values[0]);
						LittleEndian.PutUint32(buf, cast ins.values[1]);
					}
				case "i64.le_u":
					{
						buf.writeByte(I64LeU);
						LittleEndian.PutUint32(buf, cast ins.values[0]);
						LittleEndian.PutUint32(buf, cast ins.values[1]);
					}
				case "i64.gt_s":
					{
						buf.writeByte(I64GtS);
						LittleEndian.PutUint32(buf, cast ins.values[0]);
						LittleEndian.PutUint32(buf, cast ins.values[1]);
					}
				case "i64.gt_u":
					{
						buf.writeByte(I64GtU);
						LittleEndian.PutUint32(buf, cast ins.values[0]);
						LittleEndian.PutUint32(buf, cast ins.values[1]);
					}
				case "i64.ge_s":
					{
						buf.writeByte(I64GeS);
						LittleEndian.PutUint32(buf, cast ins.values[0]);
						LittleEndian.PutUint32(buf, cast ins.values[1]);
					}
				case "i64.ge_u":
					{
						buf.writeByte(I64GeU);
						LittleEndian.PutUint32(buf, cast ins.values[0]);
						LittleEndian.PutUint32(buf, cast ins.values[1]);
					}

				// for f32
				case "f32.add":
					{
						buf.writeByte(F32Add);
						LittleEndian.PutUint32(buf, cast ins.values[0]);
						LittleEndian.PutUint32(buf, cast ins.values[1]);
					}
				case "f32.sub":
					{
						buf.writeByte(F32Sub);
						LittleEndian.PutUint32(buf, cast ins.values[0]);
						LittleEndian.PutUint32(buf, cast ins.values[1]);
					}
				case "f32.mul":
					{
						buf.writeByte(F32Mul);
						LittleEndian.PutUint32(buf, cast ins.values[0]);
						LittleEndian.PutUint32(buf, cast ins.values[1]);
					}
				case "f32.div":
					{
						buf.writeByte(F32Div);
						LittleEndian.PutUint32(buf, cast ins.values[0]);
						LittleEndian.PutUint32(buf, cast ins.values[1]);
					}
				case "f32.sqrt":
					{
						buf.writeByte(F32Sqrt);
						LittleEndian.PutUint32(buf, cast ins.values[0]);
					}
				case "f32.min":
					{
						buf.writeByte(F32Min);
						LittleEndian.PutUint32(buf, cast ins.values[0]);
						LittleEndian.PutUint32(buf, cast ins.values[1]);
					}
				case "f32.max":
					{
						buf.writeByte(F32Max);
						LittleEndian.PutUint32(buf, cast ins.values[0]);
						LittleEndian.PutUint32(buf, cast ins.values[1]);
					}
				case "f32.ceil":
					{
						buf.writeByte(F32Ceil);
						LittleEndian.PutUint32(buf, cast ins.values[0]);
					}
				case "f32.floor":
					{
						buf.writeByte(F32Floor);
						LittleEndian.PutUint32(buf, cast ins.values[0]);
					}
				case "f32.trunc":
					{
						buf.writeByte(F32Trunc);
						LittleEndian.PutUint32(buf, cast ins.values[0]);
					}
				case "f32.nearest":
					{
						buf.writeByte(F32Nearest);
						LittleEndian.PutUint32(buf, cast ins.values[0]);
					}
				case "f32.abs":
					{
						buf.writeByte(F32Abs);
						LittleEndian.PutUint32(buf, cast ins.values[0]);
					}
				case "f32.neg":
					{
						buf.writeByte(F32Neg);
						LittleEndian.PutUint32(buf, cast ins.values[0]);
					}
				case "f32.copysign":
					{
						buf.writeByte(F32CopySign);
						LittleEndian.PutUint32(buf, cast ins.values[0]);
						LittleEndian.PutUint32(buf, cast ins.values[1]);
					}
				case "f32.eq":
					{
						buf.writeByte(F32Eq);
						LittleEndian.PutUint32(buf, cast ins.values[0]);
						LittleEndian.PutUint32(buf, cast ins.values[1]);
					}
				case "f32.ne":
					{
						buf.writeByte(F32Eq);
						LittleEndian.PutUint32(buf, cast ins.values[0]);
						LittleEndian.PutUint32(buf, cast ins.values[1]);
					}
				case "f32.lt":
					{
						buf.writeByte(F32Lt);
						LittleEndian.PutUint32(buf, cast ins.values[0]);
						LittleEndian.PutUint32(buf, cast ins.values[1]);
					}
				case "f32.le":
					{
						buf.writeByte(F32Le);
						LittleEndian.PutUint32(buf, cast ins.values[0]);
						LittleEndian.PutUint32(buf, cast ins.values[1]);
					}
				case "f32.gt":
					{
						buf.writeByte(F32Gt);
						LittleEndian.PutUint32(buf, cast ins.values[0]);
						LittleEndian.PutUint32(buf, cast ins.values[1]);
					}
				case "f32.Ge":
					{
						buf.writeByte(F32Ge);
						LittleEndian.PutUint32(buf, cast ins.values[0]);
						LittleEndian.PutUint32(buf, cast ins.values[1]);
					}

				case "i32.wrap/i64":
					{
						buf.writeByte(I32WrapI64);
						LittleEndian.PutUint32(buf, cast ins.values[0]);
					}
				case "i32.trunc_s/f32":
					{
						buf.writeByte(I32TruncSF32);
						LittleEndian.PutUint32(buf, cast ins.values[0]);
					}
				case "i32.trunc_s/f64":
					{
						buf.writeByte(I32TruncSF64);
						LittleEndian.PutUint32(buf, cast ins.values[0]);
					}
				case "i32.trunc_u/f32":
					{
						buf.writeByte(I32TruncUF32);
						LittleEndian.PutUint32(buf, cast ins.values[0]);
					}
				case "i32.trunc_u/f64":
					{
						buf.writeByte(I32TruncUF64);
						LittleEndian.PutUint32(buf, cast ins.values[0]);
					}
				case "i64.trunc_s/f32":
					{
						buf.writeByte(I64TruncSF32);
						LittleEndian.PutUint32(buf, cast ins.values[0]);
					}
				case "i64.trunc_s/f64":
					{
						buf.writeByte(I64TruncSF64);
						LittleEndian.PutUint32(buf, cast ins.values[0]);
					}
				case "i64.trunc_u/f32":
					{
						buf.writeByte(I64TruncUF32);
						LittleEndian.PutUint32(buf, cast ins.values[0]);
					}
				case "i64.trunc_u/f64":
					{
						buf.writeByte(I64TruncUF64);
						LittleEndian.PutUint32(buf, cast ins.values[0]);
					}
				case "i64.extend_u/i32":
					{
						buf.writeByte(I64ExtendUI32);
						LittleEndian.PutUint32(buf, cast ins.values[0]);
					}
				case "i64.extend_s/i32":
					{
						buf.writeByte(I64ExtendSI32);
						LittleEndian.PutUint32(buf, cast ins.values[0]);
					}
				case "f32.demote/f64":
					{
						buf.writeByte(F32DemoteF64);
						LittleEndian.PutUint32(buf, cast ins.values[0]);
					}
				case "f64.promote/f32":
					{
						buf.writeByte(F64PromoteF32);
						LittleEndian.PutUint32(buf, cast ins.values[0]);
					}
				case "f64.convert_s/i32":
					{
						buf.writeByte(F64ConvertSI32);
						LittleEndian.PutUint32(buf, cast ins.values[0]);
					}
				case "f64.convert_u/i32":
					{
						buf.writeByte(F64ConvertUI32);
						LittleEndian.PutUint32(buf, cast ins.values[0]);
					}
				case "f64.convert_s/i64":
					{
						buf.writeByte(F64ConvertSI64);
						LittleEndian.PutUint32(buf, cast ins.values[0]);
					}
				case "f64.convert_u/i64":
					{
						buf.writeByte(F64ConvertUI64);
						LittleEndian.PutUint32(buf, cast ins.values[0]);
					}
				case "f32.convert_s/i32":
					{
						buf.writeByte(F32ConvertSI32);
						LittleEndian.PutUint32(buf, cast ins.values[0]);
					}
				case "f32.convert_u/i32":
					{
						buf.writeByte(F32ConvertUI32);
						LittleEndian.PutUint32(buf, cast ins.values[0]);
					}
				case "f32.convert_s/i64":
					{
						buf.writeByte(F32ConvertSI64);
						LittleEndian.PutUint32(buf, cast ins.values[0]);
					}
				case "f32.convert_u/i64":
					{
						buf.writeByte(F32ConvertUI64);
						LittleEndian.PutUint32(buf, cast ins.values[0]);
					}
				case "i32.reinterpret/f32" | "i64.reinterpret/f64" | "f32.reinterpret/i32" | "f64.reinterpret/i64":
					{
						buf.writeByte(Nop);
					}

				// Memory
				case "i32.load" | "f32.load":
					{
						buf.writeByte(I32Load);

						LittleEndian.PutUint32(buf, cast ins.immediates[0]); // Memory alignment flags
						LittleEndian.PutUint32(buf, cast ins.immediates[1]); // Memory offset
						LittleEndian.PutUint32(buf, cast ins.values[0]); // Memory base address
					}
				case "i32.load8_s":
					{
						buf.writeByte(I32Load8S);

						LittleEndian.PutUint32(buf, cast ins.immediates[0]); // Memory alignment flags
						LittleEndian.PutUint32(buf, cast ins.immediates[1]); // Memory offset
						LittleEndian.PutUint32(buf, cast ins.values[0]); // Memory base address
					}
				case "i32.load16_s":
					{
						buf.writeByte(I32Load16S);

						LittleEndian.PutUint32(buf, cast ins.immediates[0]); // Memory alignment flags
						LittleEndian.PutUint32(buf, cast ins.immediates[1]); // Memory offset
						LittleEndian.PutUint32(buf, cast ins.values[0]); // Memory base address
					}
				case "i64.load8_s":
					{
						buf.writeByte(I64Load8S);

						LittleEndian.PutUint32(buf, cast ins.immediates[0]); // Memory alignment flags
						LittleEndian.PutUint32(buf, cast ins.immediates[1]); // Memory offset
						LittleEndian.PutUint32(buf, cast ins.values[0]); // Memory base address
					}
				case "i64.load16_s":
					{
						buf.writeByte(I64Load16S);

						LittleEndian.PutUint32(buf, cast ins.immediates[0]); // Memory alignment flags
						LittleEndian.PutUint32(buf, cast ins.immediates[1]); // Memory offset
						LittleEndian.PutUint32(buf, cast ins.values[0]); // Memory base address
					}
				case "i64.load32_s":
					{
						buf.writeByte(I64Load32S);

						LittleEndian.PutUint32(buf, cast ins.immediates[0]); // Memory alignment flags
						LittleEndian.PutUint32(buf, cast ins.immediates[1]); // Memory offset
						LittleEndian.PutUint32(buf, cast ins.values[0]); // Memory base address
					}
				case "i32.load8_u":
					{
						buf.writeByte(I32Load8U);

						LittleEndian.PutUint32(buf, cast ins.immediates[0]); // Memory alignment flags
						LittleEndian.PutUint32(buf, cast ins.immediates[1]); // Memory offset
						LittleEndian.PutUint32(buf, cast ins.values[0]); // Memory base address
					}
				case "i32.load16_u":
					{
						buf.writeByte(I32Load16U);

						LittleEndian.PutUint32(buf, cast ins.immediates[0]); // Memory alignment flags
						LittleEndian.PutUint32(buf, cast ins.immediates[1]); // Memory offset
						LittleEndian.PutUint32(buf, cast ins.values[0]); // Memory base address
					}
				case "i64.load8_u":
					{
						buf.writeByte(I64Load8U);

						LittleEndian.PutUint32(buf, cast ins.immediates[0]); // Memory alignment flags
						LittleEndian.PutUint32(buf, cast ins.immediates[1]); // Memory offset
						LittleEndian.PutUint32(buf, cast ins.values[0]); // Memory base address
					}
				case "i64.load16_u":
					{
						buf.writeByte(I64Load16U);

						LittleEndian.PutUint32(buf, cast ins.immediates[0]); // Memory alignment flags
						LittleEndian.PutUint32(buf, cast ins.immediates[1]); // Memory offset
						LittleEndian.PutUint32(buf, cast ins.values[0]); // Memory base address
					}
				case "i64.load32_u":
					{
						buf.writeByte(I64Load32U);

						LittleEndian.PutUint32(buf, cast ins.immediates[0]); // Memory alignment flags
						LittleEndian.PutUint32(buf, cast ins.immediates[1]); // Memory offset
						LittleEndian.PutUint32(buf, cast ins.values[0]); // Memory base address
					}
				case "i64.load" | "f64.load":
					{
						buf.writeByte(I64Load);

						LittleEndian.PutUint32(buf, cast ins.immediates[0]); // Memory alignment flags
						LittleEndian.PutUint32(buf, cast ins.immediates[1]); // Memory offset
						LittleEndian.PutUint32(buf, cast ins.values[0]); // Memory base address
					}
				case "i32.store" | "f32.store":
					{
						buf.writeByte(I32Store);

						LittleEndian.PutUint32(buf, cast ins.immediates[0]); // Memory alignment flags
						LittleEndian.PutUint32(buf, cast ins.immediates[1]); // Memory offset
						LittleEndian.PutUint32(buf, cast ins.values[0]); // Memory base address
						LittleEndian.PutUint32(buf, cast ins.values[1]); // Address of value to store
					}
				case "i32.store8":
					{
						buf.writeByte(I32Store8);

						LittleEndian.PutUint32(buf, cast ins.immediates[0]); // Memory alignment flags
						LittleEndian.PutUint32(buf, cast ins.immediates[1]); // Memory offset
						LittleEndian.PutUint32(buf, cast ins.values[0]); // Memory base address
						LittleEndian.PutUint32(buf, cast ins.values[1]); // Address of value to store
					}
				case "i32.store16":
					{
						buf.writeByte(I32Store16);

						LittleEndian.PutUint32(buf, cast ins.immediates[0]); // Memory alignment flags
						LittleEndian.PutUint32(buf, cast ins.immediates[1]); // Memory offset
						LittleEndian.PutUint32(buf, cast ins.values[0]); // Memory base address
						LittleEndian.PutUint32(buf, cast ins.values[1]); // Address of value to store
					}
				case "i64.store8":
					{
						buf.writeByte(I64Store8);

						LittleEndian.PutUint32(buf, cast ins.immediates[0]); // Memory alignment flags
						LittleEndian.PutUint32(buf, cast ins.immediates[1]); // Memory offset
						LittleEndian.PutUint32(buf, cast ins.values[0]); // Memory base address
						LittleEndian.PutUint32(buf, cast ins.values[1]); // Address of value to store
					}
				case "i64.store16":
					{
						buf.writeByte(I64Store16);

						LittleEndian.PutUint32(buf, cast ins.immediates[0]); // Memory alignment flags
						LittleEndian.PutUint32(buf, cast ins.immediates[1]); // Memory offset
						LittleEndian.PutUint32(buf, cast ins.values[0]); // Memory base address
						LittleEndian.PutUint32(buf, cast ins.values[1]); // Address of value to store
					}
				case "i64.store32":
					{
						buf.writeByte(I64Store32);

						LittleEndian.PutUint32(buf, cast ins.immediates[0]); // Memory alignment flags
						LittleEndian.PutUint32(buf, cast ins.immediates[1]); // Memory offset
						LittleEndian.PutUint32(buf, cast ins.values[0]); // Memory base address
						LittleEndian.PutUint32(buf, cast ins.values[1]); // Address of value to store
					}
				case "i64.store" | "f64.store":
					{
						buf.writeByte(I64Store);

						LittleEndian.PutUint32(buf, cast ins.immediates[0]); // Memory alignment flags
						LittleEndian.PutUint32(buf, cast ins.immediates[1]); // Memory offset
						LittleEndian.PutUint32(buf, cast ins.values[0]); // Memory base address
						LittleEndian.PutUint32(buf, cast ins.values[1]); // Address of value to store
					}
				case "jmp":
					{
						buf.writeByte(Jmp);

						reloc32Targets.push(buf.length);
						LittleEndian.PutUint32(buf, cast ins.immediates[0]);
						LittleEndian.PutUint32(buf, cast ins.values[0]);
					}
				case "jmp_if":
					{
						buf.writeByte(JmpIf);

						reloc32Targets.push(buf.length);
						LittleEndian.PutUint32(buf, cast ins.immediates[0]);

						LittleEndian.PutUint32(buf, cast ins.values[0]);
						LittleEndian.PutUint32(buf, cast ins.values[1]);
					}
				case "jmp_either":
					{
						buf.writeByte(JmpEither);

						reloc32Targets.push(buf.length);
						LittleEndian.PutUint32(buf, cast ins.immediates[0]);
						reloc32Targets.push(buf.length);
						LittleEndian.PutUint32(buf, cast ins.immediates[1]);

						LittleEndian.PutUint32(buf, cast ins.values[0]);
						LittleEndian.PutUint32(buf, cast ins.values[1]);
					}
				case "jmp_table":
					{
						buf.writeByte(JmpTable);
						var imm = ins.immediates.length - 1;
						LittleEndian.PutUint32(buf, cast imm);

						for (v in ins.immediates) {
							reloc32Targets.push(buf.length);
							LittleEndian.PutUint32(buf, cast v);
						}

						LittleEndian.PutUint32(buf, cast ins.values[0]);
						LittleEndian.PutUint32(buf, cast ins.values[1]);
					}
				case "phi":
					{
						buf.writeByte(Phi);
					}
				case "return":
					{
						if (ins.values.length != 0) {
							buf.writeByte(ReturnValue);
							LittleEndian.PutUint32(buf, cast ins.values[0]);
						} else {
							buf.writeByte(ReturnVoid);
						}
					}
				case "get_local":
					{
						buf.writeByte(GetLocal);
						LittleEndian.PutUint32(buf, cast ins.immediates[0]);
					}
				case "set_local":
					{
						buf.writeByte(SetLocal);
						LittleEndian.PutUint32(buf, cast ins.immediates[0]);
						LittleEndian.PutUint32(buf, cast ins.values[0]);
					}
				case "call":
					{
						buf.writeByte(Call);
						LittleEndian.PutUint32(buf, cast ins.immediates[0]);
						LittleEndian.PutUint32(buf, cast ins.values.length);
						for (v in ins.values) {
							LittleEndian.PutUint32(buf, cast v);
						}
					}
				case "call_indirect":
					{
						buf.writeByte(CallIndirect);
						LittleEndian.PutUint32(buf, cast ins.immediates[0]);
						LittleEndian.PutUint32(buf, cast ins.values.length);
						for (v in ins.values) {
							LittleEndian.PutUint32(buf, cast v);
						}
					}
				case "current_memory":
					{
						buf.writeByte(CurrentMemory);
					}
				case "grow_memory":
					{
						buf.writeByte(GrowMemory);
						LittleEndian.PutUint32(buf, cast ins.values[0]);
					}
				case "fp_disabled_error":
					{
						buf.writeByte(FPDisabledError);
					}
				default:
					throw ins.op;
			}
		}

		var ret = buf.getBytes();
		for (t in reloc32Targets) {
			var insPos = LittleEndian.Uint32(ret.sub(t, t + 4));
			var bo = new BytesOutput();
			LittleEndian.PutUint32(bo, cast insRelocs[cast insPos]);
			ret.blit(t, bo.getBytes(), 0, 4);
		}

		return ret;
	}
}
