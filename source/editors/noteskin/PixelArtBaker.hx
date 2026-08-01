package editors.noteskin;

import backend.skins.Pixel;
import backend.NoteSkinConfig;
import backend.NoteSkinConfig.NoteSkinData;
import openfl.display.BitmapData;
import openfl.display.PNGEncoderOptions;

using StringTools;

/** Result of a bake: what was written, and why nothing was when `frames` is 0. **/
typedef BakeResult = {frames:Int, path:String, error:String};

/**
	Generates a skin's `pixel/` art from its HD art, so a pixel variant can be bootstrapped instead of
	drawn from scratch. Output always lands as `pixel/<name>-pixel.png` -- the form
	`NoteSkinConfig.pixelArt` resolves -- so a baked skin picks its own frames up with no config edit.

	The two halves work differently because the ENGINE treats them differently:

	- `bake` (SPLASH) reproduces `PixelSplashShader`, which quantises the art in place at full size
	  rather than swapping in a smaller image. Once the frames exist `applySplash` detects them and
	  turns the shader off, so the look is unchanged but now editable and one shader cheaper.
	- `bakeElements` (EVERYTHING ELSE) downscales, because notes/strums/holds have no shader: pixel
	  mode swaps in genuinely smaller art (the shipped `Default` is 157x154 HD against 17x17 pixel).

	Neither bakes COLOUR. Lane colour is applied at runtime by the RGB palette, so baking the shader's
	colour matrix would freeze one lane's colour into the art.

	Both run on the CPU rather than reading back off the GPU, so they work headless and deterministically.
**/
class PixelArtBaker {
	/** Smallest dimension a baked frame may have, so thin art keeps some gradient to stretch. **/
	static inline var MIN_DIM:Int = 2;

	/** 50% opacity: the default cull threshold, and the lowest alpha a baked pixel may have come from. **/
	public static inline var ALPHA_HALF:Int = 128;

	/**
		Bakes every splash frame of a skin.
		@param draft the skin to bake (must already be saved to a real directory)
		@param zoom the block size, normally `PlayState.daPixelZoom`
		@param maxColors palette size for the quantize pass; `<= 1` leaves colour alone
		@param alphaCut alpha threshold for hard edges
		@return how many frames were written, where, and any error
	**/
	public static function bake(draft:NoteSkinDraft, zoom:Float, maxColors:Int = 0, alphaCut:Int = ALPHA_HALF):BakeResult {
		#if sys
		if (draft == null || draft.config == null)
			return {frames: 0, path: null, error: 'No skin loaded'};
		if (draft.dir == null)
			return {frames: 0, path: null, error: 'Save the skin first'};
		if (zoom < 2)
			return {frames: 0, path: null, error: 'Pixel zoom must be at least 2'};

		var cfg:NoteSkinData = draft.config;
		if (cfg.splash == null)
			return {frames: 0, path: null, error: 'This skin has no splash image set'};

		// Resolve the splash frames the same way the renderer does, off the BASE art (never a pixel
		// variant -- baking from an already-baked frame would compound the block size).
		var prevRender:Bool = Pixel.render;
		Pixel.render = false;
		var prevPin:Null<String> = Paths.pinModRoot;
		var pin:Null<String> = NoteSkinConfig.activeSkinPinRoot();
		if (pin != null)
			Paths.pinModRoot = pin;

		var base:String = NoteSkinConfig.folder(draft.name);
		var key:String = NoteSkinConfig.columnKey(cfg.splash, 0);
		var frames:Array<String> = (key != null) ? NoteSkinConfig.frameKeys(base + key) : null;

		var written:Int = 0;
		var err:String = null;
		var outDir:String = draft.dir + '/pixel';

		if (frames == null || frames.length < 1) {
			err = 'Could not resolve splash frames for "' + key + '"';
		} else {
			try {
				NoteSkinDraft.ensureDir(outDir);
				for (frameKey in frames) {
					var src:BitmapData = loadBitmap(frameKey);
					if (src == null)
						continue;
					var out:BitmapData = pixelate(src, zoom);
					out = finish(out, maxColors, alphaCut);
					// `<name>-pixel.png`: the suffix goes AFTER the frame number, which is the form
					// `NoteSkinConfig.pixelArt` looks for inside a `pixel/` folder.
					var leaf:String = frameKey.substr(frameKey.lastIndexOf('/') + 1);
					sys.io.File.saveBytes('$outDir/$leaf-pixel.png', out.encode(out.rect, new PNGEncoderOptions()));
					out.dispose();
					written++;
				}
			} catch (e:Dynamic)
				err = Std.string(e);
		}

		Paths.pinModRoot = prevPin;
		Pixel.render = prevRender;
		NoteSkinConfig.invalidate(draft.name); // so the new frames are seen immediately

		if (err == null && written < 1)
			err = 'No splash frames could be read';
		return {frames: written, path: outDir, error: err};
		#else
		return {frames: 0, path: null, error: 'Baking needs a desktop build'};
		#end
	}

	/**
		Bakes low-res pixel variants for the NON-splash elements.

		These don't use a shader -- `resolveFrames` swaps in `pixel/` art when the skin is in pixel mode,
		so a pixel variant has to be a genuinely smaller image. Real skins bear this out: the shipped
		`Default` art is 157x154 with a 17x17 pixel counterpart.

		Each frame is downscaled by `scale / pixelScale`, which is exactly the factor that makes the
		result occupy the SAME on-screen space: the HD art draws at `scale` while pixel art draws at
		`pixelScale`. This produces a usable starting point to hand-tidy, not a replacement for
		hand-drawn pixel art.

		@param draft the skin to bake (must already be saved)
		@param elements the element fields to bake
		@param maxColors palette size for the quantize pass; `<= 1` leaves colour alone
		@param alphaCut alpha threshold for hard edges
		@return how many frames were written, where, and any error
	**/
	public static function bakeElements(draft:NoteSkinDraft, elements:Array<String>, maxColors:Int = 16, alphaCut:Int = ALPHA_HALF):BakeResult {
		#if sys
		if (draft == null || draft.config == null)
			return {frames: 0, path: null, error: 'No skin loaded'};
		if (draft.dir == null)
			return {frames: 0, path: null, error: 'Save the skin first'};
		if (draft.atlas)
			return {frames: 0, path: null, error: 'Atlas skins have no per-element images to bake'};

		var cfg:NoteSkinData = draft.config;
		var scale:Float = numOf(cfg.scale, 0.7);
		var pixelScale:Float = numOf(cfg.pixelScale, 6);
		if (pixelScale <= 0)
			return {frames: 0, path: null, error: 'Pixel scale must be above 0'};
		var ratio:Float = scale / pixelScale;
		if (ratio <= 0 || ratio >= 1)
			return {frames: 0, path: null, error: 'Pixel scale must be larger than Scale to downscale'};

		var prevRender:Bool = Pixel.render;
		Pixel.render = false; // always bake from the BASE art, never a previous bake
		var prevPin:Null<String> = Paths.pinModRoot;
		var pin:Null<String> = NoteSkinConfig.activeSkinPinRoot();
		if (pin != null)
			Paths.pinModRoot = pin;

		var base:String = NoteSkinConfig.folder(draft.name);
		var outDir:String = draft.dir + '/pixel';
		var written:Int = 0;
		var err:String = null;

		try {
			NoteSkinDraft.ensureDir(outDir);
			for (element in elements) {
				// Every lane's key, so a per-direction skin bakes all of its distinct images.
				var done:Array<String> = [];
				for (col in 0...Mania.clamp(draft.keyCount)) {
					var key:String = NoteSkinConfig.columnKey(draft.effective(element), col);
					if (key == null || key.length < 1 || done.contains(key))
						continue;
					done.push(key);
					var frames:Array<String> = NoteSkinConfig.frameKeys(base + key);
					if (frames == null)
						continue;
					for (frameKey in frames) {
						var src:BitmapData = loadBitmap(frameKey);
						if (src == null)
							continue;
						// Floor at 2px: a thin source (a 50x20 hold body reduces to ~2px tall) would
						// otherwise collapse to a single row with no gradient left to stretch.
						var tw:Int = Std.int(Math.max(MIN_DIM, Math.round(src.width * ratio)));
						var th:Int = Std.int(Math.max(MIN_DIM, Math.round(src.height * ratio)));
						var out:BitmapData = finish(downscale(src, tw, th), maxColors, alphaCut);
						var leaf:String = frameKey.substr(frameKey.lastIndexOf('/') + 1);
						sys.io.File.saveBytes('$outDir/$leaf-pixel.png', out.encode(out.rect, new PNGEncoderOptions()));
						out.dispose();
						written++;
					}
				}
			}
		} catch (e:Dynamic)
			err = Std.string(e);

		Paths.pinModRoot = prevPin;
		Pixel.render = prevRender;
		NoteSkinConfig.invalidate(draft.name);

		if (err == null && written < 1)
			err = 'No element frames could be read';
		return {frames: written, path: outDir, error: err};
		#else
		return {frames: 0, path: null, error: 'Baking needs a desktop build'};
		#end
	}

	static function numOf(v:Dynamic, fallback:Float):Float {
		if (v == null)
			return fallback;
		if (Std.isOfType(v, Float) || Std.isOfType(v, Int))
			return v;
		var f:Float = Std.parseFloat(Std.string(v));
		return Math.isNaN(f) ? fallback : f;
	}

	/**
		Area-averaged (box filter) downscale.

		A large downscale needs every source pixel to contribute; bilinear (what `BitmapData.draw`
		would give) samples only a 2x2 neighbourhood and drops most of a ~9x reduction on the floor,
		which shreds thin outlines. Colour is averaged WEIGHTED BY ALPHA so transparent pixels don't
		bleed black into the edges -- the classic halo when RGB is averaged unweighted.

		@param src the source art
		@param tw the target width
		@param th the target height
		@return a new bitmap; the caller owns it
	**/
	public static function downscale(src:BitmapData, tw:Int, th:Int):BitmapData {
		var sw:Int = src.width;
		var sh:Int = src.height;
		var out:BitmapData = new BitmapData(tw, th, true, 0x00000000);

		for (y in 0...th) {
			var y0:Int = Std.int(y * sh / th);
			var y1:Int = Std.int((y + 1) * sh / th);
			if (y1 <= y0)
				y1 = y0 + 1;
			for (x in 0...tw) {
				var x0:Int = Std.int(x * sw / tw);
				var x1:Int = Std.int((x + 1) * sw / tw);
				if (x1 <= x0)
					x1 = x0 + 1;

				var aSum:Float = 0;
				var rSum:Float = 0;
				var gSum:Float = 0;
				var bSum:Float = 0;
				var count:Int = 0;
				for (sy in y0...y1) {
					for (sx in x0...x1) {
						var p:Int = src.getPixel32(sx, sy);
						var a:Float = (p >>> 24) & 0xFF;
						rSum += ((p >> 16) & 0xFF) * a;
						gSum += ((p >> 8) & 0xFF) * a;
						bSum += (p & 0xFF) * a;
						aSum += a;
						count++;
					}
				}
				if (count < 1)
					continue;
				var a:Int = Std.int(aSum / count + 0.5);
				var r:Int = (aSum > 0) ? Std.int(rSum / aSum + 0.5) : 0;
				var g:Int = (aSum > 0) ? Std.int(gSum / aSum + 0.5) : 0;
				var b:Int = (aSum > 0) ? Std.int(bSum / aSum + 0.5) : 0;
				out.setPixel32(x, y, (a << 24) | (r << 16) | (g << 8) | b);
			}
		}
		return out;
	}

	/**
		Reduces a bitmap to a small palette with hard edges -- the step that makes a downscale actually
		read as pixel art rather than a smooth miniature.

		Colour is reduced by MEDIAN CUT: repeatedly split the colour box with the widest channel spread
		at its median, then map every pixel to the nearest resulting representative. Unlike a fixed
		posterize this adapts to the art's actual palette, so a mostly-one-hue note keeps its shading
		instead of banding into a few arbitrary levels.

		Transparent pixels are left transparent and take no part in the palette -- `cullAlpha` has
		already decided which pixels exist.

		@param src the source art (already alpha-culled by `cullAlpha`)
		@param maxColors palette size; `<= 1` skips colour reduction
		@return a new bitmap; the caller owns it
	**/
	public static function quantize(src:BitmapData, maxColors:Int):BitmapData {
		var w:Int = src.width;
		var h:Int = src.height;
		var out:BitmapData = new BitmapData(w, h, true, 0x00000000);

		var counts:Map<Int, Int> = new Map();
		for (y in 0...h) {
			for (x in 0...w) {
				var p:Int = src.getPixel32(x, y);
				if (((p >>> 24) & 0xFF) == 0)
					continue;
				var rgb:Int = p & 0xFFFFFF;
				counts.set(rgb, (counts.exists(rgb) ? counts.get(rgb) : 0) + 1);
			}
		}

		var uniques:Array<Int> = [for (k in counts.keys()) k];
		if (uniques.length < 1)
			return out; // nothing opaque left to quantise

		var palette:Array<Int> = (maxColors > 1 && uniques.length > maxColors) ? medianCut(uniques, counts, maxColors) : uniques;

		// Cache the mapping: art repeats colours heavily, so this collapses the nearest-colour search
		// to once per DISTINCT colour instead of once per pixel.
		var mapped:Map<Int, Int> = new Map();
		for (y in 0...h) {
			for (x in 0...w) {
				var p:Int = src.getPixel32(x, y);
				if (((p >>> 24) & 0xFF) == 0)
					continue;
				var rgb:Int = p & 0xFFFFFF;
				var hit:Int;
				if (mapped.exists(rgb))
					hit = mapped.get(rgb);
				else {
					hit = nearest(palette, rgb);
					mapped.set(rgb, hit);
				}
				out.setPixel32(x, y, 0xFF000000 | hit);
			}
		}
		return out;
	}

	static inline function channelOf(rgb:Int, ch:Int):Int
		return switch (ch) {
			case 0: (rgb >> 16) & 0xFF;
			case 1: (rgb >> 8) & 0xFF;
			default: rgb & 0xFF;
		}

	/** Splits the colour set into `maxColors` boxes and returns each box's weighted average. **/
	static function medianCut(colors:Array<Int>, counts:Map<Int, Int>, maxColors:Int):Array<Int> {
		var boxes:Array<Array<Int>> = [colors.copy()];

		while (boxes.length < maxColors) {
			var pickIdx:Int = -1;
			var pickCh:Int = 0;
			var pickRange:Int = 0;
			for (i in 0...boxes.length) {
				var box:Array<Int> = boxes[i];
				if (box.length < 2)
					continue;
				for (ch in 0...3) {
					var mn:Int = 255;
					var mx:Int = 0;
					for (c in box) {
						var v:Int = channelOf(c, ch);
						if (v < mn)
							mn = v;
						if (v > mx)
							mx = v;
					}
					if (mx - mn > pickRange) {
						pickRange = mx - mn;
						pickIdx = i;
						pickCh = ch;
					}
				}
			}
			if (pickIdx < 0 || pickRange < 1)
				break; // every box is a single colour already

			var box:Array<Int> = boxes[pickIdx];
			var ch:Int = pickCh;
			box.sort(function(a:Int, b:Int):Int return channelOf(a, ch) - channelOf(b, ch));
			var mid:Int = Std.int(box.length / 2);
			boxes[pickIdx] = box.slice(0, mid);
			boxes.push(box.slice(mid));
		}

		return [for (box in boxes) average(box, counts)];
	}

	/** A box's representative colour: its members averaged, weighted by how often each occurs. **/
	static function average(box:Array<Int>, counts:Map<Int, Int>):Int {
		var r:Float = 0;
		var g:Float = 0;
		var b:Float = 0;
		var total:Float = 0;
		for (c in box) {
			var n:Int = counts.exists(c) ? counts.get(c) : 1;
			r += ((c >> 16) & 0xFF) * n;
			g += ((c >> 8) & 0xFF) * n;
			b += (c & 0xFF) * n;
			total += n;
		}
		if (total <= 0)
			return box.length > 0 ? box[0] : 0;
		return (Std.int(r / total + 0.5) << 16) | (Std.int(g / total + 0.5) << 8) | Std.int(b / total + 0.5);
	}

	/** Nearest palette entry by squared RGB distance. **/
	static function nearest(palette:Array<Int>, rgb:Int):Int {
		var br:Int = (rgb >> 16) & 0xFF;
		var bg:Int = (rgb >> 8) & 0xFF;
		var bb:Int = rgb & 0xFF;
		var best:Int = palette[0];
		var bestDist:Int = 0x7FFFFFFF;
		for (c in palette) {
			var dr:Int = ((c >> 16) & 0xFF) - br;
			var dg:Int = ((c >> 8) & 0xFF) - bg;
			var db:Int = (c & 0xFF) - bb;
			var d:Int = dr * dr + dg * dg + db * db;
			if (d < bestDist) {
				bestDist = d;
				best = c;
			}
		}
		return best;
	}

	/**
		Drops every pixel below `threshold` opacity and makes the rest fully opaque.

		ALWAYS applied, and applied BEFORE any colour work: half-transparent pixels are what make a
		downscale look like a blurry miniature instead of pixel art, and the rule must not depend on
		whether colour reduction happens to be enabled.

		@param src the art to cull
		@param threshold alpha below this is discarded (`ALPHA_HALF` = 50% opacity)
		@return a new bitmap; the caller owns it
	**/
	public static function cullAlpha(src:BitmapData, threshold:Int):BitmapData {
		var w:Int = src.width;
		var h:Int = src.height;
		var out:BitmapData = new BitmapData(w, h, true, 0x00000000);
		for (y in 0...h) {
			for (x in 0...w) {
				var p:Int = src.getPixel32(x, y);
				if (((p >>> 24) & 0xFF) < threshold)
					continue; // stays fully transparent
				out.setPixel32(x, y, 0xFF000000 | (p & 0xFFFFFF));
			}
		}
		return out;
	}

	/** Alpha cull then colour reduction, disposing the intermediates. **/
	static function finish(bmp:BitmapData, maxColors:Int, alphaCut:Int):BitmapData {
		var culled:BitmapData = cullAlpha(bmp, alphaCut);
		bmp.dispose();
		if (maxColors <= 1)
			return culled;
		var q:BitmapData = quantize(culled, maxColors);
		culled.dispose();
		return q;
	}

	static function loadBitmap(key:String):BitmapData {
		var img = NoteSkinConfig.resolveImage(key, false);
		return (img != null && img.graphic != null) ? img.graphic.bitmap : null;
	}

	/**
		Block-snaps a bitmap, reproducing `PixelSplashShader`'s pixelation at the SAME dimensions (the
		shader quantises, it doesn't downscale).

		This evaluates the shader's expression LITERALLY per axis rather than using the tempting
		`floor(x / zoom) * zoom` shorthand: the two only agree when `zoom` divides the texture size
		evenly, and differ by a pixel along block edges otherwise (verified across a range of sizes).
		The per-axis source index is resolved once into a lookup, so the fill stays a flat copy.

		@param src the source art
		@param zoom the block size, matching the shader's `uBlocksize`
		@return a new bitmap; the caller owns it
	**/
	public static function pixelate(src:BitmapData, zoom:Float):BitmapData {
		var w:Int = src.width;
		var h:Int = src.height;
		var out:BitmapData = new BitmapData(w, h, true, 0x00000000);

		var srcX:Array<Int> = axisMap(w, zoom);
		var srcY:Array<Int> = axisMap(h, zoom);

		for (y in 0...h) {
			var sy:Int = srcY[y];
			for (x in 0...w)
				out.setPixel32(x, y, src.getPixel32(srcX[x], sy));
		}
		return out;
	}

	/**
		The source texel each output index samples, mirroring
		`floor(coord * (size / zoom)) / (size / zoom)` with `coord = (i + 0.5) / size`.
		@param size the axis length in pixels
		@param zoom the block size
	**/
	static function axisMap(size:Int, zoom:Float):Array<Int> {
		var blocks:Float = size / zoom;
		var out:Array<Int> = [];
		for (i in 0...size) {
			var coord:Float = (i + 0.5) / size;
			var texel:Int = Std.int(Math.ffloor(coord * blocks) / blocks * size);
			if (texel < 0)
				texel = 0;
			else if (texel > size - 1)
				texel = size - 1;
			out.push(texel);
		}
		return out;
	}
}
