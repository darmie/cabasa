package cabasa.exec;

/**
 * VMConfig denotes a set of options passed to a single VM instance
 */
typedef VMConfig = {
    ?enableJIT:Bool,
    ?maxMemoryPages:Int,
    ?maxTableSize:Int,
    ?maxValueSlots:Int,
    ?maxCallStackDepth:Int,
    ?defaultMemoryPages:Int,
    ?defaultTableSize:Int,
    ?disableFloatingPoint:Bool
}