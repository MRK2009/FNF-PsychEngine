package scripting;

import flixel.FlxStrip;
import flixel.graphics.tile.FlxDrawTrianglesItem.DrawData;

/**
 * Bulk geometry transfer from script arrays into the buffers `drawTriangles` consumes.
 *
 * A script that builds its own geometry has no cheap way to hand it over. `openfl.Vector` is an
 * abstract, so there is no runtime class for the interpreter to construct; assigning by index
 * does not reach the abstract's accessor either. That leaves `push`, one interpreted call per
 * float, and a frame of custom geometry is tens of thousands of floats. The crossing ends up
 * costing more than building the geometry did.
 *
 * These do the identical work in compiled code, one call per buffer rather than one per element.
 * Nothing here is specific to any mod: it is the missing bulk path for any script driving
 * `FlxStrip`.
 *
 * `@:keep` because nothing in the engine calls this. Only scripts do, and dead code elimination
 * cannot see that.
 */
@:keep
class ScriptDraw {
	/**
	 * Uploads quad geometry to a strip and generates its triangle indices.
	 *
	 * Vertices and UVs are interleaved x/y pairs, four vertices per quad in corner order. Indices
	 * are derived rather than passed, because for quads they are entirely predictable and having
	 * a script build them means another buffer to fill and another crossing to pay for.
	 *
	 * Buffers are resized and refilled in place, so a steady frame rate allocates nothing.
	 *
	 * @param strip     the strip to upload into
	 * @param vertices  screen x/y pairs, at least `quads * 8` entries
	 * @param uvs       normalised u/v pairs, matching `vertices`
	 * @param quads     how many quads to take from the front of those arrays
	 */
	public static function uploadQuads(strip:FlxStrip, vertices:Array<Float>, uvs:Array<Float>, quads:Int):Void {
		if (strip == null || vertices == null || uvs == null || quads <= 0) {
			if (strip != null) {
				strip.visible = false;
			}
			return;
		}

		var floats:Int = quads * 8;
		if (vertices.length < floats || uvs.length < floats) {
			strip.visible = false;
			return;
		}

		var v:DrawData<Float> = strip.vertices;
		var t:DrawData<Float> = strip.uvtData;
		var n:DrawData<Int> = strip.indices;

		if (v.length != floats) {
			v.length = floats;
		}
		if (t.length != floats) {
			t.length = floats;
		}

		for (i in 0...floats) {
			v[i] = vertices[i];
			t[i] = uvs[i];
		}

		var indexCount:Int = quads * 6;
		if (n.length != indexCount) {
			n.length = indexCount;
		}

		for (q in 0...quads) {
			var base:Int = q * 4;
			var at:Int = q * 6;

			n[at] = base;
			n[at + 1] = base + 1;
			n[at + 2] = base + 2;
			n[at + 3] = base;
			n[at + 4] = base + 2;
			n[at + 5] = base + 3;
		}

		strip.visible = true;
	}

	/** Empties a strip's buffers so it costs no draw call. */
	public static function clearStrip(strip:FlxStrip):Void {
		if (strip == null) {
			return;
		}

		strip.vertices.length = 0;
		strip.uvtData.length = 0;
		strip.indices.length = 0;
		strip.visible = false;
	}
}
