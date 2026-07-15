package backend.tools;

import openfl.display.BitmapData;
import openfl.display.PNGEncoderOptions;
import openfl.geom.Matrix;
#if sys
import sys.io.File;
import sys.FileSystem;
import haxe.io.Path;
#end

using StringTools;

/**
 * Generic (not converter-specific) wrapper around the ffmpeg binary for
 * audio/video transcoding, plus ffmpeg detection and on-demand download. Also
 * provides a pure-OpenFL image resize. All methods return a Bool success and
 * never throw.
 */
class MediaConverter {
	/** User-set ffmpeg path (takes priority when valid); also set after a download. */
	public static var customFfmpegPath:String = null;

	/*
	 * Cached resolved ffmpeg file path. Only a POSITIVE result is cached (a missing
	 * ffmpeg stays unresolved so a later install is picked up). Invalidate by setting
	 * this to null (done after a fresh install via installFfmpegFromZip).
	 */
	static var cachedFfmpeg:String = null;

	#if desktop
	static var currentProc:sys.io.Process = null;
	static var procMutex:sys.thread.Mutex = new sys.thread.Mutex();
	#end

	/** Kills the ffmpeg process currently running (if any) so a conversion can stop. */
	public static function cancel() {
		#if desktop
		procMutex.acquire();
		var proc:sys.io.Process = currentProc;
		procMutex.release();
		if (proc != null) {
			try {
				#if windows
				Sys.command('taskkill', ['/F', '/T', '/PID', Std.string(proc.getPid())]);
				#else // macOS / Linux: taskkill doesn't exist
				Sys.command('kill', ['-9', Std.string(proc.getPid())]);
				#end
			} catch (error:Dynamic)
				trace('cancel/kill failed: $error');
		}
		#end
	}

	public static function ffmpegExe():String {
		#if sys
		var found:String = resolveFfmpegFile();
		if (found != null)
			return found;
		#end
		return 'ffmpeg'; // last resort: rely on PATH at run time
	}

	/**
	 * Locates ffmpeg as a FILE -- a custom path, the bundled tools/ folder, next to
	 * the exe, or anywhere on the system PATH -- WITHOUT spawning a process. This
	 * keeps detection instant and avoids flashing a console window on Windows.
	 */
	static function resolveFfmpegFile():String {
		#if sys
		/* Return the cached hit if it's still valid. */
		if (cachedFfmpeg != null && FileSystem.exists(cachedFfmpeg))
			return cachedFfmpeg;
		cachedFfmpeg = null;

		if (customFfmpegPath != null && customFfmpegPath.trim().length > 0 && FileSystem.exists(customFfmpegPath.trim()))
			return cachedFfmpeg = customFfmpegPath.trim();

		var cwd:String = Sys.getCwd();
		var candidates:Array<String> = [
			'tools/ffmpeg.exe',
			'tools/ffmpeg/ffmpeg.exe',
			'ffmpeg.exe',
			Path.join([cwd, 'tools', 'ffmpeg.exe']),
			Path.join([cwd, 'tools', 'ffmpeg', 'ffmpeg.exe']),
			Path.join([cwd, 'ffmpeg.exe'])
		];
		for (candidate in candidates)
			if (FileSystem.exists(candidate))
				return cachedFfmpeg = candidate;

		/* Walk PATH and look for the binary as a file (no exec -> no console flash). */
		var pathEnv:String = Sys.getEnv('PATH');
		if (pathEnv != null) {
			#if windows
			var sep:String = ';';
			var names:Array<String> = ['ffmpeg.exe'];
			#else
			var sep:String = ':';
			var names:Array<String> = ['ffmpeg'];
			#end
			for (dir in pathEnv.split(sep)) {
				if (dir == null || dir.length < 1)
					continue;
				for (name in names) {
					var full:String = Path.join([dir, name]);
					if (FileSystem.exists(full))
						return cachedFfmpeg = full;
				}
			}
		}
		#end
		return null;
	}

	/*
	 * A GPL static Windows build (includes libvorbis / libvpx / libaom) with a stable
	 * "latest" download URL.
	 */
	public static inline var DOWNLOAD_URL:String = 'https://github.com/BtbN/FFmpeg-Builds/releases/latest/download/ffmpeg-master-latest-win64-gpl.zip';
	public static inline var INSTALL_DIR:String = 'tools/ffmpeg';

	public static inline function installPath():String
		return '$INSTALL_DIR/ffmpeg.exe';

	/** Downloads `url` to `dest` via the system curl (follows redirects). */
	public static function downloadFile(url:String, dest:String):Bool {
		#if desktop
		try {
			var dir:String = Path.directory(dest);
			if (dir != null && dir.length > 0 && !FileSystem.exists(dir))
				FileSystem.createDirectory(dir);
			var code:Int = Sys.command('curl', ['-L', '--fail', '--silent', '--show-error', '-o', dest, url]);
			return code == 0 && FileSystem.exists(dest);
		} catch (error:Dynamic) {
			trace('downloadFile failed: $error');
			return false;
		}
		#else
		return false;
		#end
	}

	/** Total download size in bytes via a curl HEAD (follows redirects), or -1 if unknown. */
	public static function getContentLength(url:String):Int {
		#if desktop
		try {
			var proc = new sys.io.Process('curl', ['-sIL', url]);
			var output:String = proc.stdout.readAll().toString();
			proc.close();
			var length:Int = -1;
			for (line in output.split('\n')) {
				if (line.toLowerCase().startsWith('content-length:')) {
					var parsed:Null<Int> = Std.parseInt(line.substr(line.indexOf(':') + 1).trim());
					if (parsed != null)
						length = parsed; // keep the last one (final 200 response after redirects)
				}
			}
			return length;
		} catch (error:Dynamic) {
			return -1;
		}
		#else
		return -1;
		#end
	}

	/** Extracts just `ffmpeg.exe` from a downloaded ffmpeg zip into INSTALL_DIR. */
	public static function installFfmpegFromZip(zipPath:String):Bool {
		#if desktop
		try {
			var entries = haxe.zip.Reader.readZip(new haxe.io.BytesInput(File.getBytes(zipPath)));
			for (entry in entries) {
				var entryName:String = entry.fileName.toLowerCase().replace('\\', '/');
				if (entryName.endsWith('/ffmpeg.exe') || entryName == 'ffmpeg.exe') {
					if (!FileSystem.exists(INSTALL_DIR))
						FileSystem.createDirectory(INSTALL_DIR);
					File.saveBytes(installPath(), haxe.zip.Reader.unzip(entry));
					customFfmpegPath = installPath();
					cachedFfmpeg = installPath();
					return true;
				}
			}
		} catch (error:Dynamic) {
			trace('installFfmpegFromZip failed: $error');
		}
		#end
		return false;
	}

	public static function hasFfmpeg():Bool {
		#if sys
		return resolveFfmpegFile() != null;
		#else
		return false;
		#end
	}

	public static function convertAudio(input:String, output:String, bitrate:String, shiftMs:Float = 0):Bool {
		/*
		 * shiftMs > 0 trims that much off the start (`-ss`, fast, works on any ffmpeg);
		 * shiftMs < 0 pads that much leading silence (`adelay` -- needs a modern ffmpeg).
		 */
		var args:Array<String> = ['-y'];
		if (shiftMs > 0)
			args = args.concat(['-ss', Std.string(shiftMs / 1000)]);
		args = args.concat(['-i', input, '-vn']);
		if (shiftMs < 0) {
			/*
			 * Per-channel form (older builds lack `:all=1`); extra pipes past the real channel
			 * count are ignored, so this covers mono/stereo/5.1. Builds with no `adelay` fail
			 * (the caller falls back to trimming).
			 */
			var d:String = Std.string(Math.round(-shiftMs));
			args = args.concat(['-af', 'adelay=$d|$d|$d|$d|$d|$d']);
		}
		args = args.concat(['-c:a', 'libvorbis', '-b:a', bitrate, output]);
		return run(args);
	}

	/**
	 * Returns the leading silence (ms) at the START of an audio file via ffmpeg `silencedetect`,
	 * or 0 when the file opens with sound, detection fails, or the filter is unavailable.
	 *
	 * @param input Audio file to probe.
	 * @param thresholdDb Level below which audio counts as silence (dBFS, negative).
	 * @param minDur Minimum silence length (s) for the filter to report it.
	 */
	public static function detectLeadingSilence(input:String, thresholdDb:Float = -45, minDur:Float = 0.1):Float {
		#if desktop
		try {
			var proc:sys.io.Process = new sys.io.Process(ffmpegExe(), [
				'-i',
				input,
				'-af',
				'silencedetect=noise=${thresholdDb}dB:d=$minDur',
				'-f',
				'null',
				'-'
			]);
			/* silencedetect reports on stderr; drain stdout so its pipe can't deadlock. */
			sys.thread.Thread.create(() -> {
				try
					while (true)
						proc.stdout.readByte()
				catch (error:Dynamic) {}
			});
			var err:String = proc.stderr.readAll().toString();
			proc.exitCode(true);
			try
				proc.close()
			catch (error:Dynamic) {}

			/* A leading silence is a `silence_start` at (or near) 0 followed by a `silence_end`. */
			var startedAtZero:Bool = false;
			for (line in err.split('\n')) {
				var startAt:Int = line.indexOf('silence_start:');
				if (startAt >= 0) {
					var startVal:Float = Std.parseFloat(line.substr(startAt + 14).trim());
					startedAtZero = !Math.isNaN(startVal) && startVal <= 0.05;
					continue;
				}
				var endAt:Int = line.indexOf('silence_end:');
				if (endAt >= 0 && startedAtZero) {
					var endVal:Float = Std.parseFloat(line.substr(endAt + 12).split('|')[0].trim());
					return (!Math.isNaN(endVal) && endVal > 0) ? endVal * 1000 : 0;
				}
			}
		} catch (error:Dynamic) {
			trace('detectLeadingSilence failed: $error');
		}
		#end
		return 0;
	}

	public static function convertVideo(input:String, output:String, codec:String, extra:String):Bool {
		/*
		 * Fast, no-frills transcode: realtime mode at max speed across all CPU cores, targeting HALF
		 * the source bitrate (smaller files; backgrounds don't need full quality). Audio is dropped --
		 * the song's Inst.ogg is the audio. -deadline/-usage must be best|good|realtime (an invalid
		 * value writes a 0-byte file and the video gets silently dropped from the stage).
		 */
		var kbps:Int = detectVideoBitrateKbps(input);
		var rate:String = ((kbps > 0 ? kbps : 4000) >> 1) + 'k';
		var threads:String = Std.string(cpuCores());

		var args:Array<String> = ['-y', '-i', input, '-an', '-row-mt', '1', '-threads', threads];
		if (codec == 'av1')
			args = args.concat(['-c:v', 'libaom-av1', '-usage', 'realtime', '-cpu-used', '8', '-b:v', rate]);
		else
			args = args.concat(['-c:v', 'libvpx-vp9', '-deadline', 'realtime', '-cpu-used', '8', '-b:v', rate]);

		if (extra != null && extra.trim().length > 0)
			for (arg in extra.trim().split(' '))
				if (arg.length > 0)
					args.push(arg);
		args.push(output);
		return run(args);
	}

	/** Logical CPU core count (Windows `NUMBER_OF_PROCESSORS`), for maxing ffmpeg threads; 4 if unknown. */
	public static function cpuCores():Int {
		#if sys
		var env:String = Sys.getEnv('NUMBER_OF_PROCESSORS');
		if (env != null) {
			var n:Null<Int> = Std.parseInt(env);
			if (n != null && n > 0)
				return n;
		}
		#end
		return 4;
	}

	/**
	 * Reads the source's overall bitrate (kb/s) from ffmpeg's input banner, used to target a
	 * similar output size. Returns 0 if it can't be parsed.
	 */
	public static function detectVideoBitrateKbps(input:String):Int {
		#if desktop
		try {
			/* `ffmpeg -i <file>` prints the stream banner to stderr then exits (no decode) -- fast. */
			var proc:sys.io.Process = new sys.io.Process(ffmpegExe(), ['-i', input]);
			sys.thread.Thread.create(() -> {
				try
					while (true)
						proc.stdout.readByte()
				catch (error:Dynamic) {}
			});
			var err:String = proc.stderr.readAll().toString();
			proc.exitCode(true);
			try
				proc.close()
			catch (error:Dynamic) {}

			for (line in err.split('\n')) {
				var at:Int = line.indexOf('bitrate:'); // "Duration: .., bitrate: 1234 kb/s"
				if (at >= 0) {
					var value:Null<Int> = Std.parseInt(line.substr(at + 8).trim().split(' ')[0]);
					if (value != null && value > 0)
						return value;
				}
			}
		} catch (error:Dynamic) {
			trace('detectVideoBitrateKbps failed: $error');
		}
		#end
		return 0;
	}

	static function run(args:Array<String>):Bool {
		#if desktop
		try {
			var proc:sys.io.Process = new sys.io.Process(ffmpegExe(), args);
			procMutex.acquire();
			currentProc = proc;
			procMutex.release();

			/* Drain stdout/stderr so ffmpeg's pipe buffers don't fill and deadlock. */
			var drain = function(stream:haxe.io.Input) {
				try
					while (true)
						stream.readByte()
				catch (error:Dynamic) {}
			};
			sys.thread.Thread.create(() -> drain(proc.stdout));
			sys.thread.Thread.create(() -> drain(proc.stderr));

			var code:Int = proc.exitCode(true);

			procMutex.acquire();
			currentProc = null;
			procMutex.release();
			try
				proc.close()
			catch (error:Dynamic) {}
			return code == 0;
		} catch (error:Dynamic) {
			trace('ffmpeg run failed: $error');
			procMutex.acquire();
			currentProc = null;
			procMutex.release();
			return false;
		}
		#else
		return false;
		#end
	}

	/** Writes a fully transparent `width`x`height` PNG to `output`. */
	public static function writeBlankPng(output:String, width:Int = 1, height:Int = 1):Bool {
		#if sys
		try {
			var dir:String = Path.directory(output);
			if (dir != null && dir.length > 0 && !FileSystem.exists(dir))
				FileSystem.createDirectory(dir);
			var bmp:BitmapData = new BitmapData(width, height, true, 0x00000000);
			File.saveBytes(output, bmp.encode(bmp.rect, new PNGEncoderOptions()));
			bmp.dispose();
			return true;
		} catch (error:Dynamic) {
			trace('writeBlankPng failed: $error');
			return false;
		}
		#else
		return false;
		#end
	}

	/** Resize `input` to cover `width`x`height` and write a PNG to `output`. */
	public static function resizeImage(input:String, output:String, width:Int = 1280, height:Int = 720):Bool {
		#if sys
		try {
			var source:BitmapData = BitmapData.fromFile(input);
			if (source == null)
				return false;

			var target:BitmapData = new BitmapData(width, height, true, 0xFF000000);
			var scale:Float = Math.max(width / source.width, height / source.height); // cover
			var matrix:Matrix = new Matrix();
			matrix.scale(scale, scale);
			matrix.translate((width - source.width * scale) / 2, (height - source.height * scale) / 2);
			target.draw(source, matrix, null, null, null, true);

			var bytes = target.encode(target.rect, new PNGEncoderOptions());
			File.saveBytes(output, bytes);

			source.dispose();
			target.dispose();
			return true;
		} catch (error:Dynamic) {
			trace('resizeImage failed: $error');
			return false;
		}
		#else
		return false;
		#end
	}
}
