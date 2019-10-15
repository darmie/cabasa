package cabasa.bits;

import haxe.io.FPHelper;
import haxe.io.BytesData;
import haxe.io.Bytes;
import haxe.io.BytesBuffer;

/**
 * Bit operations borrowed from Golang: https://golang.org/src/math/bits/bits.go
 */
#if cpp
@:include("<math.h>");
#end
class Op {
	private static function uint(val):U32 {
		return cast val;
	}

	static var deBruijn32:U32 = 0x077CB531;

	#if cs
	static var deBruijn64:U64 = untyped __cs__('0x03F79D71B4CA8B09uL');
	#elseif java
	static var deBruijn64:U64 = untyped __java__('0x03F79D71B4CA8B09L & 0xFFFFFFFFL');
	#elseif cpp
	static var deBruijn64:U64 = untyped __cpp__('0x03F79D71B4CA8B09');
	#end

	#if cs
	static var m0:U64 = untyped __cs__('0x5555555555555555uL'); // 01010101 ...
	static var m1:U64 = untyped __cs__('0x3333333333333333uL'); // 00110011 ...
	static var m2:U64 = untyped __cs__('0x0F0F0F0F0F0f0F0FuL'); // 00001111 ...

	#elseif static
	var m0:U64 = untyped __java__('0x5555555555555555L & 0xFFFFFFFFL'); // 01010101 ...

	static var m1:U64 = untyped __java__('0x3333333333333333L & 0xFFFFFFFFL'); // 00110011 ...
	static var m2:U64 = untyped __java__('0x0F0F0F0F0F0f0F0FL & 0xFFFFFFFFL'); // 00001111 ...
	#elseif cpp
	static var m0:U64 = untyped __cpp__('0x5555555555555555'); // 01010101 ...
	static var m1:U64 = untyped __cpp__('0x3333333333333333'); // 00110011 ...
	static var m2:U64 = untyped __cpp__('0x0F0F0F0F0F0f0F0F'); // 00001111 ...

	#end
	static function deBruijn32tab():Bytes {
		var data = [
			 0,  1, 28,  2, 29, 14, 24, 3, 30, 22, 20, 15, 25, 17,  4, 8,
			31, 27, 13, 23, 21, 19, 16, 7, 26, 12, 18,  6, 11,  5, 10, 9
		];

		var buf = new BytesBuffer();
		for (d in data) {
			buf.addByte(d);
		}

		return buf.getBytes();
	}

	static var _deBruijn32tab = deBruijn32tab();

	static function deBruijn64tab():Bytes {
		var data = [
			 0,  1, 56,  2, 57, 49, 28,  3, 61, 58, 42, 50, 38, 29, 17,  4,
			62, 47, 59, 36, 45, 43, 51, 22, 53, 39, 33, 30, 24, 18, 12,  5,
			63, 55, 48, 27, 60, 41, 37, 16, 46, 35, 44, 21, 52, 32, 23, 11,
			54, 26, 40, 15, 34, 20, 31, 10, 25, 14, 19,  9, 13,  8,  7,  6
		];

		var buf = new BytesBuffer();
		for (d in data) {
			buf.addByte(d);
		}

		return buf.getBytes();
	}

	static var _deBruijn64tab = deBruijn64tab();

	static function len8tab():Bytes {
		var data = [
			0x00, 0x01, 0x02, 0x02, 0x03, 0x03, 0x03, 0x03, 0x04, 0x04, 0x04, 0x04, 0x04, 0x04, 0x04, 0x04,
			0x05, 0x05, 0x05, 0x05, 0x05, 0x05, 0x05, 0x05, 0x05, 0x05, 0x05, 0x05, 0x05, 0x05, 0x05, 0x05,
			0x06, 0x06, 0x06, 0x06, 0x06, 0x06, 0x06, 0x06, 0x06, 0x06, 0x06, 0x06, 0x06, 0x06, 0x06, 0x06,
			0x06, 0x06, 0x06, 0x06, 0x06, 0x06, 0x06, 0x06, 0x06, 0x06, 0x06, 0x06, 0x06, 0x06, 0x06, 0x06,
			0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07,
			0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07,
			0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07,
			0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07,
			0x08, 0x08, 0x08, 0x08, 0x08, 0x08, 0x08, 0x08, 0x08, 0x08, 0x08, 0x08, 0x08, 0x08, 0x08, 0x08,
			0x08, 0x08, 0x08, 0x08, 0x08, 0x08, 0x08, 0x08, 0x08, 0x08, 0x08, 0x08, 0x08, 0x08, 0x08, 0x08,
			0x08, 0x08, 0x08, 0x08, 0x08, 0x08, 0x08, 0x08, 0x08, 0x08, 0x08, 0x08, 0x08, 0x08, 0x08, 0x08,
			0x08, 0x08, 0x08, 0x08, 0x08, 0x08, 0x08, 0x08, 0x08, 0x08, 0x08, 0x08, 0x08, 0x08, 0x08, 0x08,
			0x08, 0x08, 0x08, 0x08, 0x08, 0x08, 0x08, 0x08, 0x08, 0x08, 0x08, 0x08, 0x08, 0x08, 0x08, 0x08,
			0x08, 0x08, 0x08, 0x08, 0x08, 0x08, 0x08, 0x08, 0x08, 0x08, 0x08, 0x08, 0x08, 0x08, 0x08, 0x08,
			0x08, 0x08, 0x08, 0x08, 0x08, 0x08, 0x08, 0x08, 0x08, 0x08, 0x08, 0x08, 0x08, 0x08, 0x08, 0x08,
			0x08, 0x08, 0x08, 0x08, 0x08, 0x08, 0x08, 0x08, 0x08, 0x08, 0x08, 0x08, 0x08, 0x08, 0x08, 0x08
		];

		var buf = new BytesBuffer();
		for (d in data) {
			buf.addByte(d);
		}

		return buf.getBytes();
	}

	static var _len8tab = len8tab();

	static function pop8tab():Bytes {
		var data = [
			0x00, 0x01, 0x01, 0x02, 0x01, 0x02, 0x02, 0x03, 0x01, 0x02, 0x02, 0x03, 0x02, 0x03, 0x03, 0x04,
			0x01, 0x02, 0x02, 0x03, 0x02, 0x03, 0x03, 0x04, 0x02, 0x03, 0x03, 0x04, 0x03, 0x04, 0x04, 0x05,
			0x01, 0x02, 0x02, 0x03, 0x02, 0x03, 0x03, 0x04, 0x02, 0x03, 0x03, 0x04, 0x03, 0x04, 0x04, 0x05,
			0x02, 0x03, 0x03, 0x04, 0x03, 0x04, 0x04, 0x05, 0x03, 0x04, 0x04, 0x05, 0x04, 0x05, 0x05, 0x06,
			0x01, 0x02, 0x02, 0x03, 0x02, 0x03, 0x03, 0x04, 0x02, 0x03, 0x03, 0x04, 0x03, 0x04, 0x04, 0x05,
			0x02, 0x03, 0x03, 0x04, 0x03, 0x04, 0x04, 0x05, 0x03, 0x04, 0x04, 0x05, 0x04, 0x05, 0x05, 0x06,
			0x02, 0x03, 0x03, 0x04, 0x03, 0x04, 0x04, 0x05, 0x03, 0x04, 0x04, 0x05, 0x04, 0x05, 0x05, 0x06,
			0x03, 0x04, 0x04, 0x05, 0x04, 0x05, 0x05, 0x06, 0x04, 0x05, 0x05, 0x06, 0x05, 0x06, 0x06, 0x07,
			0x01, 0x02, 0x02, 0x03, 0x02, 0x03, 0x03, 0x04, 0x02, 0x03, 0x03, 0x04, 0x03, 0x04, 0x04, 0x05,
			0x02, 0x03, 0x03, 0x04, 0x03, 0x04, 0x04, 0x05, 0x03, 0x04, 0x04, 0x05, 0x04, 0x05, 0x05, 0x06,
			0x02, 0x03, 0x03, 0x04, 0x03, 0x04, 0x04, 0x05, 0x03, 0x04, 0x04, 0x05, 0x04, 0x05, 0x05, 0x06,
			0x03, 0x04, 0x04, 0x05, 0x04, 0x05, 0x05, 0x06, 0x04, 0x05, 0x05, 0x06, 0x05, 0x06, 0x06, 0x07,
			0x02, 0x03, 0x03, 0x04, 0x03, 0x04, 0x04, 0x05, 0x03, 0x04, 0x04, 0x05, 0x04, 0x05, 0x05, 0x06,
			0x03, 0x04, 0x04, 0x05, 0x04, 0x05, 0x05, 0x06, 0x04, 0x05, 0x05, 0x06, 0x05, 0x06, 0x06, 0x07,
			0x03, 0x04, 0x04, 0x05, 0x04, 0x05, 0x05, 0x06, 0x04, 0x05, 0x05, 0x06, 0x05, 0x06, 0x06, 0x07,
			0x04, 0x05, 0x05, 0x06, 0x05, 0x06, 0x06, 0x07, 0x05, 0x06, 0x06, 0x07, 0x06, 0x07, 0x07, 0x08
		];

		var buf = new BytesBuffer();
		for (d in data) {
			buf.addByte(d);
		}

		return buf.getBytes();
	}

	static var _pop8tab = pop8tab();

	/**
	 * returns the number of trailing zero bits in x; the result is 32 for x == 0.
	 * @param x
	 */
	public static function TrailingZeros32(x:U32) {
		if (x == 0)
			return 32;
		return _deBruijn32tab.get((x & -x) * deBruijn32 >> (32 - 5));
	}

	/**
	 * returns the number of trailing zero bits in x; the result is 64 for x == 0.
	 * @param x
	 */
	public static function TrailingZeros64(x:U64):Int {
		if (x == 0)
			return 64;

		// If popcount is fast, replace code below with return popcount(^x & (x - 1)).
		//
		// x & -x leaves only the right-most bit set in the word. Let k be the
		// index of that bit. Since only a single bit is set, the value is two
		// to the power of k. Multiplying by a power of two is equivalent to
		// left shifting, in this case by k bits. The de Bruijn (64 bit) constant
		// is such that all six bit, consecutive substrings are distinct.
		// Therefore, if we have a left shifted version of this constant we can
		// find by how many bits it was shifted by looking at which six bit
		// substring ended up at the top of the word.
		// (Knuth, volume 4, section 7.3.1)
		var v = (x & -x) * deBruijn64 >> (64 - 6);
		return _deBruijn64tab.get(cast v);
	}

	static function len32(x:U32) {
		var ret:Int = 0;
		if (x >= 1 << 16) {
			x >>= 16;
			ret = 16;
		}

		if (x >= 1 << 8) {
			x >>= 8;
			ret += 8;
		}

		return ret + len8tab().get(x);
	}

	static function len64(x:U64) {
		var ret:Int = 0;
		if (x >= 1 << 32) {
			x >>= 32;
			ret = 32;
		}

		if (x >= 1 << 16) {
			x >>= 16;
			ret += 16;
		}

		if (x >= 1 << 8) {
			x >>= 8;
			ret += 8;
		}

		return ret + len8tab().get(cast x);
	}

	/**
	 * returns the number of leading zero bits in x; the result is 32 for x == 0.
	 * @param x
	 */
	public static function LeadingZeros32(x:U32) {
		return 32 - len32(x);
	}

	/**
	 * returns the number of leading zero bits in x; the result is 64 for x == 0.
	 * @param x
	 */
	public static function LeadingZeros64(x:U64) {
		return 64 - len64(x);
	}

	/**
	 * returns the number of one bits ("population count") in x.
	 * @param x
	 */
	public static function OnesCount32(x:U32) {
		return _pop8tab.get(x >> 24) + _pop8tab.get(x >> 16 & 0xff) + _pop8tab.get(x >> 8 & 0xff) + _pop8tab.get(x & 0xff);
	}

	/**
	 * returns the number of one bits ("population count") in x.
	 * @param x
	 */
	public static function OnesCount64(x:U64):Int {
		// Implementation: Parallel summing of adjacent bits.
		// See "Hacker's Delight", Chap. 5: Counting Bits.
		// The following pattern shows the general approach:
		//
		//   x = x>>1&(m0&m) + x&(m0&m)
		//   x = x>>2&(m1&m) + x&(m1&m)
		//   x = x>>4&(m2&m) + x&(m2&m)
		//   x = x>>8&(m3&m) + x&(m3&m)
		//   x = x>>16&(m4&m) + x&(m4&m)
		//   x = x>>32&(m5&m) + x&(m5&m)
		//   return int(x)
		//
		// Masking (& operations) can be left away when there's no
		// danger that a field's sum will carry over into the next
		// field: Since the result cannot be > 64, 8 bits is enough
		// and we can ignore the masks for the shifts by 8 and up.
		// Per "Hacker's Delight", the first line can be simplified
		// more, but it saves at best one instruction, so we leave
		// it alone for clarity.
        var m = 1<<64 - 1;
        x = x>>1&(m0&m) + x&(m0&m);
        x = x>>2&(m1&m) + x&(m1&m);
        x = (x>>4 + x) & (m2 & m);
        x += x >> 8;
        x += x >> 16;
        x += x >> 32;

        var v =  cast(x, Int) & (1<<7 - 1);

        return v;
	}

    public static function rotateLeft32(x:I32, n:I32):I32{
		return (x << n) | (x >> (32 - n)) & ~(-1 << n);
	}

    public static function rotateLeft64(x:I64, n):I64{
		return (x << n) | (x >> (64 - n)) & ~(-1 << n);
	}

    public static function Float32frombits(x:U32):Float {
        #if cs 
        return untyped __cs__('System.Convert.ToSingle({0})', x);
        #elseif java
        return FPHelper.i32ToFloat(x.toInt());
        #elseif cpp
        untyped __cpp__('float ret = {0}', x);
        return untyped __cpp__('ret');
        #end
        
    }

    public static function Float64frombits(x:U64):Float {
        #if cs 
        return untyped __cs__('System.Convert.ToDouble({0})', x);
        #elseif java
        return x.toDouble();
        #elseif cpp
        untyped __cpp__('double ret = {0}', x);
        return untyped __cpp__('ret');
        #end
    }


    public static function Trunc(x:Float):Float {
        if(x == 0 || !Math.isFinite(x) || Math.isNaN(x)){
            return x;
        }

        #if cs 
        return cs.system.Math.Truncate(x);
        #elseif java 
        if (value < 0) {
            return Math.ceil(value);
        } else {
            return Math.floor(value);
        }
        #elseif cpp 
        return untyped __cpp__('trunc({0})', x);
        #end
    }

    public static function CopySign(x:Float, y:Float) {
        #if cpp 
        return untyped __cpp__('copysign({0}, {1})', x, y);
        #elseif java 
        return java.lang.Math.copySign(x, y);
        #elseif cs 
        var magBits = cs.system.BitConverter.DoubleToInt64Bits(x);
        var signBits = cs.system.BitConverter.DoubleToInt64Bits(y);
         
        if((magBits ^ signBits)  < 0){
            return cs.system.BitConverter.Int64BitsToDouble(magBits ^ cs.system.Int64.MinValue);
        }
        return x;
        #end
    }
}
