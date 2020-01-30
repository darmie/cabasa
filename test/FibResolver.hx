package test;

import haxe.Int64;
import cabasa.exec.*;
import haxe.io.*;

class FibResolver implements ImportResolver {
	public function new() {}

	/**
	 * Resoolve function impport
	 * @param module
	 * @param field
	 * @return FunctionImport
	 */
	public function resolveFunc(module:String, field:String):FunctionImport {
		return switch module {
			case 'env': {
                    trace(field);
					return switch field {
						case '__putc': return function(vm:VM):I64 {
								var frame:Frame = vm.getCurrentFrame();
								var c:I32 = Int64.toInt(frame.locals[0]);
								var str = String.fromCharCode(c);
								trace(str);
								return 0;
							}
						case '__syscall1': return function(vm:VM):I64 {
                                var frame:Frame = vm.getCurrentFrame();
								var n:I32 = Int64.toInt(frame.locals[0]);
								sysCall(vm, n, []);
								return 0;
							}
						case '__syscall3': return function(vm:VM):I64 {
                                var frame:Frame = vm.getCurrentFrame();
								var n:I32 = Int64.toInt(frame.locals[0]);
								var a:I32 = Int64.toInt(frame.locals[1]);
								var b:I32 = Int64.toInt(frame.locals[2]);
								var c:I32 = Int64.toInt(frame.locals[3]);
								sysCall(vm, n, [a, b, c]);
								return 0;
							}
						case '__syscall5': return function(vm:VM):I64 {
                                var frame:Frame = vm.getCurrentFrame();
								var n:I32 = Int64.toInt(frame.locals[0]);
								var a:I32 = Int64.toInt(frame.locals[1]);
								var b:I32 = Int64.toInt(frame.locals[2]);
								var c:I32 = Int64.toInt(frame.locals[3]);
								var d:I32 = Int64.toInt(frame.locals[4]);
								var e:I32 = Int64.toInt(frame.locals[5]);
								sysCall(vm, n, [a, b, c, d, e]);
								return 0;
							}
						default: throw 'cannot find field $field in module $module';
					}
				}
			default: throw 'module $module not found in host';
		}
	}

    var memoryStates:Map<VM, Dynamic> = new Map();

	function sysCall(vm:VM, n:Int, args:Array<I64>):Int {
		switch (n) {
			default: return 0;
            case /* brk */ 45: return 0;
			case /* writev */ 146:
				{
					var writev_c = vm.getFunctionExport("writev_c");
					var data = vm.run(writev_c, args[0], args[1], args[2]);
					if (data.err != null) {
						trace(data.err);
                        return -1;
						// do something with error
					}
					return data.result;
				}
			case /* mmap2 */ 192:
				{
                    
                    var memory = new BytesOutput();
                    memory.write(vm.memory);
                    var memoryState = memoryStates.get(vm);
                    var requested:I32 = Int64.toInt(args[1]);
                    if (memoryState == null){
                        memoryState = {
                            object: memory,
                            currentPosition: memory.length,
                        };

                        memoryStates.set(vm, memoryState);
                    }

                    var cur:Int = memoryState.currentPosition;

                    if (cur + requested > memory.length) {
                        var need = Math.ceil((cur + requested - memory.length) / 65536);
                        memory.write(Bytes.alloc(need));
                    }

                    memoryState.currentPosition += requested;
                    return cur;
                }
		}
	}

	/**
	 * Resolve global import
	 * @param module
	 * @param field
	 * @return I64
	 */
	public function resolveGlobal(module:String, field:String):I64 {
		throw '$module.$field Global import is not implemented';
	}
}
