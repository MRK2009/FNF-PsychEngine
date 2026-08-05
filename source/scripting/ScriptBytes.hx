package scripting;

/**
 * Bulk byte access for scripts.
 *
 * Reading bytes one at a time from a script is expensive twice over. Every accessor on
 * `haxe.io.Bytes` is declared `inline` in the standard library, so none of them has a runtime
 * representation to call and each one has to go through a shim (see `ScriptShims`); and even with
 * the shim in place, a file of any size means one interpreted call per byte.
 *
 * These do the loop in compiled code, so reading a whole lump costs one call instead of tens of
 * thousands. The result is a plain array, which a script indexes at roughly a tenth the cost of a
 * call, so the copy pays for itself long before the file is finished with.
 *
 * `@:keep` because nothing in the engine calls this; only scripts do, by name, and dead code
 * elimination cannot see that.
 */
@:keep
class ScriptBytes {
	/**
	 * Copies a byte range into a plain array of unsigned values.
	 *
	 * @param bytes  the buffer to read
	 * @param start  first byte to copy, defaults to the beginning
	 * @param length how many to copy, defaults to the rest of the buffer
	 */
	public static function toIntArray(bytes:haxe.io.Bytes, start:Int = 0, length:Int = -1):Array<Int> {
		if (bytes == null) {
			return [];
		}

		var from:Int = start < 0 ? 0 : start;
		if (from > bytes.length) {
			return [];
		}

		var count:Int = length < 0 ? bytes.length - from : length;
		if (from + count > bytes.length) {
			count = bytes.length - from;
		}

		var out:Array<Int> = [];
		for (i in 0...count) {
			out.push(bytes.get(from + i));
		}
		return out;
	}

	/**
	 * Reads a fixed-size, NUL-padded name, upper-cased.
	 *
	 * Container formats pad short names out to a fixed width with NULs, and building that string a
	 * character at a time is a call per character from a script. This is here because it is the one
	 * string operation such formats need in bulk.
	 */
	public static function fixedName(bytes:haxe.io.Bytes, start:Int, width:Int):String {
		if (bytes == null || start < 0 || start + width > bytes.length) {
			return '';
		}

		var out:StringBuf = new StringBuf();
		for (i in 0...width) {
			var c:Int = bytes.get(start + i);
			if (c != 0) {
				out.addChar(c);
			}
		}
		return out.toString().toUpperCase();
	}
}
