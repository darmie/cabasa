package cabasa.exec;

import cabasa.compiler.Module.InterpreterCode;

/**
 * Represents a call frame.
 */
typedef Frame = {
	?functionID:Int,
	?code:haxe.io.Bytes,
	?regs:Array<I64>,
	?locals:Array<I64>,
	?IP:Int,
	?returnReg:Int,
	?continuation:I32
}


class FrameUtils {
    /**
     * initializes a frame. Must be called on `call` and `call_indirect`.
     * @param vm 
     * @param functionID 
     * @param code 
     */
    public static inline function init(frame:Frame, vm:VM, functionID:Int, _code:InterpreterCode) {
        var numValueSlots = _code.numRegs + _code.numParams + _code.numLocals;
        if(vm.config.maxValueSlots != 0 && vm.numValueSlots+numValueSlots > vm.config.maxValueSlots){
            throw "max value slot count exceeded";
        }

        if(frame == null){
            frame = {};
        }

        
        vm.numValueSlots += numValueSlots;
        var numRegs = _code.numRegs;
        var values:Array<I64> = [];
        for(i in 0...numValueSlots){
            values.push(0);
        }
        
        frame.functionID = functionID;
        frame.regs = values.slice(0, numRegs);
        frame.locals = values.slice(numRegs);
        frame.code = _code.bytes;
        frame.IP = 0;
        frame.continuation = 0;
    }

     /**
     * destroys a frame. Must be called on return.
     * @param vm 
     */
    public static function destroy(frame:Frame, vm:VM){
        if(frame != null){
            var numValueSlots = frame.regs.length + frame.locals.length;
            vm.numValueSlots -= numValueSlots;
        } 
    }
}
