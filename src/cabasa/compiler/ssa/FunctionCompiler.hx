package cabasa.compiler.ssa;

import wasp.Module;
import wasp.disasm.Disassembly;



/**
 * FunctionCompiler represents a compiler which translates a WebAssembly modules
 * intepreted code into a Static-Single-Assignment-based intermediate representation.
 */
class FunctionCompiler {
    
    public var module:Module;
    public var source:Disassembly;



    public function toCFG():CFG {
        return null;
    }
}