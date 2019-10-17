# Cābāsā
**Cābāsā** is a haxe framework for WebAssembly which includes a fast and secure WebAssembly VM (which is a haxe port of [Life](https://github.com/perlin-network/life) VM).

[Status: Not Ready For Use!]

## Features
- **Fast** - Includes a fast interpreter and an AOT compiler
- **Secure** - Executed code is fully sandboxed, wasm modules do not have access to host resources unless explicitly given.
- **Portable** - Does not rely on native dependencies and can redistribute wasm in AOT mode as normal haxe code.
- **Cross-Platform** - Cābāsā aims to take full advantage of Haxe's cross platform capabilities, therefore wasm module can go anywhere Haxe goes.

## Getting Started
Install package manager
```
npm i -g lix
``` 
Use latest Haxe version
```
lix use haxe 4.0.0-rc.5
```
Download dependencies 
```
lix download
```

### Executing WebAssembly Modules
Pass a wasm bytcode into a newly instantiated VM
```hx
import cabasa.exec.*;

...
var config:VMConfig = {...};
var resolver:ImportResolver = new MyImportResolver(); // handle function and global imports

var vm = new VM(code, config, resolver);
```
Look up an exported funtion from wasm code by its name, it will return its ID to be used to call the function later
```hx
var funcID = vm.getFunctionExport("main"); // could be the name of any exported function
```
Now call the function by its ID 
```hx
var data = vm.run(funcID);
if(data.err != null){
    // do something with error
}
Sys.println('return value ${data.result}');
``` 
### Implementing an Import Resolver
Assume a code compiled to wasm calls an virtual (or native) function `__graphics_drawCirle(radius, color)`, we need to resolve for this function in the host application. 

We create an **ImportResolver** class:
```hx
import cabasa.exec.*;

class MyImportResolver implements ImportResolver {
    ...
    public function resolveFunc(module:String, field:String):FunctionImport {
        return switch module {
            case 'env':{
                switch field:{
                    case '__graphics_drawCirle': function(vm:VM):I64 {
                            // get the local variables or function params
                            var radius:U32 = vm.getCurrentFrame().locals[0]; 
                            var color:U32 = vm.getCurrentFrame().locals[1]; 

                            // call the equivalent of the function in the host app
                            myhost.app.Graphics.drawCircle(cast radius, cast color); 

                            return 0;
                        };
                    }
                    default: throw 'cannot find field $field in module $module';
                }
            }
            default: throw 'module $module not found in host';
        }
    }
    // just like resolveFunc but returns the ID of the global export
    public function resolveGlobal(module:String, field:String):I64 {
        throw "not implemented for now"; 
    }
}
```
Now use this resolver in a VM instance
```hx
var vm = new VM(code, {...}, new MyImportResolver());
```

### Run Test 
```sh
#compile
haxe build.hxml

#run jar output
java -jar build/java/Test-Debug.jar
```

### Why Cābāsā ? 
I personally found other haxe embedded scripting interfaces quite limiting. `CPPIA` only works in C++ targets, `HL` only work in Hashlink VM just like `Neko` runs only in its VM. `hscript` is nice, it's crossplatform but it is a stripped down version of haxe, taking away useful features like types, OOP and modular imports (I honestly tried to fix this with [hxComposer](https://github.com/darmie/hxComposer)), it is at best just for expressions.

WebAssembly shows promise, apart from its much advertise use of redistributing native libraries to the web, it has drawn the attention of server side developers who feel the need to run self contained apps with all the advantages promised by WebAssembly. The WebAssembly [specification](https://webassembly.org) describes a stack based immediate language with promise of a faster load time, smaller and portable binary size, and memory-safe execution environment.

**Haxe + WebAssembly =** :zap: :zap: , a combined force that will benefit all cross platform software engineers. With Haxe's cross platform abilities and `wasm`, software distribution accross platforms should be more fluid by reducing the need for platform specific glue code, which makes for a more portable software without compromise on quality and performance.


### Dependencies

 * [Haxe](https://haxe.org/)
 * [Wasp](https://github.com/darmie/wasp)
 * [Binary128](https://github.com/darmie/binary128)
 * [Numerix](https://github.com/darmie/numerix)


### Supported Targets
- C++
- Java
- C#


### To-Do
- Support runtime and AOT compilation for HashLink binary 
- Support runtime and AOT compilation for Neko binary
- Support runtime and AOT compilation for CPPIA binary
- Command Line Interface for running wasm module from terminal, disassemble wasm or compile wasm to Haxe AOT
- Validate wasm binary
- Extension framwork for distributing wasm modules as Haxe libraries
- Examples
