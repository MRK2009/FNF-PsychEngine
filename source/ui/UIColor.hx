package ui;

/**
	Small ARGB color math helpers (the library never depends on a framework color type).
**/
final class UIColor {
	/**
		Linear blend between two ARGB colors.
		@param a the start color (`0xAARRGGBB`)
		@param b the end color
		@param t blend amount, 0 (all `a`) .. 1 (all `b`)
		@return the interpolated ARGB color
	**/
	public static function mix(a:Int, b:Int, t:Float):Int {
		if (t <= 0)
			return a;
		if (t >= 1)
			return b;
		var aA:Int = (a >>> 24) & 0xFF;
		var aR:Int = (a >>> 16) & 0xFF;
		var aG:Int = (a >>> 8) & 0xFF;
		var aB:Int = a & 0xFF;
		var bA:Int = (b >>> 24) & 0xFF;
		var bR:Int = (b >>> 16) & 0xFF;
		var bG:Int = (b >>> 8) & 0xFF;
		var bB:Int = b & 0xFF;
		var oA:Int = aA + Std.int((bA - aA) * t);
		var oR:Int = aR + Std.int((bR - aR) * t);
		var oG:Int = aG + Std.int((bG - aG) * t);
		var oB:Int = aB + Std.int((bB - aB) * t);
		return (oA << 24) | (oR << 16) | (oG << 8) | oB;
	}

	/**
		Blends a color toward white.
		@param c the ARGB color
		@param f blend amount 0..1
		@return the lightened ARGB color
	**/
	public static inline function lighten(c:Int, f:Float):Int {
		return mix(c, 0xFFFFFFFF, f);
	}

	/**
		Blends a color toward black, keeping its alpha.
		@param c the ARGB color
		@param f blend amount 0..1
		@return the darkened ARGB color
	**/
	public static inline function darken(c:Int, f:Float):Int {
		return mix(c, (c & 0xFF000000) | 0x000000, f);
	}

	/**
		Drops the alpha channel, for APIs that take RGB + a separate alpha.
		@param c the ARGB color
		@return the `0xRRGGBB` part
	**/
	public static inline function rgb(c:Int):Int {
		return c & 0xFFFFFF;
	}

	/**
		Extracts the alpha channel.
		@param c the ARGB color
		@return alpha as 0..1
	**/
	public static inline function alphaOf(c:Int):Float {
		return ((c >>> 24) & 0xFF) / 255.0;
	}
}
