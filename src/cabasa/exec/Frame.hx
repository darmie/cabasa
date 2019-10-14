package cabasa.exec;

import cabasa.compiler.Module.InterpreterCode;

/**
 * Represents a call frame.
 */
typedef TFrame = {
	functionID:Int,
	code:haxe.io.Bytes,
	regs:Array<I64>,
	locals:Array<I64>,
	IP:Int,
	returnReg:Int,
	continuation:I32
}

@:forward(
    functionID,
    code,
    regs,
    locals,
    IP,
    returnReg,
    continuation
)
abstract Frame(TFrame) from TFrame to TFrame {
    inline function new(f:TFrame) {
        this = f;
    }

    /**
     * initializes a frame. Must be called on `call` and `call_indirect`.
     * @param vm 
     * @param functionID 
     * @param code 
     */
    public function init(vm:VM, functionID:Int, code:InterpreterCode) {
        var numValueSlots = code.numRegs + code.numParams + code.numLocals;
        if(vm.config.maxValueSlots != 0 && vm.numValueSlots+numValueSlots > vm.config.maxValueSlots){
            throw "max value slot count exceeded";
        }

        vm.numValueSlots += numValueSlots;
        var values:Array<I64> = [];
        this.functionID = functionID;
        this.regs = values.slice(0, code.numRegs);
        this.locals = values.slice(code.numRegs);
        this.code = code.bytes;
        this.IP = 0;
        this.continuation = 0;
    }

    /**
     * destroys a frame. Must be called on return.
     * @param vm 
     */
    public function destroy(vm:VM){
        var numValueSlots = this.regs.length + this.locals.length;
        vm.numValueSlots -= numValueSlots;
    }
}
