package backend.osu;

typedef OsuConvertOptions = {
	var packName:String; // destination modpack folder under mods/
	var audioBitrate:String; // e.g. "192k"
	var convertBackground:Bool;
	var convertVideo:Bool;
	var videoCodec:String; // "vp9" | "av1"
	var videoExtraArgs:String; // raw extra ffmpeg args appended to the video encode
	var convertStoryboard:Bool; // parse the .osb, copy its images, and play it via the native storyboard runtime
	var mimicSV:Bool; // emit "Osu SV" events + bundle a script that reproduces osu! SV scrolling
	var svScript:String; // which bundled SV script to write: "lua" | "hscript"
	var quantize:Bool; // snap each note to its nearest clean beat subdivision (fixes loose timing)
}

class OsuConvertDefaults {
	public static inline var PACK_NAME:String = 'osu! Conversions';

	public static function make():OsuConvertOptions {
		return {
			packName: PACK_NAME,
			audioBitrate: '192k',
			convertBackground: true,
			convertVideo: false,
			videoCodec: 'vp9',
			videoExtraArgs: '',
			convertStoryboard: false,
			mimicSV: false,
			svScript: 'lua',
			quantize: false
		};
	}

	public static final AUDIO_BITRATES:Array<String> = ['96k', '128k', '192k', '256k', '320k'];
	public static final VIDEO_CODECS:Array<String> = ['vp9', 'av1'];

	/* Dropdown labels for the SV script language; map back to OsuConvertOptions.svScript. */
	public static final SV_SCRIPTS:Array<String> = ['Lua', 'HScript'];

	public static inline function svScriptValue(label:String):String
		return (label == 'HScript') ? 'hscript' : 'lua';
}
