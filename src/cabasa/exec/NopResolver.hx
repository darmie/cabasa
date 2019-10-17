package cabasa.exec;

class NopResolver implements ImportResolver {
    public function new() {
        
    }
    /**
     * Resoolve function impport
     * @param module 
     * @param field 
     * @return FunctionImport
     */
    public function resolveFunc(module:String, field:String):FunctionImport {
        throw "not implemented";
    }

    /**
     * Resolve global import
     * @param module 
     * @param field 
     * @return I64
     */
    public function resolveGlobal(module:String, field:String):I64 {
        throw "not implemented";
    }
}