package backend.replay;

import haxe.io.Bytes;
import haxe.io.BytesOutput;
import haxe.io.BytesInput;
#if sys
import sys.io.File;
import sys.FileSystem;
#end

/**
 * A complete recorded run in the compact binary `.psr` format: a header snapshotting everything
 * that influences judgement (song identity, playback rate, scoring system, judge/OD, hit windows,
 * offsets, input options) followed by the raw input-edge stream -- one byte of column+direction
 * plus a float64 song position per edge (~9 bytes each, a whole song is a few tens of KB).
 *
 * Edge times are the EXACT `Conductor.songPosition` values the run judged with (press edges use
 * the music-time-resynced position `keyPressed` computes), so playback reproduces every tap
 * offset bit-for-bit. Times are float64 on purpose: float32 would round late-song positions by
 * enough to flip judgements at window boundaries.
 */
class ReplayData {
	static inline final MAGIC:Int = 0x50535250; // "PSRP"
	static inline final VERSION:Int = 1;

	public var songKey:String = '';
	public var songName:String = '';
	public var folder:String = '';
	public var diff:Int = 0;
	public var keyCount:Int = 4;
	public var playbackRate:Float = 1;
	public var systemId:String = 'psych';
	public var etternaJudge:Int = 4;
	public var osuOD:Float = 8;
	public var ratingOffset:Int = 0;
	public var noteOffset:Int = 0;
	public var safeFrames:Float = 10;
	public var sickWindow:Float = 45;
	public var goodWindow:Float = 90;
	public var badWindow:Float = 135;
	public var ghostTapping:Bool = true;
	public var guitarHeroSustains:Bool = true;
	public var dateSec:Float = 0;

	/** Edge song positions in ms, index-aligned with `columns`. */
	public var times:Array<Float> = [];

	/** Edge column (bits 0-6) with bit 7 set for a press, clear for a release. */
	public var columns:Array<Int> = [];

	public function new() {}

	/**
	 * Appends one input edge.
	 * @param column the strum column
	 * @param down true for a press, false for a release
	 * @param timeMs the song position the edge was judged at
	 */
	public inline function push(column:Int, down:Bool, timeMs:Float):Void {
		columns.push(down ? (column | 0x80) : column);
		times.push(timeMs);
	}

	/** @return the number of recorded edges */
	public inline function length():Int
		return times.length;

	/** @return the whole replay encoded as bytes */
	public function encode():Bytes {
		var o:BytesOutput = new BytesOutput();
		o.bigEndian = false;
		o.writeInt32(MAGIC);
		o.writeByte(VERSION);
		writeStr(o, songKey);
		writeStr(o, songName);
		writeStr(o, folder);
		o.writeInt32(diff);
		o.writeByte(keyCount);
		o.writeDouble(playbackRate);
		writeStr(o, systemId);
		o.writeByte(etternaJudge);
		o.writeDouble(osuOD);
		o.writeInt32(ratingOffset);
		o.writeInt32(noteOffset);
		o.writeDouble(safeFrames);
		o.writeDouble(sickWindow);
		o.writeDouble(goodWindow);
		o.writeDouble(badWindow);
		o.writeByte(ghostTapping ? 1 : 0);
		o.writeByte(guitarHeroSustains ? 1 : 0);
		o.writeDouble(dateSec);
		o.writeInt32(times.length);
		for (i in 0...times.length) {
			o.writeByte(columns[i]);
			o.writeDouble(times[i]);
		}
		return o.getBytes();
	}

	/**
	 * Decodes a replay from bytes.
	 * @param bytes the encoded replay
	 * @return the replay, or null when the data is not a readable `.psr`
	 */
	public static function decode(bytes:Bytes):Null<ReplayData> {
		try {
			var i:BytesInput = new BytesInput(bytes);
			i.bigEndian = false;
			if (i.readInt32() != MAGIC)
				return null;
			if (i.readByte() != VERSION)
				return null;
			var r:ReplayData = new ReplayData();
			r.songKey = readStr(i);
			r.songName = readStr(i);
			r.folder = readStr(i);
			r.diff = i.readInt32();
			r.keyCount = i.readByte();
			r.playbackRate = i.readDouble();
			r.systemId = readStr(i);
			r.etternaJudge = i.readByte();
			r.osuOD = i.readDouble();
			r.ratingOffset = i.readInt32();
			r.noteOffset = i.readInt32();
			r.safeFrames = i.readDouble();
			r.sickWindow = i.readDouble();
			r.goodWindow = i.readDouble();
			r.badWindow = i.readDouble();
			r.ghostTapping = i.readByte() != 0;
			r.guitarHeroSustains = i.readByte() != 0;
			r.dateSec = i.readDouble();
			var n:Int = i.readInt32();
			r.times.resize(n);
			r.columns.resize(n);
			for (k in 0...n) {
				r.columns[k] = i.readByte();
				r.times[k] = i.readDouble();
			}
			return r;
		} catch (e:Dynamic) {
			return null;
		}
	}

	/**
	 * Writes the replay to disk.
	 * @param path the target file path
	 * @return true when the write succeeded
	 */
	public function save(path:String):Bool {
		#if sys
		try {
			File.saveBytes(path, encode());
			return true;
		} catch (e:Dynamic) {
			trace('ReplayData.save failed (' + path + '): ' + e);
		}
		#end
		return false;
	}

	/**
	 * Reads a replay from disk.
	 * @param path the `.psr` file path
	 * @return the replay, or null when missing or unreadable
	 */
	public static function load(path:String):Null<ReplayData> {
		#if sys
		try {
			if (!FileSystem.exists(path))
				return null;
			return decode(File.getBytes(path));
		} catch (e:Dynamic) {}
		#end
		return null;
	}

	/**
	 * Writes a length-prefixed UTF-8 string.
	 * @param o the output
	 * @param s the string, null writes as empty
	 */
	static function writeStr(o:BytesOutput, s:String):Void {
		if (s == null)
			s = '';
		var b:Bytes = Bytes.ofString(s);
		o.writeUInt16(b.length);
		o.write(b);
	}

	/**
	 * Reads a length-prefixed UTF-8 string.
	 * @param i the input
	 * @return the string
	 */
	static function readStr(i:BytesInput):String {
		var len:Int = i.readUInt16();
		return len == 0 ? '' : i.read(len).toString();
	}
}
