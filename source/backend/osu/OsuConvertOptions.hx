package backend.osu;

typedef OsuConvertOptions = {
	var packName:String; // destination modpack folder under mods/
	var audioBitrate:String; // e.g. "192k"
	var convertBackground:Bool;
	var convertVideo:Bool;
	var videoCodec:String; // "vp9" | "av1"
	var videoExtraArgs:String; // raw extra ffmpeg args appended to the video encode
	var convertStoryboard:Bool; // v1: stub (logged, not emitted)
	var mimicSV:Bool; // emit Change Scroll Speed events from inherited timing points
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
			mimicSV: false
		};
	}

	public static final AUDIO_BITRATES:Array<String> = ['96k', '128k', '192k', '256k', '320k'];
	public static final VIDEO_CODECS:Array<String> = ['vp9', 'av1'];
}
