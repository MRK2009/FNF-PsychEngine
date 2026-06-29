package editors.charting;

import lime.media.AudioBuffer;
import haxe.io.Bytes;
import flash.geom.Rectangle;
import editors.ChartingState;

/**
	Renders the chart editor's audio waveform overlay for the section currently in view.

	Owns only the scratch sample envelope (`wavData`); the displayed sprite and the enabled/target
	flags live on `ChartingState` (the View tab toggles them). `redraw` rebuilds the bitmap from the
	editor's active section and audio source.
**/
@:access(editors.ChartingState)
class EditorWaveform {
	var wavData:Array<Array<Array<Float>>> = [[[0], [0]], [[0], [0]]];

	public function new() {}

	/**
		Rebuilds the waveform bitmap for the editor's current section, or hides the overlay when the
		waveform is disabled / the section index is out of range.
		@param s the chart editor whose section, audio source and sprite drive the render
	**/
	public function redraw(s:ChartingState):Void {
		#if (lime_cffi && !macro)
		if (s.curSec < 0 || s.curSec >= s.cachedSectionTimes.length || !s.waveformEnabled) {
			s.waveformSprite.visible = false;
			return;
		}

		s.waveformSprite.visible = true;
		s.waveformSprite.flipY = ChartingState.downScroll;
		s.waveformSprite.y = ChartingState.downScroll ? (-s.curGridTopY - s.gridBg.height) : s.curGridTopY;
		var width:Int = Std.int(ChartingState.GRID_SIZE * ChartingState.GRID_COLUMNS_PER_PLAYER * ChartingState.GRID_PLAYERS);
		var height:Int = Std.int(s.gridBg.height);
		if (Std.int(s.waveformSprite.height) != height && s.waveformSprite.pixels != null) {
			s.waveformSprite.pixels.dispose();
			s.waveformSprite.pixels.disposeImage();
			s.waveformSprite.makeGraphic(width, height, 0x00FFFFFF);
		}
		s.waveformSprite.pixels.fillRect(new Rectangle(0, 0, width, height), 0x00FFFFFF);

		wavData[0][0].resize(0);
		wavData[0][1].resize(0);
		wavData[1][0].resize(0);
		wavData[1][1].resize(0);

		var sound:FlxSound = switch (s.waveformTarget) {
			case INST:
				FlxG.sound.music;
			case PLAYER:
				s.vocals;
			case OPPONENT:
				s.opponentVocals;
			default:
				null;
		}
		@:privateAccess
		if (sound != null && sound._sound != null && sound._sound.__buffer != null) {
			var bytes:Bytes = sound._sound.__buffer.data.toBytes();
			wavData = waveformData(sound._sound.__buffer, bytes, s.cachedSectionTimes[s.curSec] - Conductor.offset,
				s.cachedSectionTimes[s.curSec + 1] - Conductor.offset, 1, wavData, height);
		}

		var gSize:Int = Std.int(ChartingState.GRID_SIZE * ChartingState.GRID_COLUMNS_PER_PLAYER * ChartingState.GRID_PLAYERS);
		var hSize:Int = Std.int(gSize / 2);
		var size:Float = 1;

		var leftLength:Int = (wavData[0][0].length > wavData[0][1].length ? wavData[0][0].length : wavData[0][1].length);
		var rightLength:Int = (wavData[1][0].length > wavData[1][1].length ? wavData[1][0].length : wavData[1][1].length);

		var length:Int = leftLength > rightLength ? leftLength : rightLength;

		for (index in 0...length) {
			var lmin:Float = FlxMath.bound(((index < wavData[0][0].length && index >= 0) ? wavData[0][0][index] : 0) * (gSize / 1.12), -hSize, hSize) / 2;
			var lmax:Float = FlxMath.bound(((index < wavData[0][1].length && index >= 0) ? wavData[0][1][index] : 0) * (gSize / 1.12), -hSize, hSize) / 2;

			var rmin:Float = FlxMath.bound(((index < wavData[1][0].length && index >= 0) ? wavData[1][0][index] : 0) * (gSize / 1.12), -hSize, hSize) / 2;
			var rmax:Float = FlxMath.bound(((index < wavData[1][1].length && index >= 0) ? wavData[1][1][index] : 0) * (gSize / 1.12), -hSize, hSize) / 2;

			s.waveformSprite.pixels.fillRect(new Rectangle(hSize - (lmin + rmin), index * size, (lmin + rmin) + (lmax + rmax), size), FlxColor.WHITE);
		}
		#else
		s.waveformSprite.visible = false;
		#end
	}

	/**
		Accumulates the per-row min/max sample envelope for a slice of a PCM audio buffer. Ported from
		the original chart editor's waveform sampler.
		@param buffer the decoded audio buffer
		@param bytes the buffer's raw PCM bytes
		@param time slice start in ms
		@param endTime slice end in ms
		@param multiply amplitude scale
		@param array reused output `[channel][min/max][row]` envelope (allocated if null)
		@param steps target row count
		@return the populated envelope
	**/
	function waveformData(buffer:AudioBuffer, bytes:Bytes, time:Float, endTime:Float, multiply:Float = 1, ?array:Array<Array<Array<Float>>>,
			?steps:Float):Array<Array<Array<Float>>> {
		#if (lime_cffi && !macro)
		if (buffer == null || buffer.data == null)
			return [[[0], [0]], [[0], [0]]];

		var khz:Float = (buffer.sampleRate / 1000);
		var channels:Int = buffer.channels;

		var index:Int = Std.int(time * khz);

		var samples:Float = ((endTime - time) * khz);

		if (steps == null)
			steps = 1280;

		var samplesPerRow:Float = samples / steps;
		var samplesPerRowI:Int = Std.int(samplesPerRow);

		var gotIndex:Int = 0;

		var lmin:Float = 0;
		var lmax:Float = 0;

		var rmin:Float = 0;
		var rmax:Float = 0;

		var rows:Float = 0;

		var simpleSample:Bool = false;
		var v1:Bool = false;

		if (array == null)
			array = [[[0], [0]], [[0], [0]]];

		while (index < (bytes.length - 1)) {
			if (index >= 0) {
				var byte:Int = bytes.getUInt16(index * channels * 2);

				if (byte > 65535 / 2)
					byte -= 65535;

				var sample:Float = (byte / 65535);

				if (sample > 0)
					if (sample > lmax)
						lmax = sample;
					else if (sample < 0)
						if (sample < lmin)
							lmin = sample;

				if (channels >= 2) {
					byte = bytes.getUInt16((index * channels * 2) + 2);

					if (byte > 65535 / 2)
						byte -= 65535;

					sample = (byte / 65535);

					if (sample > 0) {
						if (sample > rmax)
							rmax = sample;
					} else if (sample < 0) {
						if (sample < rmin)
							rmin = sample;
					}
				}
			}

			v1 = samplesPerRowI > 0 ? (index % samplesPerRowI == 0) : false;
			while (simpleSample ? v1 : rows >= samplesPerRow) {
				v1 = false;
				rows -= samplesPerRow;

				gotIndex++;

				var lRMin:Float = Math.abs(lmin) * multiply;
				var lRMax:Float = lmax * multiply;

				var rRMin:Float = Math.abs(rmin) * multiply;
				var rRMax:Float = rmax * multiply;

				if (gotIndex > array[0][0].length)
					array[0][0].push(lRMin);
				else
					array[0][0][gotIndex - 1] = array[0][0][gotIndex - 1] + lRMin;

				if (gotIndex > array[0][1].length)
					array[0][1].push(lRMax);
				else
					array[0][1][gotIndex - 1] = array[0][1][gotIndex - 1] + lRMax;

				if (channels >= 2) {
					if (gotIndex > array[1][0].length)
						array[1][0].push(rRMin);
					else
						array[1][0][gotIndex - 1] = array[1][0][gotIndex - 1] + rRMin;

					if (gotIndex > array[1][1].length)
						array[1][1].push(rRMax);
					else
						array[1][1][gotIndex - 1] = array[1][1][gotIndex - 1] + rRMax;
				} else {
					if (gotIndex > array[1][0].length)
						array[1][0].push(lRMin);
					else
						array[1][0][gotIndex - 1] = array[1][0][gotIndex - 1] + lRMin;

					if (gotIndex > array[1][1].length)
						array[1][1].push(lRMax);
					else
						array[1][1][gotIndex - 1] = array[1][1][gotIndex - 1] + lRMax;
				}

				lmin = 0;
				lmax = 0;

				rmin = 0;
				rmax = 0;
			}

			index++;
			rows++;
			if (gotIndex > steps)
				break;
		}

		return array;
		#else
		return [[[0], [0]], [[0], [0]]];
		#end
	}
}
