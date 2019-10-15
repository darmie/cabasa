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


### Dependencies

 * [Haxe](https://haxe.org/)
 * [Wasp](https://github.com/darmie/wasp)
 * [Binary128](https://github.com/darmie/binary128)
 * [Numerix](https://github.com/darmie/numerix)

### To-Do
- Command Line Interface for running wasm module from terminal, disassemble wasm or compile wasm to Haxe AOT
- Validate wasm binary
- Extension framwork for distributing wasm modules as Haxe libraries
- Examples 
