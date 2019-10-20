package test;

import wasp.wast.Writer;
import cabasa.exec.*;
import haxe.io.*;
import sys.FileSystem;
import sys.io.File;

class Test {
	public static function main() {
		var source = FileSystem.fullPath("test/add.wasm");
		var raw = File.getBytes(source);
		
		Sys.println('===================================');
		call_add(raw);
		call_main(raw);
	}

	static function call_add(code:Bytes){
		var vm = new VM(code, {
			disableFloatingPoint: false,
			maxMemoryPages: 1024,
			maxCallStackDepth: 0,
			maxValueSlots: 0
		}, new NopResolver());

		var add_funcID = vm.getFunctionExport("add");
		var data = vm.run(add_funcID, [50, 70]);
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
		var data = vm.run(main_funcID, []);
		if (data.err != null) {
			trace(data.err);
			// do something with error
		}
		var val:I64 = data.result;

		Sys.println('=== Executing function main() =====');
		Sys.println('=== in program add.wasm ===========\n');
		var buf = new StringBuf();
		Writer.writeTo(buf, vm.module.base);
		Sys.println(buf.toString());
		Sys.println('===================================');
		Sys.println('Output = $val');
		Sys.println('===================================');
	}
}
