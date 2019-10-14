package cabasa.exec;

import haxe.Int64;
import cabasa.compiler.Opcodes;
import wasp.io.LittleEndian;
import wasp.types.External;
import wasp.io.Read;
import binary128.internal.Leb128;
import wasp.sections.Tables;
import wasp.types.Table;
import wasp.types.ResizableLimits;
import wasp.types.Memory;
import wasp.sections.Memories;
import hex.log.HexLog;
import haxe.io.*;
import cabasa.compiler.Module;
import cabasa.bits.Op.*;

/**
 * WebAssemble virtual machine
 */
class VM {
	/**
	 * DefaultCallStackSize is the default call stack size.
	 */
	public static inline var DefaultCallStackSize = 512;

	/**
	 * DefaultPageSize is the linear memory page size.
	 */
	public static inline var DefaultPageSize = 65536;

	/**
	 * JITCodeSizeThreshold is the lower-bound code size threshold for the JIT compiler.
	 */
	public static inline var JITCodeSizeThreshold = 30;

	public var module:Module;
	public var config:VMConfig;
	public var functionCode:Array<InterpreterCode>;
	public var functionImports:Array<FunctionImportInfo>;
	public var callStack:Array<Frame>;
	public var currentFrame:Int;
	public var table:Array<U32>;
	public var globals:Array<I64>;
	public var memory:Bytes;
	public var numValueSlots:Int;
	public var yielded:I64;
	public var insideExecute:Bool;
	public var delegate:() -> Void;
	public var exited:Bool;
	public var exitErr:Dynamic;
	public var returnValue:I64;
	public var importResolver:ImportResolver;
	public var AOTService:AOTService;
	public var stackTrace:String;

	/**
	 * Instantiates a virtual machine for a given WebAssembly module, with
	 * specific execution options specified under a VMConfig, and a WebAssembly module import
	 * resolver.
	 * @param input
	 * @param config
	 * @param importResolver
	 */
	public function new(code:Bytes, config:VMConfig, importResolver:ImportResolver) {
		if (config.enableJIT != null && config.enableJIT) {
			HexLog.warn("Warning: JIT support is removed.");
		}

		// Load the module from code
		var module = Module.load(code);

		// set if we should disable floatingpoint
		module.disableFloatingPoints = config.disableFloatingPoint;

		var functionCode = module.compileInterp();

		var table:Array<U32> = [];
		var globals:Array<I64> = [];
		var funcImports:Array<FunctionImportInfo> = [];

		if (module.base.import_ != null && importResolver != null) {
			for (imp in module.base.import_.entries) {
				switch imp.type.kind() {
					case ExternalFunction:
						{
							funcImports.push({
								moduleName: imp.moduleName,
								fieldName: imp.fieldName,
								func: null // deferred
							});
						}
					case ExternalGlobal:
						{
							globals.push(importResolver.resolveGlobal(imp.moduleName, imp.fieldName));
						}
					case ExternalMemory:
						{
							if (module.base.memory != null && module.base.memory.entries.length > 0) {
								throw "cannot import another memory while we already have one";
							}
							module.base.memory = new Memories();
							var mem = new Memory();
							mem.limits = new ResizableLimits(config.defaultMemoryPages);
							module.base.memory.entries = [mem];
						}
					case ExternalTable:
						{
							if (module.base.table != null && module.base.table.entries.length > 0) {
								throw "cannot import another table while we already have one";
							}
							module.base.table = new Tables();
							var tab = new Table();
							tab.limits = new ResizableLimits(config.defaultMemoryPages);
							module.base.table.entries = [tab];
						}
					default:
						throw 'import kind not supported: ${imp.type.kind()}';
				}
			}
		}

		// load globale entries
		for (entry in module.base.globalIndexSpace) {
			globals.push(execInitExpr(entry.init, globals));
		}

		// Populate table elements.
		if (module.base.table != null && module.base.table.entries.length > 0) {
			var t = module.base.table.entries[0];
			var ini:Int = cast t.limits.initial;
			if (config.maxTableSize != 0 && ini > config.maxTableSize) {
				throw "max table size exceeded";
			}

			var table:Array<U32> = [];
			for (i in 0...ini) {
				table[i] = 0xffffffff;
			}

			if (module.base.elements != null && module.base.elements.entries.length > 0) {
				for (e in module.base.elements.entries) {
					var offset:Int = haxe.Int64.toInt(execInitExpr(e.offset, globals));
					// copy elements to table from offset
					table.splice(offset, e.elems.length);
					for (i in e.elems) {
						table.insert(offset++, i);
					}
				}
			}
		}

		// Load linear memory.
		var memory = Bytes.alloc(0);
		if (module.base.memory != null && module.base.memory.entries.length > 0) {
			var initialLimit:Int = cast module.base.memory.entries[0].limits.initial;
			if (config.maxMemoryPages != 0 && initialLimit > config.maxMemoryPages) {
				throw "max memory exceeded";
			}

			var capacity = initialLimit * DefaultPageSize;

			// Initialize empty memory.
			memory = Bytes.alloc(capacity);
			var b = new BytesBuffer();
			for (i in 0...capacity) {
				b.addByte(0);
			}
			memory = b.getBytes();

			if (module.base.data != null && module.base.data.entries.length > 0) {
				for (e in module.base.data.entries) {
					var offset:Int = haxe.Int64.toInt(execInitExpr(e.offset, globals));
					memory.blit(offset, e.data, 0, e.data.length);
				}
			}
		}

		this.module = module;
		this.config = config;
		this.functionCode = functionCode;
		this.functionImports = funcImports;
		this.callStack = [];
		this.currentFrame = -1;
		this.table = table;
		this.globals = globals;
		this.memory = memory;
		this.exited = true;
		this.importResolver = importResolver;
	}

	public function setAOTService(s:AOTService) {
		this.AOTService = s;
	}

	public static function execInitExpr(expr:Bytes, globals:Array<I64>):I64 {
		var stack:Array<I64> = [];
		var r = new BytesInput(expr);

		while (true) {
			try {
				var b:wasp.operators.Ops = r.readByte();

				switch b {
					case I32Const:
						{
							var i = Leb128.readInt32(r);
							#if !cs
							stack.push(cast i);
							#else
							stack.push(untyped __cs__('System.Convert.ToInt64({0})', i));
							#end
						}
					case I64Const:
						{
							var i = Leb128.readInt64(r);
							stack.push(i);
						}
					case F32Const:
						{
							var i = Read.U32(r);
							#if !cs
							stack.push(cast i);
							#else
							stack.push(untyped __cs__('System.Convert.ToInt64({0})', i));
							#end
						}
					case F64Const:
						{
							var i = Read.U64(r);
							#if !cs
							stack.push(cast i);
							#else
							stack.push(untyped __cs__('System.Convert.ToInt64({0})', i));
							#end
						}
					case GetGlobal:
						{
							var i = Leb128.readInt32(r);
							#if !cs
							stack.push(globals[cast i]);
							#else
							stack.push(globals[i]);
							#end
						}
					case End:
						{
							break;
						}
					default:
						{
							throw "invalid opcode in init expr";
						}
				}
			} catch (e:Dynamic) {
				if (Std.is(e, Eof)) {
					break;
				} else {
					throw e;
				}
			}
		}

		return stack[stack.length - 1];
	}

	/**
	 * Returns the current frame.
	 * @return Frame
	 */
	public function getCurrentFrame():Frame {
		if (config.maxCallStackDepth != 0 && currentFrame >= config.maxCallStackDepth) {
			throw "max call stack depth exceeded";
		}
		if (currentFrame >= callStack.length) {
			throw "call stack overflow";
		}

		return callStack[currentFrame];
	}

	function getExport(key:String, kind:External) {
		if (module.base.export == null) {
			return -1;
		}
		if (module.base.export.entries.exists(key)) {
			var entry = module.base.export.entries.get(key);
			if (entry.kind != kind) {
				return -1;
			}

			return entry.index;
		}

		return -1;
	}

	/**
	 * Returns the global export with the given name.
	 * @param key
	 */
	public function getGlobalExport(key:String) {
		return getExport(key, ExternalGlobal);
	}

	/**
	 * Returns the function export with the given name.
	 * @param key
	 */
	public function getFunctionExport(key:String) {
		return getExport(key, ExternalFunction);
	}

	/**
	 * Prints the entire VM stack trace for debugging.
	 */
	public function printStackTrace() {
		Sys.println("--- Begin stack trace ---");
		var i = currentFrame;
		while (i >= 0) {
			var functionID = callStack[i].functionID;
			Sys.println('<${i}> [${functionID}] ${module.functionNames[functionID]}');
			i--;
		}
		Sys.println("--- End stack trace ---");
	}

	/**
	 * Initializes the first call frame.
	 * @param functionID
	 * @param params
	 */
	public function ignite(functionID:Int, params:Array<I64>) {
		if (exitErr != null) {
			throw "last execution exited with error; cannot ignite.";
		}
		if (currentFrame != -1) {
			throw "call stack not empty; cannot ignite.";
		}

		var code = functionCode[functionID];
		if (code.numParams != params.length) {
			throw "param count mismatch";
		}

		exited = false;

		currentFrame++;

		var frame = getCurrentFrame();
		frame.init(this, functionID, code);

		frame.locals = params.copy();
	}

	/**
	 * Starts the virtual machines main instruction processing loop.
	 * This function may return at any point and is guaranteed to return
	 * at least once every 10000 instructions. Caller is responsible for
	 * detecting VM status in a loop.
	 */
	public function execute() {
		// Todo: execute
		if (exited) {
			throw "attempting to execute an exited vm";
		}

		if (delegate != null) {
			throw "delegate not cleared";
		}

		if (insideExecute) {
			throw "vm execution is not re-entrant";
		}

		insideExecute = true;

		try {
			var frame = getCurrentFrame();
			while (true) {
				var valueID:Int = cast LittleEndian.Uint32(frame.code.sub(frame.IP, frame.IP + 4));
				var ins:Opcodes = frame.code.get(frame.IP + 4);
				frame.IP += 5;

				switch ins {
					case Nop:
					case Unreachable:
						throw "wasm: unreachable executed";
					case Select:
						{
							var a = frame.regs[cast LittleEndian.Uint32(frame.code.sub(frame.IP, frame.IP + 4))];
							var b = frame.regs[cast LittleEndian.Uint32(frame.code.sub(frame.IP + 4, frame.IP + 8))];
							var c:I32 = cast frame.regs[cast LittleEndian.Uint32(frame.code.sub(frame.IP + 8, frame.IP + 12))];
							frame.IP += 12;

							if (c != 0) {
								frame.regs[valueID] = a;
							} else {
								frame.regs[valueID] = b;
							}
						}
					case I32Const:
						{
							var val = LittleEndian.Uint32(frame.code.sub(frame.IP, frame.IP + 4));
							frame.IP += 4;
							frame.regs[valueID] = Int64.ofInt(val);
						}
					case I32Add:
						{
							var a:I32 = cast frame.regs[LittleEndian.Uint32(frame.code.sub(frame.IP, frame.IP + 4))];
							var b:I32 = cast frame.regs[LittleEndian.Uint32(frame.code.sub(frame.IP + 4, frame.IP + 8))];
							frame.IP += 8;
							var val:I32 = a + b;
							frame.regs[valueID] = Int64.ofInt(val);
						}
					case I32Sub:
						{
							var a:I32 = cast frame.regs[LittleEndian.Uint32(frame.code.sub(frame.IP, frame.IP + 4))];
							var b:I32 = cast frame.regs[LittleEndian.Uint32(frame.code.sub(frame.IP + 4, frame.IP + 8))];
							frame.IP += 8;
							var val:I32 = a - b;
							frame.regs[valueID] = Int64.ofInt(val);
						}
					case I32Mul:
						{
							var a:I32 = cast frame.regs[LittleEndian.Uint32(frame.code.sub(frame.IP, frame.IP + 4))];
							var b:I32 = cast frame.regs[LittleEndian.Uint32(frame.code.sub(frame.IP + 4, frame.IP + 8))];
							frame.IP += 8;
							var val:I32 = a * b;
							frame.regs[valueID] = Int64.ofInt(val);
						}
					case I32DivS:
						{
							var a:I32 = cast frame.regs[LittleEndian.Uint32(frame.code.sub(frame.IP, frame.IP + 4))];
							var b:I32 = cast frame.regs[LittleEndian.Uint32(frame.code.sub(frame.IP + 4, frame.IP + 8))];

							if (b == 0)
								throw "integer division by zero";
							if (a == 0x80000000 && b == -1) {
								throw "signed integer overflow";
							}

							frame.IP += 8;
							var val:I32 = cast(a / b);
							frame.regs[valueID] = Int64.ofInt(val);
						}
					case I32DivU:
						{
							var a:U32 = cast frame.regs[LittleEndian.Uint32(frame.code.sub(frame.IP, frame.IP + 4))];
							var b:U32 = cast frame.regs[LittleEndian.Uint32(frame.code.sub(frame.IP + 4, frame.IP + 8))];

							if (b == 0)
								throw "integer division by zero";

							frame.IP += 8;
							var val:U32 = cast(a / b);
							frame.regs[valueID] = Int64.ofInt(cast val);
						}
					case I32RemS:
						{
							var a:I32 = cast frame.regs[LittleEndian.Uint32(frame.code.sub(frame.IP, frame.IP + 4))];
							var b:I32 = cast frame.regs[LittleEndian.Uint32(frame.code.sub(frame.IP + 4, frame.IP + 8))];

							if (b == 0)
								throw "integer division by zero";

							frame.IP += 8;
							var val:I32 = cast(a % b);
							frame.regs[valueID] = Int64.ofInt(val);
						}
					case I32RemU:
						{
							var a:U32 = cast frame.regs[LittleEndian.Uint32(frame.code.sub(frame.IP, frame.IP + 4))];
							var b:U32 = cast frame.regs[LittleEndian.Uint32(frame.code.sub(frame.IP + 4, frame.IP + 8))];

							if (b == 0)
								throw "integer division by zero";

							frame.IP += 8;
							var val:U32 = cast(a % b);
							frame.regs[valueID] = Int64.ofInt(cast val);
						}
					case I32And:
						{
							var a:I32 = cast frame.regs[LittleEndian.Uint32(frame.code.sub(frame.IP, frame.IP + 4))];
							var b:I32 = cast frame.regs[LittleEndian.Uint32(frame.code.sub(frame.IP + 4, frame.IP + 8))];

							frame.IP += 8;
							var val:I32 = (a & b);
							frame.regs[valueID] = Int64.ofInt(val);
						}
					case I32Or:
						{
							var a:I32 = cast frame.regs[LittleEndian.Uint32(frame.code.sub(frame.IP, frame.IP + 4))];
							var b:I32 = cast frame.regs[LittleEndian.Uint32(frame.code.sub(frame.IP + 4, frame.IP + 8))];

							frame.IP += 8;
							var val:I32 = (a | b);
							frame.regs[valueID] = Int64.ofInt(val);
						}
					case I32Xor:
						{
							var a:I32 = cast frame.regs[LittleEndian.Uint32(frame.code.sub(frame.IP, frame.IP + 4))];
							var b:I32 = cast frame.regs[LittleEndian.Uint32(frame.code.sub(frame.IP + 4, frame.IP + 8))];

							frame.IP += 8;
							var val:I32 = (a ^ b);
							frame.regs[valueID] = Int64.ofInt(val);
						}
					case I32Shl:
						{
							var a:I32 = cast frame.regs[LittleEndian.Uint32(frame.code.sub(frame.IP, frame.IP + 4))];
							var b:I32 = cast frame.regs[LittleEndian.Uint32(frame.code.sub(frame.IP + 4, frame.IP + 8))];

							frame.IP += 8;
							var val:I32 = (a << (b % 32));
							frame.regs[valueID] = Int64.ofInt(val);
						}
					case I32ShrS:
						{
							var a:I32 = cast frame.regs[LittleEndian.Uint32(frame.code.sub(frame.IP, frame.IP + 4))];
							var b:I32 = cast frame.regs[LittleEndian.Uint32(frame.code.sub(frame.IP + 4, frame.IP + 8))];

							frame.IP += 8;
							var val:I32 = (a >> (b % 32));
							frame.regs[valueID] = Int64.ofInt(val);
						}
					case I32ShrU:
						{
							var a:U32 = cast frame.regs[LittleEndian.Uint32(frame.code.sub(frame.IP, frame.IP + 4))];
							var b:U32 = cast frame.regs[LittleEndian.Uint32(frame.code.sub(frame.IP + 4, frame.IP + 8))];

							frame.IP += 8;
							var val:U32 = (a >> (b % 32));
							frame.regs[valueID] = Int64.ofInt(cast val);
						}
					case I32Rotl:
						{
							var a:U32 = cast frame.regs[LittleEndian.Uint32(frame.code.sub(frame.IP, frame.IP + 4))];
							var b:U32 = cast frame.regs[LittleEndian.Uint32(frame.code.sub(frame.IP + 4, frame.IP + 8))];

							frame.IP += 8;
							var val = rotateLeft32(a, b);
							frame.regs[valueID] = Int64.ofInt(val);
						}
					case I32Rotr:
						{
							var a:U32 = cast frame.regs[LittleEndian.Uint32(frame.code.sub(frame.IP, frame.IP + 4))];
							var b:U32 = cast frame.regs[LittleEndian.Uint32(frame.code.sub(frame.IP + 4, frame.IP + 8))];

							frame.IP += 8;
							var val = rotateLeft32(a, -b);
							frame.regs[valueID] = Int64.ofInt(val);
						}
					case I32Clz:
						{
							var a:U32 = cast frame.regs[LittleEndian.Uint32(frame.code.sub(frame.IP, frame.IP + 4))];
							frame.IP += 4;
							frame.regs[valueID] = Int64.ofInt(LeadingZeros32(a));
						}
					case I32PopCnt:
						{
							var a:U32 = cast frame.regs[LittleEndian.Uint32(frame.code.sub(frame.IP, frame.IP + 4))];
							frame.IP += 4;
							frame.regs[valueID] = Int64.ofInt(OnesCount32(a));
						}
					case I32EqZ:
						{
							var val:U32 = cast frame.regs[LittleEndian.Uint32(frame.code.sub(frame.IP, frame.IP + 4))];
							frame.IP += 4;
							if (val == 0) {
								frame.regs[valueID] = 1;
							} else {
								frame.regs[valueID] = 0;
							}
						}
					case I32Eq:
						{
							var a:I32 = cast frame.regs[LittleEndian.Uint32(frame.code.sub(frame.IP, frame.IP + 4))];
							var b:I32 = cast frame.regs[LittleEndian.Uint32(frame.code.sub(frame.IP + 4, frame.IP + 8))];
							frame.IP += 8;
							if (a == b) {
								frame.regs[valueID] = 1;
							} else {
								frame.regs[valueID] = 0;
							}
						}
					case I32Ne:
						{
							var a:I32 = cast frame.regs[LittleEndian.Uint32(frame.code.sub(frame.IP, frame.IP + 4))];
							var b:I32 = cast frame.regs[LittleEndian.Uint32(frame.code.sub(frame.IP + 4, frame.IP + 8))];
							frame.IP += 8;
							if (a != b) {
								frame.regs[valueID] = 1;
							} else {
								frame.regs[valueID] = 0;
							}
						}
					case I32LtS:
						{
							var a:I32 = cast frame.regs[LittleEndian.Uint32(frame.code.sub(frame.IP, frame.IP + 4))];
							var b:I32 = cast frame.regs[LittleEndian.Uint32(frame.code.sub(frame.IP + 4, frame.IP + 8))];
							frame.IP += 8;
							if (a < b) {
								frame.regs[valueID] = 1;
							} else {
								frame.regs[valueID] = 0;
							}
						}
					case I32LtU:
						{
							var a:U32 = cast frame.regs[LittleEndian.Uint32(frame.code.sub(frame.IP, frame.IP + 4))];
							var b:U32 = cast frame.regs[LittleEndian.Uint32(frame.code.sub(frame.IP + 4, frame.IP + 8))];
							frame.IP += 8;
							if (a < b) {
								frame.regs[valueID] = 1;
							} else {
								frame.regs[valueID] = 0;
							}
						}
					case I32LeS:
						{
							var a:I32 = cast frame.regs[LittleEndian.Uint32(frame.code.sub(frame.IP, frame.IP + 4))];
							var b:I32 = cast frame.regs[LittleEndian.Uint32(frame.code.sub(frame.IP + 4, frame.IP + 8))];
							frame.IP += 8;
							if (a <= b) {
								frame.regs[valueID] = 1;
							} else {
								frame.regs[valueID] = 0;
							}
						}
					case I32LeU:
						{
							var a:U32 = cast frame.regs[LittleEndian.Uint32(frame.code.sub(frame.IP, frame.IP + 4))];
							var b:U32 = cast frame.regs[LittleEndian.Uint32(frame.code.sub(frame.IP + 4, frame.IP + 8))];
							frame.IP += 8;
							if (a <= b) {
								frame.regs[valueID] = 1;
							} else {
								frame.regs[valueID] = 0;
							}
						}
					case I32GtS:
						{
							var a:I32 = cast frame.regs[LittleEndian.Uint32(frame.code.sub(frame.IP, frame.IP + 4))];
							var b:I32 = cast frame.regs[LittleEndian.Uint32(frame.code.sub(frame.IP + 4, frame.IP + 8))];
							frame.IP += 8;
							if (a > b) {
								frame.regs[valueID] = 1;
							} else {
								frame.regs[valueID] = 0;
							}
						}
					case I32GtU:
						{
							var a:U32 = cast frame.regs[LittleEndian.Uint32(frame.code.sub(frame.IP, frame.IP + 4))];
							var b:U32 = cast frame.regs[LittleEndian.Uint32(frame.code.sub(frame.IP + 4, frame.IP + 8))];
							frame.IP += 8;
							if (a > b) {
								frame.regs[valueID] = 1;
							} else {
								frame.regs[valueID] = 0;
							}
						}
					case I32GeS:
						{
							var a:I32 = cast frame.regs[LittleEndian.Uint32(frame.code.sub(frame.IP, frame.IP + 4))];
							var b:I32 = cast frame.regs[LittleEndian.Uint32(frame.code.sub(frame.IP + 4, frame.IP + 8))];
							frame.IP += 8;
							if (a >= b) {
								frame.regs[valueID] = 1;
							} else {
								frame.regs[valueID] = 0;
							}
						}
					case I32GeU:
						{
							var a:U32 = cast frame.regs[LittleEndian.Uint32(frame.code.sub(frame.IP, frame.IP + 4))];
							var b:U32 = cast frame.regs[LittleEndian.Uint32(frame.code.sub(frame.IP + 4, frame.IP + 8))];
							frame.IP += 8;
							if (a >= b) {
								frame.regs[valueID] = 1;
							} else {
								frame.regs[valueID] = 0;
							}
						}

					case I64Const:
						{
							var val:U64 = Read.U64(new BytesInput(frame.code.sub(frame.IP, frame.IP + 8)));
							frame.IP += 8;
							frame.regs[valueID] = cast val;
						}
					case I64Add:
						{
							var a:I64 = frame.regs[LittleEndian.Uint32(frame.code.sub(frame.IP, frame.IP + 4))];
							var b:I64 = frame.regs[LittleEndian.Uint32(frame.code.sub(frame.IP + 4, frame.IP + 8))];
							frame.IP += 8;
							frame.regs[valueID] = a + b;
						}
					case I64Sub:
						{
							var a:I64 = frame.regs[LittleEndian.Uint32(frame.code.sub(frame.IP, frame.IP + 4))];
							var b:I64 = frame.regs[LittleEndian.Uint32(frame.code.sub(frame.IP + 4, frame.IP + 8))];
							frame.IP += 8;
							frame.regs[valueID] = a - b;
						}
					case I64Mul:
						{
							var a:I64 = frame.regs[LittleEndian.Uint32(frame.code.sub(frame.IP, frame.IP + 4))];
							var b:I64 = frame.regs[LittleEndian.Uint32(frame.code.sub(frame.IP + 4, frame.IP + 8))];
							frame.IP += 8;
							frame.regs[valueID] = a * b;
						}
					case I64DivS:
						{
							var a:I64 = frame.regs[LittleEndian.Uint32(frame.code.sub(frame.IP, frame.IP + 4))];
							var b:I64 = frame.regs[LittleEndian.Uint32(frame.code.sub(frame.IP + 4, frame.IP + 8))];

							var minI64Val:I64 = -9223372036854775808;

							if (b == 0)
								throw "integer division by zero";

							if (a == minI64Val && b == -1) {
								throw "signed integer overflow";
							}

							frame.IP += 8;
							frame.regs[valueID] = a / b;
						}
					case I64DivU:
						{
							var a:U64 = cast frame.regs[LittleEndian.Uint32(frame.code.sub(frame.IP, frame.IP + 4))];
							var b:U64 = cast frame.regs[LittleEndian.Uint32(frame.code.sub(frame.IP + 4, frame.IP + 8))];

							if (b == 0)
								throw "integer division by zero";

							frame.IP += 8;
							var v = a / b;
							frame.regs[valueID] = cast v;
						}
					case I64RemS:
						{
							var a:I64 = frame.regs[LittleEndian.Uint32(frame.code.sub(frame.IP, frame.IP + 4))];
							var b:I64 = frame.regs[LittleEndian.Uint32(frame.code.sub(frame.IP + 4, frame.IP + 8))];

							if (b == 0)
								throw "integer division by zero";

							frame.IP += 8;
							frame.regs[valueID] = a % b;
						}
					case I64RemU:
						{
							var a:U64 = frame.regs[LittleEndian.Uint32(frame.code.sub(frame.IP, frame.IP + 4))];
							var b:U64 = frame.regs[LittleEndian.Uint32(frame.code.sub(frame.IP + 4, frame.IP + 8))];

							if (b == 0)
								throw "integer division by zero";

							frame.IP += 8;
							frame.regs[valueID] = cast(a % b);
						}
					case I64And:
						{
							var a:I64 = frame.regs[LittleEndian.Uint32(frame.code.sub(frame.IP, frame.IP + 4))];
							var b:I64 = frame.regs[LittleEndian.Uint32(frame.code.sub(frame.IP + 4, frame.IP + 8))];

							frame.IP += 8;
							frame.regs[valueID] = a & b;
						}
					case I64Or:
						{
							var a:I64 = frame.regs[LittleEndian.Uint32(frame.code.sub(frame.IP, frame.IP + 4))];
							var b:I64 = frame.regs[LittleEndian.Uint32(frame.code.sub(frame.IP + 4, frame.IP + 8))];

							frame.IP += 8;
							frame.regs[valueID] = a | b;
						}

					case I64Xor:
						{
							var a:I64 = frame.regs[LittleEndian.Uint32(frame.code.sub(frame.IP, frame.IP + 4))];
							var b:I64 = frame.regs[LittleEndian.Uint32(frame.code.sub(frame.IP + 4, frame.IP + 8))];

							frame.IP += 8;
							frame.regs[valueID] = a ^ b;
						}
					case I64Shl:
						{
							var a:I64 = frame.regs[LittleEndian.Uint32(frame.code.sub(frame.IP, frame.IP + 4))];
							var b:U64 = frame.regs[LittleEndian.Uint32(frame.code.sub(frame.IP + 4, frame.IP + 8))];

							frame.IP += 8;
							var v = (a << (b % 64));
							frame.regs[valueID] = cast v;
						}
					case I64ShrS:
						{
							var a:I64 = frame.regs[LittleEndian.Uint32(frame.code.sub(frame.IP, frame.IP + 4))];
							var b:U64 = frame.regs[LittleEndian.Uint32(frame.code.sub(frame.IP + 4, frame.IP + 8))];

							frame.IP += 8;
							var v = (a >> (b % 64));
							frame.regs[valueID] = cast v;
						}
					case I64ShrU:
						{
							var a:U64 = frame.regs[LittleEndian.Uint32(frame.code.sub(frame.IP, frame.IP + 4))];
							var b:U64 = frame.regs[LittleEndian.Uint32(frame.code.sub(frame.IP + 4, frame.IP + 8))];

							frame.IP += 8;
							var v = (a >> (b % 64));
							frame.regs[valueID] = cast v;
						}
					case I64Rotl:
						{
							var a:U64 = frame.regs[LittleEndian.Uint32(frame.code.sub(frame.IP, frame.IP + 4))];
							var b:U64 = frame.regs[LittleEndian.Uint32(frame.code.sub(frame.IP + 4, frame.IP + 8))];

							frame.IP += 8;
							var v = rotateLeft64(cast a, cast b);
							frame.regs[valueID] = cast v;
						}
					case I64Rotr:
						{
							var a:U64 = frame.regs[LittleEndian.Uint32(frame.code.sub(frame.IP, frame.IP + 4))];
							var b:U64 = frame.regs[LittleEndian.Uint32(frame.code.sub(frame.IP + 4, frame.IP + 8))];

							frame.IP += 8;
							var v = rotateLeft64(cast a, -cast(b, Int));
							frame.regs[valueID] = cast v;
						}
					case I64PopCnt:
						{
							var val:U64 = frame.regs[LittleEndian.Uint32(frame.code.sub(frame.IP, frame.IP + 4))];
							

							frame.IP += 4;
							
							frame.regs[valueID] = Int64.ofInt(OnesCount64(val));
						}
					case I64Clz:
						{
							var val:U64 = frame.regs[LittleEndian.Uint32(frame.code.sub(frame.IP, frame.IP + 4))];

							frame.IP += 4;
							frame.regs[valueID] = Int64.ofInt(LeadingZeros64(val));
						}
					case I64Ctz:
						{
							var val:U64 = frame.regs[LittleEndian.Uint32(frame.code.sub(frame.IP, frame.IP + 4))];

							frame.IP += 4;
							frame.regs[valueID] = Int64.ofInt(TrailingZeros64(val));
						}
					case I64EqZ:
						{
							var val:U64 = frame.regs[LittleEndian.Uint32(frame.code.sub(frame.IP, frame.IP + 4))];
							frame.IP += 4;
							if (val == 0) {
								frame.regs[valueID] = 1;
							} else {
								frame.regs[valueID] = 0;
							}
						}
					case I64Eq:
						{
							var a:I64 = frame.regs[LittleEndian.Uint32(frame.code.sub(frame.IP, frame.IP + 4))];
							var b:I64 = frame.regs[LittleEndian.Uint32(frame.code.sub(frame.IP + 4, frame.IP + 8))];
							frame.IP += 8;
							if (a == b) {
								frame.regs[valueID] = 1;
							} else {
								frame.regs[valueID] = 0;
							}
						}
					 case I64Ne:
						{
							var a:I64 = frame.regs[LittleEndian.Uint32(frame.code.sub(frame.IP, frame.IP + 4))];
							var b:I64 = frame.regs[LittleEndian.Uint32(frame.code.sub(frame.IP + 4, frame.IP + 8))];
							frame.IP += 8;
							if (a != b) {
								frame.regs[valueID] = 1;
							} else {
								frame.regs[valueID] = 0;
							}
						}
					case I64LtS:
						{
							var a:I64 = frame.regs[LittleEndian.Uint32(frame.code.sub(frame.IP, frame.IP + 4))];
							var b:I64 = frame.regs[LittleEndian.Uint32(frame.code.sub(frame.IP + 4, frame.IP + 8))];
							frame.IP += 8;
							if (a < b) {
								frame.regs[valueID] = 1;
							} else {
								frame.regs[valueID] = 0;
							}
						}
					case I64LtU:
						{
							var a:U64 = frame.regs[LittleEndian.Uint32(frame.code.sub(frame.IP, frame.IP + 4))];
							var b:U64 = frame.regs[LittleEndian.Uint32(frame.code.sub(frame.IP + 4, frame.IP + 8))];
							frame.IP += 8;
							if (a < b) {
								frame.regs[valueID] = 1;
							} else {
								frame.regs[valueID] = 0;
							}
						}
					case I64LeS:
						{
							var a:I64 = frame.regs[LittleEndian.Uint32(frame.code.sub(frame.IP, frame.IP + 4))];
							var b:I64 = frame.regs[LittleEndian.Uint32(frame.code.sub(frame.IP + 4, frame.IP + 8))];
							frame.IP += 8;
							if (a <= b) {
								frame.regs[valueID] = 1;
							} else {
								frame.regs[valueID] = 0;
							}
						}
					case I64LeU:
						{
							var a:U64 = frame.regs[LittleEndian.Uint32(frame.code.sub(frame.IP, frame.IP + 4))];
							var b:U64 = frame.regs[LittleEndian.Uint32(frame.code.sub(frame.IP + 4, frame.IP + 8))];
							frame.IP += 8;
							if (a <= b) {
								frame.regs[valueID] = 1;
							} else {
								frame.regs[valueID] = 0;
							}
						}
					case I64GtS:
						{
							var a:I64 = frame.regs[LittleEndian.Uint32(frame.code.sub(frame.IP, frame.IP + 4))];
							var b:I64 = frame.regs[LittleEndian.Uint32(frame.code.sub(frame.IP + 4, frame.IP + 8))];
							frame.IP += 8;
							if (a > b) {
								frame.regs[valueID] = 1;
							} else {
								frame.regs[valueID] = 0;
							}
						}
					case I64GtU:
						{
							var a:U64 = frame.regs[LittleEndian.Uint32(frame.code.sub(frame.IP, frame.IP + 4))];
							var b:U64 = frame.regs[LittleEndian.Uint32(frame.code.sub(frame.IP + 4, frame.IP + 8))];
							frame.IP += 8;
							if (a > b) {
								frame.regs[valueID] = 1;
							} else {
								frame.regs[valueID] = 0;
							}
						}
					case I64GeS:
						{
							var a:I64 = frame.regs[LittleEndian.Uint32(frame.code.sub(frame.IP, frame.IP + 4))];
							var b:I64 = frame.regs[LittleEndian.Uint32(frame.code.sub(frame.IP + 4, frame.IP + 8))];
							frame.IP += 8;
							if (a >= b) {
								frame.regs[valueID] = 1;
							} else {
								frame.regs[valueID] = 0;
							}
						}
					case I64GeU:
						{
							var a:U64 = frame.regs[LittleEndian.Uint32(frame.code.sub(frame.IP, frame.IP + 4))];
							var b:U64 = frame.regs[LittleEndian.Uint32(frame.code.sub(frame.IP + 4, frame.IP + 8))];
							frame.IP += 8;
							if (a >= b) {
								frame.regs[valueID] = 1;
							} else {
								frame.regs[valueID] = 0;
							}
						}
					case F32Add:{
						var a:Float = Float32frombits(cast frame.regs[LittleEndian.Uint32(frame.code.sub(frame.IP, frame.IP + 4))]);
						var b:Float = Float32frombits(cast frame.regs[LittleEndian.Uint32(frame.code.sub(frame.IP + 4, frame.IP + 8))]);
						frame.IP += 8;
						var c = a + b;
						frame.regs[valueID] = FPHelper.doubleToI64(c);
					}
					case F32Sub:{
						var a:Float = Float32frombits(cast frame.regs[LittleEndian.Uint32(frame.code.sub(frame.IP, frame.IP + 4))]);
						var b:Float = Float32frombits(cast frame.regs[LittleEndian.Uint32(frame.code.sub(frame.IP + 4, frame.IP + 8))]);
						frame.IP += 8;
						var c = a - b;
						frame.regs[valueID] = FPHelper.doubleToI64(c);
					}
					case F32Mul:{
						var a:Float = Float32frombits(cast frame.regs[LittleEndian.Uint32(frame.code.sub(frame.IP, frame.IP + 4))]);
						var b:Float = Float32frombits(cast frame.regs[LittleEndian.Uint32(frame.code.sub(frame.IP + 4, frame.IP + 8))]);
						frame.IP += 8;
						var c = a * b;
						frame.regs[valueID] = FPHelper.doubleToI64(c);
					}
					case F32Div:{
						var a:Float = Float32frombits(cast frame.regs[LittleEndian.Uint32(frame.code.sub(frame.IP, frame.IP + 4))]);
						var b:Float = Float32frombits(cast frame.regs[LittleEndian.Uint32(frame.code.sub(frame.IP + 4, frame.IP + 8))]);
						frame.IP += 8;
						var c = a / b;
						frame.regs[valueID] = FPHelper.doubleToI64(c);
					}
					case F32Sqrt:{
						var a:Float = Float32frombits(cast frame.regs[LittleEndian.Uint32(frame.code.sub(frame.IP, frame.IP + 4))]);
						
						frame.IP += 4;
						var c = Math.sqrt(a);
						frame.regs[valueID] = FPHelper.doubleToI64(c);
					}
					case F32Min:{
						var a:Float = Float32frombits(cast frame.regs[LittleEndian.Uint32(frame.code.sub(frame.IP, frame.IP + 4))]);
						var b:Float = Float32frombits(cast frame.regs[LittleEndian.Uint32(frame.code.sub(frame.IP + 4, frame.IP + 8))]);
						frame.IP += 8;
						var c = Math.min(a, b);
						frame.regs[valueID] = FPHelper.doubleToI64(c);
					}
					case F32Max:{
						var a:Float = Float32frombits(cast frame.regs[LittleEndian.Uint32(frame.code.sub(frame.IP, frame.IP + 4))]);
						var b:Float = Float32frombits(cast frame.regs[LittleEndian.Uint32(frame.code.sub(frame.IP + 4, frame.IP + 8))]);
						frame.IP += 8;
						var c = Math.max(a, b);
						frame.regs[valueID] = FPHelper.doubleToI64(c);
					}
					case F32Ceil:{
						var a:Float = Float32frombits(cast frame.regs[LittleEndian.Uint32(frame.code.sub(frame.IP, frame.IP + 4))]);
						
						frame.IP += 4;
						var c = Math.fceil(a);
						frame.regs[valueID] =  FPHelper.doubleToI64(c);
					}
					case F32Floor:{
						var a:Float = Float32frombits(cast frame.regs[LittleEndian.Uint32(frame.code.sub(frame.IP, frame.IP + 4))]);
						
						frame.IP += 4;
						var c = Math.ffloor(a);
						frame.regs[valueID] =  FPHelper.doubleToI64(c);
					}
					case F32Nearest:{
						var a:Float = Float32frombits(cast frame.regs[LittleEndian.Uint32(frame.code.sub(frame.IP, frame.IP + 4))]);
						
						frame.IP += 4;
						var c = Math.fround(a);
						frame.regs[valueID] =  FPHelper.doubleToI64(c);
					}
					case F32Abs:{
						var a:Float = Float32frombits(cast frame.regs[LittleEndian.Uint32(frame.code.sub(frame.IP, frame.IP + 4))]);
						
						frame.IP += 4;
						var c = Math.abs(a);
						frame.regs[valueID] =  FPHelper.doubleToI64(c);
					}
					case F32Neg:{
						var a:Float = Float32frombits(cast frame.regs[LittleEndian.Uint32(frame.code.sub(frame.IP, frame.IP + 4))]);
						
						frame.IP += 4;
						var c = -a;
						frame.regs[valueID] =  FPHelper.doubleToI64(c);
					}
					case F32Trunc:{
						var a:Float = Float32frombits(cast frame.regs[LittleEndian.Uint32(frame.code.sub(frame.IP, frame.IP + 4))]);
						
						frame.IP += 4;
						var c = Trunc(a);
						frame.regs[valueID] =  FPHelper.doubleToI64(c);
					}
					case F32CopySign:{
						var a:Float = Float32frombits(cast frame.regs[LittleEndian.Uint32(frame.code.sub(frame.IP, frame.IP + 4))]);
						var b:Float = Float32frombits(cast frame.regs[LittleEndian.Uint32(frame.code.sub(frame.IP + 4, frame.IP + 8))]);
						frame.IP += 8;
						var c = CopySign(a, b);
						frame.regs[valueID] = FPHelper.doubleToI64(c);
					}
				}
			}
		} catch (e:Dynamic) {
			insideExecute = false;
			exited = true;
			exitErr = e;
			stackTrace = haxe.CallStack.toString(haxe.CallStack.exceptionStack());
		}
	}
}
