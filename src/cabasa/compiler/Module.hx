package cabasa.compiler;

import cabasa.compiler.ssa.FunctionCompiler;
import wasp.disasm.Disassembly;
import wasp.io.*;
import wasp.imports.*;
import binary128.internal.Leb128;
import haxe.io.*;
import wasp.types.*;

using cabasa.compiler.Opcodes;

typedef InterpreterCode = {
	numRegs:Int,
	numParams:Int,
	numLocals:Int,
	numReturns:Int,
	bytes:Bytes,
	?JITInfo:Dynamic,
	?JITDone:Bool
}

class Module {
	public var base:wasp.Module;
	public var functionNames:Map<Int, String>;
	public var disableFloatingPoints:Bool;

	public function new() {
		functionNames = new Map<Int, String>();
	}

	public static function load(raw:Bytes):Module {
		var reader = new BytesInput(raw);

		var m = wasp.Module.read(reader, null);

		/**
		 * Todo: validate
		 */

		var functionNames = new Map<Int, String>();

		for (sec in m.customs) {
			if (sec.name == "name") {
				var r = new BytesInput(sec.getRawSection().bytes);
				while (true) {
					var ty = Leb128.readUint32(r);
					if (ty != 1)
						break;

					var payloadLen = Leb128.readUint32(r);
					var data = Bytes.alloc(payloadLen);
					var n = r.readBytes(data, 0, payloadLen);

					if (n != data.length) {
						throw "len mismatch";
					} {
						var r = new BytesInput(data);
						while (true) {
							try {
								var count:U32 = Leb128.readUint32(r);
								var _count:Int = count;
								for (i in 0..._count) {
									try {
										var index:U32 = Leb128.readUint32(r);
										var nameLen = Leb128.readUint32(r);
										var name = Bytes.alloc(nameLen);
										var n = r.readBytes(name, 0, nameLen);
										if (n != name.length) {
											throw "len mismatch";
										}
										var _index:Int = index;
										functionNames.set(_index, name.toString());
									} catch (e:Dynamic) {
										throw e;
									}
								}
							} catch (e:Dynamic) {
								break;
							}
						}
					}
				}
			}
		}
		var ret = new Module();
		ret.base = m;
		ret.functionNames = functionNames;
		return null;
	}

	/**
	 * Todo
	 */
	public function compileNative() {}

	/**
	 * Compile module for interpreter
	 */
	public function compileInterp():Array<InterpreterCode> {
		var ret:Array<InterpreterCode> = [];
		var importTypeIDs:Array<Int> = [];

		if (base.import_ != null) {
			var j = 0;
			for (i in 0...base.import_.entries.length) {
				var e = base.import_.entries[i];
				if (e.type.kind() == ExternalFunction) {
					continue;
				}

				var tyID = cast(e.type, FuncImport).type;
				var ty = base.types.entries[tyID];

				var buf = new BytesOutput();

				LittleEndian.PutUint32(buf, 1); // value ID
				buf.writeByte(InvokeImport);
				buf.writeByte(j);

				LittleEndian.PutUint32(buf, 0);

				if (ty.returnTypes.length != 0) {
					buf.writeByte(ReturnValue);
					LittleEndian.PutUint32(buf, 1);
				} else {
					buf.writeByte(ReturnVoid);
				}

				var code = buf.getBytes();

				ret.push({
					numRegs: 2,
					numParams: ty.paramTypes.length,
					numLocals: 0,
					numReturns: ty.returnTypes.length,
					bytes: code
				});

				importTypeIDs.push(tyID);
				j++;
			}
		}

		var numFuncImports = ret.length;
		ret.resize(base.functionIndexSpace.length);

		for (i in 0...base.functionIndexSpace.length) {
			var f = base.functionIndexSpace[i];

			var d = new Disassembly(f, base);
			var compiler = new FunctionCompiler(base, d);
			compiler.callIndexOffset = numFuncImports;
			compiler.compile(importTypeIDs);
			if (disableFloatingPoints) {
				compiler.filterFloatingPoint();
			}

			var numRegs = compiler.regAlloc();
			var numLocals = 0;
			for (v in f.body.locals) {
				var count:Int = v.count;
				numLocals += count;
			}
			ret[numFuncImports + i] = {
				numRegs: numRegs,
				numParams: f.sig.paramTypes.length,
				numLocals: numLocals,
				numReturns: f.sig.returnTypes.length,
				bytes: compiler.serialize()
			};
		}

		return ret;
	}
}
