package editors.charting.data;

import flixel.FlxG;

/**
	Persisted editor display/behavior options (`FlxG.save.data.chartEditorPrefs`).
	Load once on state boot, save on exit and after toggles change.
**/
final class EditorPrefs {
	/** Waveform overlay toggle. **/
	public static var waveform:Bool = true;

	/** Metronome toggle. **/
	public static var metronome:Bool = false;

	/** Hitsounds toggle. **/
	public static var hitsounds:Bool = false;

	/** Vortex editor toggle (playhead receptors + number-key placing). **/
	public static var vortex:Bool = false;

	/** Quantized note coloring toggle. **/
	public static var quantColors:Bool = false;

	/** Downscroll toggle (time flows upward). **/
	public static var downscroll:Bool = false;

	/** Single-dock layout toggle (right dock folded into the rail). **/
	public static var combinedDock:Bool = false;

	/** Persisted grid snap index (into `SnapGrid.SNAPS`). **/
	public static var snapIndex:Int = 3;

	/** Persisted grid zoom index. **/
	public static var zoomIndex:Int = 2;

	/** Playback rate index (session-only: never persisted, always opens at 1x). **/
	public static var rateIndex:Int = 3;

	/** UI density multiplier. **/
	public static var uiScale:Float = 1.0;

	/** Instrumental volume (session-only). **/
	public static var instVol:Float = 1.0;

	/** Player vocals volume (session-only). **/
	public static var mainVol:Float = 1.0;

	/** Opponent vocals volume (session-only). **/
	public static var oppVol:Float = 1.0;

	/** Player-side hitsound volume (0 = off). **/
	public static var hitsoundP:Float = 0.6;

	/** Opponent-side hitsound volume (0 = off). **/
	public static var hitsoundO:Float = 0.0;

	/** Metronome sound preset index. **/
	public static var metroPreset:Int = 0;

	/** Accent the first beat of each section with a pitched tick. **/
	public static var metroAccent:Bool = true;

	/** Max pooled note drawables kept per pool (0 = unlimited/dynamic). **/
	public static var notePoolCap:Int = 0;

	/** Waveform source: 0 = inst, 1 = player vocals, 2 = opponent vocals. **/
	public static var waveTarget:Int = 0;

	/** Reads the persisted options from the save file (missing keys keep their defaults). **/
	public static function load():Void {
		var d:Dynamic = FlxG.save.data.chartEditorPrefs;
		if (d == null)
			return;
		if (d.waveform != null)
			waveform = d.waveform;
		if (d.metronome != null)
			metronome = d.metronome;
		if (d.hitsounds != null)
			hitsounds = d.hitsounds;
		if (d.vortex != null)
			vortex = d.vortex;
		if (d.quantColors != null)
			quantColors = d.quantColors;
		if (d.downscroll != null)
			downscroll = d.downscroll;
		if (d.combinedDock != null)
			combinedDock = d.combinedDock;
		if (d.snapIndex != null)
			snapIndex = d.snapIndex;
		if (d.zoomIndex != null)
			zoomIndex = d.zoomIndex;
		if (d.uiScale != null)
			uiScale = d.uiScale;
		// audio volumes + rate intentionally NOT loaded: they persist across states via
		// these statics, but reset with each game launch (user request)
		if (d.hitsoundP != null)
			hitsoundP = d.hitsoundP;
		if (d.hitsoundO != null)
			hitsoundO = d.hitsoundO;
		if (d.metroPreset != null)
			metroPreset = d.metroPreset;
		if (d.metroAccent != null)
			metroAccent = d.metroAccent;
		if (d.notePoolCap != null)
			notePoolCap = d.notePoolCap;
		if (d.waveTarget != null)
			waveTarget = d.waveTarget;
	}

	/** Writes the persisted options to the save file and flushes it. **/
	public static function save():Void {
		FlxG.save.data.chartEditorPrefs = {
			waveform: waveform,
			metronome: metronome,
			hitsounds: hitsounds,
			vortex: vortex,
			quantColors: quantColors,
			downscroll: downscroll,
			combinedDock: combinedDock,
			snapIndex: snapIndex,
			zoomIndex: zoomIndex,
			uiScale: uiScale,
			hitsoundP: hitsoundP,
			hitsoundO: hitsoundO,
			metroPreset: metroPreset,
			metroAccent: metroAccent,
			notePoolCap: notePoolCap,
			waveTarget: waveTarget
		};
		FlxG.save.flush();
	}
}
