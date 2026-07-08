package backend.osu;

typedef OsuConvertOptions = {
	var packName:String; // destination modpack folder under mods/
	var audioBitrate:String; // e.g. "192k"
	var convertBackground:Bool;
	var convertVideo:Bool;
	var videoCodec:String; // "vp9" | "av1"
	var videoExtraArgs:String; // raw extra ffmpeg args appended to the video encode
	var convertStoryboard:Bool; // parse the .osb, copy its images, and play it via the native storyboard runtime
	var convertHitsounds:Bool; // copy the beatmap's own hitsound samples and play them on note hit
	var mimicSV:Bool; // emit native "Scroll Velocity" events that reproduce osu! SV scrolling
	var quantize:Bool; // snap each note to its nearest clean beat subdivision (fixes loose timing)
	var stdTargetKeys:Array<Int>; // osu!std -> mania: one converted difficulty per keycount in this list
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
			convertHitsounds: true,
			mimicSV: false,
			quantize: false,
			stdTargetKeys: [4]
		};
	}

	public static final AUDIO_BITRATES:Array<String> = ['96k', '128k', '192k', '256k', '320k'];
	public static final VIDEO_CODECS:Array<String> = ['vp9', 'av1'];
}
