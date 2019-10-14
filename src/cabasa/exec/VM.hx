package cabasa.exec;

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
        if(currentFrame >= callStack.length){
            throw "call stack overflow";
        }

        return callStack[currentFrame];
	}

    function getExport(key:String, kind:External){
        if(module.base.export == null){
            return -1;
        }
        if(module.base.export.entries.exists(key)){
            var entry = module.base.export.entries.get(key);
            if(entry.kind != kind){
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
    public function printStackTrace(){
        Sys.println("--- Begin stack trace ---");
        var i = currentFrame;
        while(i >= 0){
            var functionID = callStack[i].functionID;
            Sys.println('<${i}> [${functionID}] ${module.functionNames[functionID]}');
            i--;
        }
        Sys.println("--- End stack trace ---");
    }

    
    public function ignite(functionID:Int, params:Array<I64>){
        if(exitErr != null){
            throw "last execution exited with error; cannot ignite.";
        }
        if(currentFrame != -1){
            throw "call stack not empty; cannot ignite.";
        }

        var code = functionCode[functionID];
        if(code.numParams != params.length){
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
    public function execute(){

    }
}
