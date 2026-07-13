package backend;

import haxe.io.Path;

#if android
import extension.androidtools.jni.JNICache;
import extension.androidtools.os.Build;
import lime.system.JNI;
#end

/**
	Generates an OpenAL-Soft config tuned for low latency and points `ALSOFT_CONF` at it before the
	audio device is opened. Output buffering (`period_size`/`periods`) is driven by the user's
	`audioBuffer` preference; the quality settings are fixed.

	OpenAL-Soft reads this config only when it opens the device at startup, so a changed preference
	only takes effect on the next launch -- an already-open device can't be re-buffered live.

	`apply()` MUST run after `FlxG.save` is bound (so the preference is readable) and before the
	`FlxGame` is created (so the device opens with the config). On desktop, `__init__` first points
	`ALSOFT_CONF` at the config shipped beside the executable, so that stays as a fallback if
	generation fails.
**/
@:keep class ALSoftConfig {
	#if desktop
	static function __init__():Void {
		var origin:String = #if hl Sys.getCwd() #else Sys.programPath() #end;

		var configPath:String = Path.directory(Path.withoutExtension(origin));
		#if windows
		configPath += "/plugins/alsoft.ini";
		#elseif mac
		configPath = Path.directory(configPath) + "/Resources/plugins/alsoft.conf";
		#else
		configPath += "/plugins/alsoft.conf";
		#end

		Sys.putEnv("ALSOFT_CONF", configPath);
	}
	#end

	/**
		Writes the preference-driven config to a writable location and repoints `ALSOFT_CONF` at it.
		No-op on targets without OpenAL-Soft (e.g. html5).
	**/
	/** The buffer preset actually applied at startup, so menus can detect a pending restart-required change. **/
	public static var appliedBuffer:String = 'Balanced';

	public static function apply():Void {
		#if (desktop || android)
		var name:String = 'Balanced';
		try {
			final saved:Dynamic = flixel.FlxG.save.data.audioBuffer;
			if (saved != null)
				name = saved;
		} catch (_:Dynamic) {}
		appliedBuffer = name;

		final p = preset(name);
		var periodSize:Int = p.periodSize;
		var freqLine:String = '';

		#if android
		// Match the device's native output so OpenAL-Soft's buffer lines up with the hardware
		// granularity (frames-per-buffer) instead of the oversized default streaming buffer.
		final native = queryNativeParams();
		if (native != null) {
			if (native.frames > 0)
				periodSize = native.frames;
			if (native.rate > 0)
				freqLine = 'frequency=${native.rate}\n';
		}
		final resampler:String = 'cubic'; // lighter on mobile CPU
		#else
		final resampler:String = 'fast_bsinc24';
		// Desktop deliberately does NOT force `frequency`: OpenAL-Soft already matches the device's
		// mix rate over WASAPI/CoreAudio, so forcing one would risk a redundant resample.
		#end

		final conf:String = '[general]\n'
			+ 'sample-type=float32\n'
			+ 'stereo-mode=speakers\n'
			+ 'stereo-encoding=panpot\n'
			+ 'hrtf=false\n'
			+ 'cf_level=0\n'
			+ 'resampler=$resampler\n'
			+ 'front-stablizer=false\n'
			+ 'output-limiter=false\n'
			+ 'volume-adjust=0\n'
			+ freqLine
			+ 'period_size=$periodSize\n'
			+ 'periods=${p.periods}\n'
			+ '[decoder]\n'
			+ 'hq-mode=false\n'
			+ 'distance-comp=false\n'
			+ 'nfc=false\n';

		try {
			final dir:String = lime.system.System.applicationStorageDirectory;
			if (!sys.FileSystem.exists(dir))
				sys.FileSystem.createDirectory(dir);
			final path:String = Path.join([dir, 'alsoft.ini']);
			sys.io.File.saveContent(path, conf);
			Sys.putEnv('ALSOFT_CONF', path);
		} catch (e:Dynamic) {
			trace('ALSoftConfig: failed to write generated config: $e');
		}
		#end
	}

	/** Output buffering presets: period count + desktop period size. Lower = less latency, more underrun risk. **/
	static function preset(name:String):{periods:Int, periodSize:Int} {
		return switch (name) {
			case 'Low': {periods: 2, periodSize: 256};
			case 'Safe': {periods: 4, periodSize: 1024};
			default: {periods: 3, periodSize: 512}; // Balanced
		}
	}

	#if android
	/**
		Reads the device's native output sample rate and frames-per-buffer via
		`AudioManager.getProperty` (API 17+). Returns `null` if unavailable, so the caller falls back
		to the preset's conservative period size.
	**/
	static function queryNativeParams():Null<{rate:Int, frames:Int}> {
		if (VERSION.SDK_INT < 17)
			return null;

		try {
			final contextField:Null<Dynamic> = JNICache.createStaticField('org/haxe/extension/Extension', 'mainContext', 'Landroid/content/Context;');
			if (contextField == null)
				return null;
			final context:Null<Dynamic> = contextField.get();
			if (context == null)
				return null;

			final getSystemService:Null<Dynamic> = JNICache.createMemberMethod('android/content/Context', 'getSystemService',
				'(Ljava/lang/String;)Ljava/lang/Object;');
			if (getSystemService == null)
				return null;
			final audioManager:Null<Dynamic> = JNI.callMember(getSystemService, context, ['audio']);
			if (audioManager == null)
				return null;

			final getProperty:Null<Dynamic> = JNICache.createMemberMethod('android/media/AudioManager', 'getProperty',
				'(Ljava/lang/String;)Ljava/lang/String;');
			if (getProperty == null)
				return null;

			final rateStr:Null<String> = JNI.callMember(getProperty, audioManager, ['android.media.property.OUTPUT_SAMPLE_RATE']);
			final framesStr:Null<String> = JNI.callMember(getProperty, audioManager, ['android.media.property.OUTPUT_FRAMES_PER_BUFFER']);

			final rate:Null<Int> = (rateStr != null) ? Std.parseInt(rateStr) : null;
			final frames:Null<Int> = (framesStr != null) ? Std.parseInt(framesStr) : null;

			return {rate: (rate != null) ? rate : 0, frames: (frames != null) ? frames : 0};
		} catch (e:Dynamic) {
			trace('ALSoftConfig: native audio param query failed: $e');
			return null;
		}
	}
	#end
}
