package test;

import wasp.wast.Writer;
import cabasa.exec.*;
import haxe.io.*;
import sys.FileSystem;
import sys.io.File;

class Test {
	public static function main() {
		var source1 = FileSystem.fullPath("test/program.wasm");
		var raw1 = File.getBytes(source1);
		var source2 = FileSystem.fullPath("test/add.wasm");
		var raw2 = File.getBytes(source2);

		var source3 = FileSystem.fullPath("test/call_indirect.wasm");
		var raw3 = File.getBytes(source3);


		var source4 = FileSystem.fullPath("test/loop.wasm");
		var raw4 = File.getBytes(source4);
		
		Sys.println('===================================');
		call_add(raw2);
		call_main(raw1);
		call_indirect(raw3);
		call_loop(raw4);
	}

	static function call_add(code:Bytes){
		var vm = new VM(code, {
			disableFloatingPoint: false,
			maxMemoryPages: 1024,
			maxCallStackDepth: 0,
			maxValueSlots: 0
		}, new NopResolver());

		var add_funcID = vm.getFunctionExport("add");
		var data = vm.run(add_funcID, 50, 70);
		if (data.err != null) {
			trace(data.err);
			// do something with error
		}
		var val:I64 = data.result;

		Sys.println('=== Executing function add(x, y) ==');
		Sys.println('=== in program add.wasm ===========\n');
		var buf = new StringBuf();
		Writer.writeTo(buf, vm.module.base);
		Sys.println(buf.toString());
		Sys.println('===================================');
		Sys.println('Output = $val');
		Sys.println('===================================');
	}

	static function call_main(code:Bytes){
		var vm = new VM(code, {
			disableFloatingPoint: false,
			maxMemoryPages: 1024,
			maxCallStackDepth: 0,
			maxValueSlots: 0
		}, new NopResolver());

		var main_funcID = vm.getFunctionExport("main");
		var data = vm.run(main_funcID);
		if (data.err != null) {
			trace(data.err);
			// do something with error
		}
		var val:I64 = data.result;

		Sys.println('====== Executing function main() =====');
		Sys.println('====== in program program.wasm =======\n');
		var buf = new StringBuf();
		Writer.writeTo(buf, vm.module.base);
		Sys.println(buf.toString());
		Sys.println('======================================');
		Sys.println('Output = $val');
		Sys.println('======================================');
	}


	static function call_indirect(code:Bytes){
		var vm = new VM(code, {
			disableFloatingPoint: false,
			maxMemoryPages: 1024,
			maxCallStackDepth: 0,
			maxValueSlots: 0,
			maxTableSize: 0
		}, new NopResolver());

		var main_funcID = vm.getFunctionExport("main");
		var data = vm.run(main_funcID);
		if (data.err != null) {
			trace(data.err);
			// do something with error
		}
		var val:I64 = data.result;

		Sys.println('====== Executing function main() =======');
		Sys.println('====== in program call_indirect.wasm ===\n');
		var buf = new StringBuf();
		Writer.writeTo(buf, vm.module.base);
		Sys.println(buf.toString());
		Sys.println('========================================');
		Sys.println('Output = $val');
		Sys.println('========================================');
	}

	static function call_loop(code:Bytes){
		var vm = new VM(code, {
			disableFloatingPoint: false,
			maxMemoryPages: 1024,
			maxCallStackDepth: 0,
			maxValueSlots: 0,
			maxTableSize: 0
		}, new NopResolver());

		var main_funcID = vm.getFunctionExport("main");
		var data = vm.run(main_funcID);
		if (data.err != null) {
			trace(data.err);
			// do something with error
		}
		var val:I64 = data.result;

		Sys.println('====== Executing function main() =======');
		Sys.println('====== in program loop.wasm ============\n');
		var buf = new StringBuf();
		Writer.writeTo(buf, vm.module.base);
		Sys.println(buf.toString());
		Sys.println('========================================');
		Sys.println('Output = $val');
		Sys.println('========================================');
	}
}
