package cabasa.exec;


/**
 * ImportResolver is an interface for allowing one to define imports to WebAssembly modules
 * ran under a single VirtualMachine instance.
 */
interface ImportResolver {
    /**
     * Resoolve function impport
     * @param module 
     * @param field 
     * @return FunctionImport
     */
    public function resolveFunc(module:String, field:String):FunctionImport;

    /**
     * Resolve global import
     * @param module 
     * @param field 
     * @return I64
     */
    public function resolveGlobal(module:String, field:String):I64;
}