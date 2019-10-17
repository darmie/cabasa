package test;

import wasp.wast.Writer;
import cabasa.exec.*;
import haxe.io.*;
import sys.FileSystem;
import sys.io.File;

class Test {
	public static function main() {
		var source = FileSystem.fullPath("test/program.wasm");
		var raw = File.getBytes(source);
		var vm = new VM(raw, {
			disableFloatingPoint: false,
			maxMemoryPages: 1024,
			maxCallStackDepth: 0,
			maxValueSlots: 0
		}, new NopResolver());

		var funcID = vm.getFunctionExport("main");
		var data = vm.run(funcID, []);
		if (data.err != null) {
			trace(data.err);
			// do something with error
		}
		var val:I64 = data.result;

		Sys.println('=== Executing Program.wasm ===\n');
		var buf = new StringBuf();
		Writer.writeTo(buf, vm.module.base);
		Sys.println(buf.toString());
		Sys.println('==============================');
		Sys.println('Output = $val');
		Sys.println('==============================');
	}
}
