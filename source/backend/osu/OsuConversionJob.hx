package backend.osu;

import backend.Song.SwagSong;
import backend.osu.OszArchive.OsuSource;
import backend.tools.MediaConverter;
import states.editors.content.PsychJsonPrinter;
#if sys
import sys.io.File;
import sys.FileSystem;
import haxe.io.Path;
#end

using StringTools;

/**
 * Orchestrates one full osu! mapset conversion: builds the modpack folders, writes
 * the per-difficulty charts, transcodes audio/background/video, emits a stage
 * script + data, and writes per-song metadata so it shows in Freeplay.
 *
 * All steps are logged through the `log` callback; failures are non-fatal where
 * possible (a missing ffmpeg skips audio/video but still writes charts).
 */
class OsuConversionJob {
	/**
	 * The play-time storyboard runtime is only ever invoked from a generated Lua `import()`
	 * string -- not a Haxe reference -- so without this it would never be compiled into the
	 * engine and the import would return nil at runtime. Touching the type here forces it in
	 * (with `@:keep` on the class so DCE keeps it).
	 */
	@:keep static var _forceStoryboardRuntime:Class<OsuStoryboardPlayer> = OsuStoryboardPlayer;

	var log:String->Void;
	var progress:Float->String->Void;
	var isCancelled:Void->Bool;
	var totalSteps:Int = 1;
	var doneSteps:Int = 0;

	var opts:OsuConvertOptions;
	var src:OsuSource;
	var maps:Array<OsuBeatmap> = [];
	var packDir:String = '';
	var songKey:String = '';
	var stageName:String = '';
	var display:String = '';
	var audioTrimMs:Int = 0; // ms trimmed off the audio start; charts shift to match (offset stays 0)

	/* Pure leading silence (no alignment) below this (ms) isn't worth trimming the whole chart for. */
	static inline var MIN_SILENCE_TRIM_MS:Int = 50;

	/* Beat phase below this (ms) is treated as already aligned -- skip the alignment trim. */
	static inline var ALIGN_EPSILON_MS:Float = 1;

	public function new(log:String->Void, ?progress:Float->String->Void, ?isCancelled:Void->Bool) {
		this.log = (log != null) ? log : function(_) {};
		this.progress = (progress != null) ? progress : function(_, _) {};
		this.isCancelled = (isCancelled != null) ? isCancelled : function() return false;
	}

	inline function report(label:String)
		progress(totalSteps > 0 ? doneSteps / totalSteps : 0, label);

	inline function stepDone()
		doneSteps++;

	public function run(src:OsuSource, opts:OsuConvertOptions):Bool {
		#if sys
		this.src = src;
		this.opts = opts;

		if (src == null || src.osuFiles == null || src.osuFiles.length < 1) {
			log('No .osu files found in the input.');
			return false;
		}

		maps = parseCharts();
		if (maps.length < 1) {
			log('No supported osu! difficulties found (only osu!mania and osu!std are supported).');
			return false;
		}

		resolveNames();
		createPackFolders();

		log('Converting "$display" ($songKey) - ${maps.length} difficulty(ies).');
		if (opts.quantize)
			log('Quantize ON: each note snapped to its nearest clean subdivision, timeline aligned to sections.');
		totalSteps = countSteps();

		report('Starting...');

		convertAudio();
		if (cancelledNow())
			return false;

		var hasBg:Bool = convertBackground();
		if (cancelledNow())
			return false;

		var hasVideo:Bool = convertVideo();
		if (cancelledNow())
			return false;

		var hasStoryboard:Bool = convertStoryboard();
		if (cancelledNow())
			return false;

		var versions:Array<String> = writeCharts();
		if (versions == null)
			return false;

		report('Finalizing (stage + metadata)...');

		writeStage(hasBg, hasVideo, hasStoryboard, maps[0].widescreenStoryboard);
		stepDone();

		if (opts.mimicSV)
			writeSvScript();

		writeSongMetadata(versions);
		stepDone();

		report('Done.');

		log('"$display": Done');
		return true;
		#else
		return false;
		#end
	}

	/* -- Conversion -- */
	#if sys
	function parseCharts():Array<OsuBeatmap> {
		var result:Array<OsuBeatmap> = [];
		for (osuPath in src.osuFiles) {
			var map:OsuBeatmap = OsuParser.parse(File.getContent(osuPath));
			var fileName:String = Path.withoutDirectory(osuPath);
			if (map.isMania()) {
				if (map.keyCount > 9)
					log('Skipped (${map.keyCount}K co-op, >9 columns): $fileName');
				else
					result.push(map);
			} else if (map.isStd())
				result.push(map);
			else
				log('Skipped (unsupported mode, only std/mania): $fileName');
		}

		var hasMania:Bool = false;
		for (map in result)
			if (map.isMania()) {
				hasMania = true;
				break;
			}
		if (hasMania) {
			var maniaOnly:Array<OsuBeatmap> = [];
			for (map in result) {
				if (map.isStd())
					log('Skipped osu!std "${map.version}" (mapset already has osu!mania difficulties).');
				else
					maniaOnly.push(map);
			}
			result = maniaOnly;
		}
		return result;
	}

	function stdPasses():Array<Int> {
		var out:Array<Int> = [];
		var seen:Map<Int, Bool> = new Map();
		if (opts.stdTargetKeys != null)
			for (k in opts.stdTargetKeys)
				if (k >= 1 && k <= 9 && !seen.exists(k)) {
					seen.set(k, true);
					out.push(k);
				}
		if (out.length < 1)
			out.push(4);
		return out;
	}

	function resolveNames() {
		var title:String = maps[0].title;
		display = (title != null && title.trim().length > 0) ? title.trim() : 'osu song';
		songKey = Paths.formatToSongPath(display);
		if (songKey.length < 1)
			songKey = 'osu-song';
		stageName = 'osu_$songKey';
	}

	function createPackFolders() {
		packDir = Paths.mods(opts.packName);
		for (sub in ['', 'data', 'songs', 'images', 'videos', 'stages', 'sounds'])
			OszArchive.ensureDir(sub.length < 1 ? packDir : '$packDir/$sub');
		ensurePack(opts.packName);
		ensureBlankCharacters();
		writeSettings();
	}

	function writeSettings() {
		var path:String = '$packDir/data/settings.json';
		if (FileSystem.exists(path) && isOptionArray(path))
			return;
		OszArchive.ensureDir('$packDir/data');
		var entries:Array<Dynamic> = [
			{
				save: 'osu_header',
				name: '-OSU! SETTINGS-',
				type: 'string',
				description: 'Options for osu! converts',
				value: ' ',
				options: [' ', ' ', ' ', ' ']
			},
			{
				save: 'osu_showBackground',
				name: 'Show Background',
				type: 'bool',
				description: 'Show the converted song background image.',
				value: true
			},
			{
				save: 'osu_showStory',
				name: 'Show Storyboard',
				type: 'bool',
				description: 'Play the converted osu! storyboard, when the song has one.',
				value: true
			},
			{
				save: 'osu_showVideo',
				name: 'Show Video',
				type: 'bool',
				description: 'Play the converted background video, when the song has one.',
				value: true
			},
			{
				save: 'osu_backgroundDim',
				name: 'Background Dim',
				type: 'float',
				description: 'Darken the background / video / storyboard.\n0 = none, 1 = fully black.',
				value: 0.5,
				min: 0,
				max: 1,
				step: 0.05,
				decimals: 2
			},
			{
				save: 'osu_mimicSV',
				name: 'Mimic osu! SV',
				type: 'bool',
				description: 'Reproduce osu! slider-velocity scrolling.\nOnly affects songs converted with SV enabled.',
				value: true
			},
			{
				save: 'osu_hitsounds',
				name: 'Hitsounds',
				type: 'bool',
				description: 'Play hitsounds embedded in the beatmap (custom samples only).',
				value: true
			}
		];
		File.saveContent(path, haxe.Json.stringify(entries, null, '\t'));
	}

	function isOptionArray(path:String):Bool {
		try {
			return Std.isOfType(haxe.Json.parse(File.getContent(path)), Array);
		} catch (e:Dynamic) {
			return false;
		}
	}

	function countSteps():Int {
		var audio:Int = (maps[0].audioFilename != null) ? 1 : 0;
		var bg:Int = opts.convertBackground ? 1 : 0;
		var video:Int = opts.convertVideo ? 1 : 0;
		var storyboard:Int = opts.convertStoryboard ? 1 : 0;
		return audio + bg + video + storyboard + chartCount() + 2; // +2 = stage + metadata
	}

	function chartCount():Int {
		var passes:Int = stdPasses().length;
		var count:Int = 0;
		for (map in maps)
			count += map.isStd() ? passes : 1;
		return count;
	}

	function convertAudio() {
		var audioName:String = maps[0].audioFilename;
		if (audioName == null)
			return;

		report('Transcoding audio...');

		var input:String = findFile(src.dir, audioName);
		if (input == null) {
			log('Audio file not found in mapset: $audioName');
		} else {
			OszArchive.ensureDir('$packDir/songs/$songKey');
			var output:String = '$packDir/songs/$songKey/Inst.ogg';
			audioTrimMs = computeAudioShift(input);

			log('Transcoding audio -> Inst.ogg (${opts.audioBitrate})...');
			if (audioTrimMs != 0)
				log((audioTrimMs > 0 ? '  trimming ${audioTrimMs}ms off' : '  padding ${- audioTrimMs}ms of silence onto')
					+ ' the start (charts shift to match; song.offset stays 0).');

			var ok:Bool = MediaConverter.convertAudio(input, output, opts.audioBitrate, audioTrimMs);
			if (!ok && audioTrimMs < 0) {
				/* Padding needs an ffmpeg with `adelay`; if it isn't there, align by trimming instead. */
				audioTrimMs = Std.int(Math.min(OsuChartConverter.beatAlignment(maps[0]).phase, earliestNoteTime()));
				log('  padding unavailable; trimming ${audioTrimMs}ms to align instead.');
				ok = MediaConverter.convertAudio(input, output, opts.audioBitrate, audioTrimMs);
			}
			if (audioTrimMs != 0)
				applyAudioTrim();
			log(ok ? '  audio OK' : '  audio FAILED (is ffmpeg available?) - song will have no instrumental');
		}
		stepDone();
	}

	/**
	 * Signed audio shift (ms): `> 0` trims that much off the start, `< 0` pads that much leading
	 * silence. The same shift is applied to every chart (`applyAudioTrim`) so audio and notes move
	 * together and `song.offset` stays 0.
	 *
	 * It does two jobs, both content-safe:
	 *  - **Beat alignment (quantize only):** slide osu's beat grid onto the engine's 0-anchored grid
	 *    (the sub-beat `phase`) so quantize snaps notes to clean subdivisions ("snap up to the red
	 *    line"). If leading silence covers the phase it's trimmed; otherwise we take the nearest beat
	 *    -- a tiny trim into the lead-in, or a pad (never cutting real audio).
	 *  - **Dead air:** when trimming, also drop whole beats of leading silence so the song doesn't
	 *    open on silence (whole beats keep the grid aligned).
	 *
	 * Trims are capped at the earliest note so no note is pushed before 0; pads never risk that.
	 */
	function computeAudioShift(input:String):Int {
		var earliest:Float = earliestNoteTime();
		var silence:Float = Math.min(MediaConverter.detectLeadingSilence(input), earliest);

		var align:{beatLength:Float, phase:Float} = OsuChartConverter.beatAlignment(maps[0]);
		var beatLength:Float = align.beatLength;
		var phase:Float = align.phase;
		if (beatLength <= 0)
			return 0;

		/* No alignment wanted (quantize off, or already on-grid): just drop whole beats of dead air. */
		if (!opts.quantize || phase < ALIGN_EPSILON_MS) {
			var t:Float = 0;
			while (t + beatLength <= silence)
				t += beatLength;
			return (t >= MIN_SILENCE_TRIM_MS) ? Std.int(Math.min(t, earliest)) : 0;
		}

		/* Enough lead-in silence to absorb the phase -> trim it (content-safe) + extra dead-air beats. */
		if (silence >= phase) {
			var t:Float = phase;
			while (t + beatLength <= silence)
				t += beatLength;
			return Std.int(Math.min(t, earliest));
		}

		/**  Not enough silence: take the nearest beat (smallest possible shift, |s| <= beatLength/2). */
		if (phase <= beatLength / 2)
			return Std.int(Math.min(phase, earliest)); // trim earlier (≤ half a beat of lead-in)
		return -Std.int(beatLength - phase); // pad later (≤ half a beat of silence, no audio lost)
	}

	/** Earliest hit-object time (ms) across all difficulties, or 0 when there are no notes. */
	function earliestNoteTime():Float {
		var earliest:Float = Math.POSITIVE_INFINITY;
		for (map in maps)
			if (map.hitObjects.length > 0 && map.hitObjects[0].time < earliest)
				earliest = map.hitObjects[0].time;
		return (earliest == Math.POSITIVE_INFINITY) ? 0 : earliest;
	}

	/** Shifts every chart time by `audioTrimMs` (earlier when trimming, later when padding) to track the audio. */
	function applyAudioTrim() {
		for (map in maps) {
			for (obj in map.hitObjects) {
				obj.time -= audioTrimMs;
				if (obj.endTime > 0)
					obj.endTime -= audioTrimMs;
			}
			for (point in map.timingPoints)
				point.time -= audioTrimMs;
		}
	}

	function convertBackground():Bool {
		if (!opts.convertBackground)
			return false;

		report('Resizing background...');

		var hasBg:Bool = false;
		var input:String = findMedia(map -> map.background);
		if (input != null) {
			log('Resizing background -> 1280x720...');
			hasBg = MediaConverter.resizeImage(input, '$packDir/images/${stageName}_bg.png');
			log(hasBg ? '  background OK' : '  background resize FAILED');
		} else
			log('No background image found in the mapset.');

		stepDone();
		return hasBg;
	}

	function convertVideo():Bool {
		if (!opts.convertVideo)
			return false;

		report('Transcoding video (slow)...');

		var hasVideo:Bool = false;
		var input:String = findMedia(map -> map.video);
		if (input != null) {
			log('Transcoding video -> ${opts.videoCodec} WebM (this can be slow)...');
			hasVideo = MediaConverter.convertVideo(input, '$packDir/videos/$stageName.webm', opts.videoCodec, opts.videoExtraArgs);
			log(hasVideo ? '  video OK (experimental playback)' : '  video FAILED (is ffmpeg available?)');
		} else
			log('No video found in the mapset.');

		stepDone();
		return hasVideo;
	}

	/**
	 * Parses the mapset's `.osb`, copies the images it references into the modpack, and ships
	 * the `.osb` alongside the stage so the generated stage script can play it at runtime. The
	 * storyboard timeline isn't rewritten -- the runtime is given `audioTrimMs` so it tracks the
	 * same audio shift the charts got. Returns whether a storyboard was written.
	 */
	function convertStoryboard():Bool {
		if (!opts.convertStoryboard)
			return false;

		report('Converting storyboard...');

		var osbPath:String = findOsb(src.dir);
		if (osbPath == null) {
			log('No .osb storyboard found in the mapset.');
			stepDone();
			return false;
		}

		var sb:OsuStoryboard = OsuStoryboard.parse(File.getContent(osbPath));
		if (sb.isEmpty()) {
			log('Storyboard has no sprites - skipped.');
			stepDone();
			return false;
		}

		var imageBase:String = '$packDir/images/${stageName}_sb';
		var soundBase:String = '$packDir/sounds/${stageName}_sb';
		var copied:Int = copyStoryboardImages(sb, imageBase);
		var samplesCopied:Int = copyStoryboardSamples(sb, soundBase);
		File.copy(osbPath, '$packDir/stages/$stageName.osb');

		log('Storyboard -> ${sb.objects.length} objects, $copied/${sb.imagePaths().length} images, '
			+ '$samplesCopied/${sb.samplePaths().length} samples copied'
			+ (audioTrimMs != 0 ? ' (timeline offset ${audioTrimMs}ms to match audio)' : '')
			+ '.');
		stepDone();
		return true;
	}

	/** First `.osb` file in the mapset directory, or null. */
	function findOsb(dir:String):String {
		for (entry in FileSystem.readDirectory(dir))
			if (entry.toLowerCase().endsWith('.osb'))
				return Path.join([dir, entry]);
		return null;
	}

	/** Copies every image a storyboard references into `destBase`, preserving relative paths. */
	function copyStoryboardImages(sb:OsuStoryboard, destBase:String):Int {
		var copied:Int = 0;
		for (p in sb.imagePaths()) {
			var input:String = resolveNested(src.dir, p);
			if (input == null)
				continue;
			var dest:String = Path.join([destBase, p.split('\\').join('/')]);
			OszArchive.ensureDir(Path.directory(dest));
			try {
				File.copy(input, dest);
				copied++;
			} catch (e:Dynamic) {}
		}
		return copied;
	}

	/** Copies every audio sample a storyboard references into `destBase`, preserving relative paths. */
	function copyStoryboardSamples(sb:OsuStoryboard, destBase:String):Int {
		var copied:Int = 0;
		for (p in sb.samplePaths()) {
			var input:String = resolveNested(src.dir, p);
			if (input == null)
				continue;
			var dest:String = Path.join([destBase, p.split('\\').join('/')]);
			OszArchive.ensureDir(Path.directory(dest));
			try {
				File.copy(input, dest);
				copied++;
			} catch (e:Dynamic) {}
		}
		return copied;
	}

	/** Resolves a (possibly nested, backslash) relative path under `root`, case-insensitively. */
	function resolveNested(root:String, osuPath:String):String {
		var rel:String = osuPath.split('\\').join('/');
		var direct:String = Path.join([root, rel]);
		if (FileSystem.exists(direct))
			return direct;

		var dir:String = root;
		for (part in rel.split('/')) {
			if (!FileSystem.exists(dir) || !FileSystem.isDirectory(dir))
				return null;
			var want:String = part.toLowerCase();
			var found:String = null;
			for (entry in FileSystem.readDirectory(dir))
				if (entry.toLowerCase() == want) {
					found = entry;
					break;
				}
			if (found == null)
				return null;
			dir = Path.join([dir, found]);
		}
		return FileSystem.exists(dir) ? dir : null;
	}

	function writeCharts():Array<String> {
		OszArchive.ensureDir('$packDir/data/$songKey');
		var entries:Array<{label:String, notes:Int}> = [];
		var usedKeys:Map<String, Bool> = new Map();
		var passes:Array<Int> = stdPasses();
		var total:Int = chartCount();
		var index:Int = 0;
		var copiedHit:Map<String, Bool> = new Map();
		var anyHit:Bool = false;

		for (map in maps) {
			var keyList:Array<Int> = map.isStd() ? passes : [map.keyCount];
			for (keys in keyList) {
				if (cancelledNow())
					return null;

				report('Writing chart ${++index}/$total...');

				var hsOut:Array<{time:Float, sounds:Array<{file:String, volume:Float}>}> = opts.convertHitsounds ? [] : null;
				var song:SwagSong = OsuChartConverter.convert(map, display, stageName, opts.mimicSV, opts.quantize, keys, hsOut);
				if (song == null) {
					log('Chart conversion failed for version "${map.version}" (${keys}K).');
					stepDone();
					continue;
				}

				if (hsOut != null && hsOut.length > 0 && appendHitsoundEvents(song, hsOut, copiedHit))
					anyHit = true;

				var fileKey:String = uniqueKey(diffKey(map, keys), usedKeys);
				var fileName:String = '$songKey-$fileKey.json';
				File.saveContent('$packDir/data/$songKey/$fileName', '{"song":' + PsychJsonPrinter.print(song, ['sectionNotes', 'events']) + '}');

				var notes:Int = countNotes(song);
				entries.push({label: diffLabel(map, keys), notes: notes});

				log('  chart -> $fileName (${keys}K, $notes notes, speed ${song.speed})');
				stepDone();
			}
		}

		if (entries.length < 1) {
			log('No charts were written.');
			return null;
		}
		if (anyHit) {
			writeHitsoundScript();
			log('Hitsounds -> bundled (custom samples found in the beatmap).');
		} else if (opts.convertHitsounds)
			log('Hitsounds -> none bundled (this beatmap relies on osu!\'s default skin, which can\'t be shipped).');
		entries.sort((a, b) -> a.notes - b.notes);
		return [for (entry in entries) entry.label];
	}

	/** Copies present hitsound samples and appends per-note "Osu Hitsounds" events to the song. */
	function appendHitsoundEvents(song:SwagSong, hsOut:Array<{time:Float, sounds:Array<{file:String, volume:Float}>}>, copiedHit:Map<String, Bool>):Bool {
		var hitDir:String = '$packDir/sounds/${stageName}_hit';
		var added:Bool = false;

		for (entry in hsOut) {
			var parts:Array<String> = [];
			for (snd in entry.sounds) {
				var rel:String = snd.file.split('\\').join('/');
				if (!copiedHit.exists(rel)) {
					var ok:Bool = false;
					var input:String = resolveNested(src.dir, snd.file);
					if (input != null) {
						var dest:String = Path.join([hitDir, rel]);
						OszArchive.ensureDir(Path.directory(dest));
						try {
							File.copy(input, dest);
							ok = true;
						} catch (e:Dynamic) {}
					}
					copiedHit.set(rel, ok);
				}
				if (copiedHit.get(rel) == true)
					parts.push(rel + ':' + Std.int(snd.volume));
			}
			if (parts.length > 0) {
				song.events.push([entry.time, [["Osu Hitsounds", parts.join('|'), ""]]]);
				added = true;
			}
		}

		if (added)
			song.events.sort((a, b) -> {
				var ta:Float = a[0], tb:Float = b[0];
				return (ta < tb) ? -1 : (ta > tb ? 1 : 0);
			});
		return added;
	}

	function writeStage(hasBg:Bool, hasVideo:Bool, hasStoryboard:Bool, widescreen:Bool) {
		File.saveContent('$packDir/stages/$stageName.lua', genStageLua(hasBg, hasVideo, hasStoryboard, widescreen));
		OszArchive.ensureDir('$packDir/data/stages');
		File.saveContent('$packDir/data/stages/$stageName.json', genStageJson());
	}

	/* -- Helpers -- */
	function cancelledNow():Bool {
		if (isCancelled()) {
			log('Conversion cancelled. Partial files may remain in the modpack.');
			return true;
		}
		return false;
	}

	function findMedia(pick:OsuBeatmap->String):String {
		for (map in maps) {
			var name:String = pick(map);
			if (name != null)
				return findFile(src.dir, name);
		}
		return null;
	}

	function uniqueKey(key:String, used:Map<String, Bool>):String {
		var base:String = key;
		var suffix:Int = 1;
		while (used.exists(key))
			key = '$base-${++suffix}';
		used.set(key, true);
		return key;
	}

	function diffKey(map:OsuBeatmap, keys:Int):String {
		var v:String = Paths.formatToSongPath(map.version);
		if (v.length < 1)
			v = 'normal';
		return map.isStd() ? '$v-${keys}k' : v;
	}

	function diffLabel(map:OsuBeatmap, keys:Int):String {
		var v:String = (map.version != null) ? map.version.trim() : '';
		if (v.length < 1)
			v = 'Normal';
		return map.isStd() ? '$v (${keys}K)' : v;
	}

	function countNotes(song:SwagSong):Int {
		var count:Int = 0;
		for (section in song.notes)
			count += section.sectionNotes.length;
		return count;
	}

	function findFile(dir:String, name:String):String {
		if (name == null)
			return null;
		name = name.replace('\\', '/');

		var direct:String = Path.join([dir, name]);
		if (FileSystem.exists(direct))
			return direct;

		var target:String = Path.withoutDirectory(name).toLowerCase();
		for (entryName in FileSystem.readDirectory(dir))
			if (entryName.toLowerCase() == target)
				return Path.join([dir, entryName]);
		return null;
	}

	function ensurePack(packName:String) {
		var path:String = Paths.mods('$packName/pack.json');
		if (FileSystem.exists(path))
			return;

		Mods.savePack(packName, {
			name: packName,
			type: 'modpack',
			description: 'Songs converted from osu!mania beatmaps.\nOnly guaranteed to work on PE Continued fork',
			runsGlobally: false,
			color: [255, 100, 200],
			restart: false
		});
	}

	/* -- Generate characters -- */
	function ensureBlankCharacters() {
		var art:String = OsuChartConverter.BLANK_ART;

		if (!FileSystem.exists('$packDir/images/characters/$art.png')) {
			OszArchive.ensureDir('$packDir/images/characters');
			MediaConverter.writeBlankPng('$packDir/images/characters/$art.png');
			File.saveContent('$packDir/images/characters/$art.xml',
				'<?xml version="1.0" encoding="utf-8"?>\n'
				+ '<TextureAtlas imagePath="$art.png">\n'
				+ '\t<SubTexture name="idle0001" x="0" y="0" width="1" height="1"/>\n'
				+ '</TextureAtlas>\n');
		}

		if (!FileSystem.exists('$packDir/images/icons/$art.png'))
			MediaConverter.writeBlankPng('$packDir/images/icons/$art.png', 150, 150);

		OszArchive.ensureDir('$packDir/characters');
		writeBlankCharJson(OsuChartConverter.BLANK_BF, [255, 255, 255]);
		writeBlankCharJson(OsuChartConverter.BLANK_DAD, [0, 0, 0]);
		writeBlankCharJson(OsuChartConverter.BLANK_GF, [255, 255, 255]);
	}

	function writeBlankCharJson(name:String, healthbarColors:Array<Int>) {
		var path:String = '$packDir/characters/$name.json';
		if (FileSystem.exists(path))
			return;

		var anims:Array<Dynamic> = [
			for (animName in ['idle', 'singLEFT', 'singDOWN', 'singUP', 'singRIGHT'])
				{
					anim: animName,
					name: 'idle',
					fps: 24,
					loop: false,
					indices: [],
					offsets: [0, 0]
				}
		];

		File.saveContent(path, haxe.Json.stringify({
			animations: anims,
			image: 'characters/${OsuChartConverter.BLANK_ART}',
			position: [0, 0],
			camera_position: [0, 0],
			healthicon: OsuChartConverter.BLANK_ART,
			flip_x: false,
			no_antialiasing: true,
			healthbar_colors: healthbarColors,
			sing_duration: 4,
			scale: 1
		}, null, '\t'));
	}

	function writeSongMetadata(diffs:Array<String>) {
		var first:OsuBeatmap = maps[0];
		var path:String = '$packDir/data/$songKey/metadata.json';
		File.saveContent(path, haxe.Json.stringify({
			songName: display,
			icon: OsuChartConverter.BLANK_ART,
			color: [255, 100, 200],
			difficulties: mergeDifficulties(path, diffs),
			source: 'osu!',
			artist: first.artist,
			charter: first.creator,
			beatmapId: first.beatmapSetId
		}, null, '\t'));
	}

	function mergeDifficulties(path:String, diffs:Array<String>):Array<String> {
		var out:Array<String> = [];
		var seen:Map<String, Bool> = new Map();

		if (FileSystem.exists(path)) {
			try {
				var data:Dynamic = haxe.Json.parse(File.getContent(path));
				if (data != null && data.difficulties != null) {
					var existing:Array<Dynamic> = data.difficulties;
					for (d in existing) {
						var s:String = Std.string(d);
						if (!seen.exists(s)) {
							seen.set(s, true);
							out.push(s);
						}
					}
				}
			} catch (e:Dynamic) {}
		}

		for (d in diffs)
			if (d != null && !seen.exists(d)) {
				seen.set(d, true);
				out.push(d);
			}
		return out;
	}

	/*
	 * -- Stage generation --
	 * Builds the stage script from discrete blocks joined by a single blank line, so the output
	 * is consistently formatted whether or not the song has a video.
	 */
	function genStageLua(hasBg:Bool, hasVideo:Bool, hasStoryboard:Bool, widescreen:Bool):String {
		var anyVisual:Bool = hasBg || hasVideo || hasStoryboard;
		var letterbox:Bool = hasStoryboard && !widescreen;

		var mod:String = opts.packName;

		var head:Array<String> = ['-- Auto-generated by the osu! converter for "$songKey" (LuaProxy stage).'];
		if (anyVisual)
			head.push("local FlxSprite = import('flixel.FlxSprite')");
		if (hasVideo)
			head.push("local FlxVideoSprite = import('hxvlc.flixel.FlxVideoSprite')");
		if (hasStoryboard)
			head.push("local OsuStoryboardPlayer = import('backend.osu.OsuStoryboardPlayer')");

		var locals:Array<String> = [];
		if (hasStoryboard)
			locals.push("local osuSb = nil");
		if (letterbox)
			locals.push("local osuLetterbox = nil");
		if (hasBg)
			locals.push("local osuBg = nil");
		if (hasVideo)
			locals.push("local osuVideo = nil");
		if (anyVisual)
			locals.push("local osuDim = nil");

		var sections:Array<String> = [head.join("\n") + (locals.length > 0 ? "\n\n" + locals.join("\n") : "")];

		if (anyVisual) {
			var post:Array<String> = [
				"\tlocal osuCover = game.camGame.height / (game.camGame.zoom > 0 and game.camGame.zoom or 1) / FlxG.height"
			];
			if (hasBg)
				post.push(gate("getModSetting('osu_showBackground', '" + mod + "')", bgBody()));
			if (hasVideo)
				post.push(gate("getModSetting('osu_showVideo', '" + mod + "')", videoBody()));
			if (letterbox)
				post.push(gate("getModSetting('osu_showStory', '" + mod + "')", letterboxBody()));
			if (hasStoryboard)
				post.push(gate("getModSetting('osu_showStory', '" + mod + "')", storyboardBody()));
			post.push("\tlocal osuDimAmount = getModSetting('osu_backgroundDim', '" + mod + "')");
			post.push(gate("osuDimAmount ~= nil and osuDimAmount > 0", dimBody()));
			sections.push(wrapFunc("onCreatePost", post));
		}

		if (hasVideo) {
			sections.push(videoCall("onSongStart", "play"));
			sections.push(videoCall("onPause", "pause"));
			sections.push(videoCall("onResume", "resume"));
			sections.push(videoCall("onGameOver", "pause"));
		}

		return sections.join("\n\n") + "\n";
	}

	function gate(cond:String, body:String):String {
		var inner:String = body.split("\n").map(line -> "\t" + line).join("\n");
		return "\tif " + cond + " then\n" + inner + "\n\tend";
	}

	/** A one-line stage callback that runs `osuVideo:method()` when the video exists. */
	function videoCall(name:String, method:String):String
		return 'function $name()\n\tif osuVideo ~= nil then osuVideo:$method() end\nend';

	/** Wraps indented body blocks (joined by a blank line) in a `function name() ... end`. */
	function wrapFunc(name:String, bodies:Array<String>):String {
		var inner:String = bodies.join("\n\n");
		return (inner.length > 0) ? 'function $name()\n$inner\nend' : 'function $name()\nend';
	}

	/* Boots the native storyboard runtime from the shipped `.osb`; it renders on camGame behind the notes. */
	function storyboardBody():String {
		var osb:String = "mods/" + opts.packName + "/stages/" + stageName + ".osb";
		var imgDir:String = "mods/" + opts.packName + "/images/" + stageName + "_sb";
		var sndDir:String = "mods/" + opts.packName + "/sounds/" + stageName + "_sb";
		return [
			"\tosuSb = OsuStoryboardPlayer.fromFile('" + osb + "', '" + imgDir + "', '" + sndDir + "', " + audioTrimMs + ")",
			"\tif osuSb ~= nil then game:add(osuSb) end"
		].join("\n");
	}

	function bgBody():String {
		return [
			"\tosuBg = FlxSprite.new(0, 0)",
			"\tosuBg:loadGraphic(Paths.image('" + stageName + "_bg'))",
			"\tosuBg:setGraphicSize(FlxG.width * osuCover, FlxG.height * osuCover)",
			"\tosuBg:updateHitbox()",
			"\tosuBg:screenCenter()",
			"\tosuBg.scrollFactor:set(0, 0)",
			"\tgame:add(osuBg)"
		].join("\n");
	}

	/*
	 * Scales the video to fill the window like the bg image. setGraphicSize must wait for the
	 * video's real resolution (onFormatSetup), which hxvlc fires once the media is parsed.
	 */
	function videoBody():String {
		return [
			"\tpcall(function()",
			"\t\tosuVideo = FlxVideoSprite.new(0, 0)",
			"\t\tosuVideo.bitmap.onFormatSetup:add(function()",
			"\t\t\tosuVideo:setGraphicSize(FlxG.width, FlxG.height)",
			"\t\t\tosuVideo:updateHitbox()",
			"\t\t\tosuVideo:screenCenter()",
			"\t\tend)",
			"\t\tosuVideo:load('mods/" + opts.packName + "/videos/" + stageName + ".webm')",
			"\t\tosuVideo.scrollFactor:set(0, 0)",
			"\t\tgame:add(osuVideo)",
			"\tend)"
		].join("\n");
	}

	function dimBody():String {
		return [
			"\tosuDim = FlxSprite.new(0, 0)",
			"\tosuDim:makeGraphic(1, 1, 0xFF000000)",
			"\tosuDim.scale:set(FlxG.width * osuCover, FlxG.height * osuCover)",
			"\tosuDim:updateHitbox()",
			"\tosuDim:screenCenter()",
			"\tosuDim.scrollFactor:set(0, 0)",
			"\tosuDim.alpha = osuDimAmount",
			"\tgame:add(osuDim)"
		].join("\n");
	}

	/* Black backdrop behind a 4:3 storyboard so its widescreen sides letterbox cleanly. */
	function letterboxBody():String {
		return [
			"\tosuLetterbox = FlxSprite.new(0, 0)",
			"\tosuLetterbox:makeGraphic(1, 1, 0xFF000000)",
			"\tosuLetterbox.scale:set(FlxG.width * osuCover, FlxG.height * osuCover)",
			"\tosuLetterbox:updateHitbox()",
			"\tosuLetterbox:screenCenter()",
			"\tosuLetterbox.scrollFactor:set(0, 0)",
			"\tgame:add(osuLetterbox)"
		].join("\n");
	}

	function genStageJson():String {
		return haxe.Json.stringify({
			directory: "",
			defaultZoom: 1.0,
			isPixelStage: false,
			stageUI: "normal",
			boyfriend: [0, 0],
			girlfriend: [0, 0],
			opponent: [0, 0],
			hide_girlfriend: true,
			camera_boyfriend: [0, 0],
			camera_opponent: [0, 0],
			camera_girlfriend: [0, 0],
			camera_speed: 1
		}, null, '\t');
	}

	/*
	 * -- SV script generation --
	 * Reproduces osu!mania slider-velocity scrolling by remapping each note's scroll
	 * distance to the integral of the "Osu SV" event timeline, so spacing changes only
	 * going forward (notes never teleport, unlike a flat "Change Scroll Speed" multiplier).
	 */
	function writeSvScript() {
		OszArchive.ensureDir('$packDir/custom_events');
		var isHx:Bool = (opts.svScript == 'hscript');
		var fileName:String = OsuChartConverter.SV_EVENT + (isHx ? '.hx' : '.lua');
		File.saveContent('$packDir/custom_events/$fileName', isHx ? genSvHScript() : genSvLua());
		log('SV script -> custom_events/$fileName (osu! slider-velocity scrolling).');
	}

	function writeHitsoundScript() {
		OszArchive.ensureDir('$packDir/custom_events');
		File.saveContent('$packDir/custom_events/Osu Hitsounds.lua', genHitsoundLua());
	}

	function genHitsoundLua():String {
		return "-- Auto-generated by the osu! converter (LuaProxy hitsound script).
-- Plays the beatmap's own hitsound samples on each note hit, read from 'Osu Hitsounds'
-- events in the chart. Only samples shipped inside the beatmap are bundled.

local ClientPrefs = import('backend.ClientPrefs')
local Sound = import('openfl.media.Sound')
local SoundTransform = import('openfl.media.SoundTransform')

local hitMap = {}
local cache = {}
local hitDir = ''
local enabled = false

function onCreatePost()
	enabled = getModSetting('osu_hitsounds', '"
			+ opts.packName
			+ "') ~= false
	if not enabled then return end
	hitDir = 'mods/"
			+ opts.packName
			+ "/sounds/osu_' .. songPath .. '_hit/'

	local offset = ClientPrefs.data.noteOffset
	local evs = game.eventNotes
	if evs == nil then return end
	for i = 1, #evs do
		local e = evs[i]
		if e.event == 'Osu Hitsounds' then
			hitMap[math.floor((e.strumTime - offset) + 0.5)] = e.value1
		end
	end
end

local function playHits(data)
	for part in string.gmatch(data, '([^|]+)') do
		local file, vol = string.match(part, '^(.+):(%d+)$')
		if file ~= nil then
			local snd = cache[file]
			if snd == nil then
				local ok, s = pcall(function() return Sound.fromFile(hitDir .. file) end)
				snd = (ok and s) or false
				cache[file] = snd
			end
			if snd then
				snd:play(0, 0, SoundTransform.new((tonumber(vol) / 100) * FlxG.sound.volume))
			end
		end
	end
end

function goodNoteHit(id, noteData, noteType, isSustainNote)
	if not enabled or isSustainNote then return end
	local note = game.notes.members[id + 1]
	if note == nil then return end
	local data = hitMap[math.floor(note.strumTime + 0.5)]
	if data ~= nil then playHits(data) end
end
";
	}

	function genSvLua():String {
		return "-- Auto-generated by the osu! converter (LuaProxy SV script).
-- Reproduces osu!mania slider-velocity scrolling (BPM-independent 'fixed scroll'):
-- note distance follows the INTEGRAL of the SV timeline (spacing changes forward only,
-- no teleporting) and hold bodies stretch/squash with the local SV. Auto-loads whenever a
-- chart has an 'Osu SV' event (value 1 = normalized SV; the map's most-common SV = 1).
-- NOTE: read song data through 'game' only -- import('states.PlayState') is ModSecurity-blocked.
--
-- Performance: each note's scroll position + hold scale are precomputed ONCE in onSpawnNote
-- (the only binary searches), so onUpdate is O(1) per note -- just one subtract+divide and
-- a single scroll lookup for the whole frame.

local Conductor = import('backend.Conductor')
local ClientPrefs = import('backend.ClientPrefs')

local svTimes = {}
local svVels = {}
local svCum = {} -- cumulative scroll position at each control point
local count = 0
local ready = false

function onCreatePost()
	buildTimeline()
end

function buildTimeline()
	svTimes, svVels, svCum, count, ready = {}, {}, {}, 0, false

	if getModSetting('osu_mimicSV', '"
			+ opts.packName
			+ "') == false then return end

	local evs = game.eventNotes
	if evs == nil then return end
	-- eventNotes bake the user's noteOffset into strumTime but notes do not, so undo it.
	local offset = ClientPrefs.data.noteOffset

	for i = 1, #evs do
		local e = evs[i]
		if e.event == 'Osu SV' then
			local v = tonumber(e.value1)
			if v == nil or v <= 0 then v = 1 end
			count = count + 1
			svTimes[count] = e.strumTime - offset
			svVels[count] = v
		end
	end

	if count < 1 then return end

	-- scroll position = integral of velocity; velocity is 1.0 before the first event.
	svCum[1] = svTimes[1]
	for i = 2, count do
		svCum[i] = svCum[i - 1] + (svTimes[i] - svTimes[i - 1]) * svVels[i - 1]
	end
	ready = true
end

-- index of the last control point at or before t (binary search)
local function svIndexAt(t)
	local lo, hi, idx = 1, count, 1
	while lo <= hi do
		local mid = math.floor((lo + hi) / 2)
		if svTimes[mid] <= t then
			idx, lo = mid, mid + 1
		else
			hi = mid - 1
		end
	end
	return idx
end

local function scrollPosAt(t)
	if t <= svTimes[1] then return t end
	local i = svIndexAt(t)
	return svCum[i] + (t - svTimes[i]) * svVels[i]
end

local function velAt(t)
	if t <= svTimes[1] then return 1 end
	return svVels[svIndexAt(t)]
end

-- Precompute this note's scroll position + hold scale once, so onUpdate stays O(1)/note.
function onSpawnNote(id, data, noteType, isSustain, strumTime)
	if not ready then return end
	local note = game.notes.members[1] -- just inserted at index 0 -> Lua index 1
	if note == nil then return end
	note.svScrollPos = scrollPosAt(strumTime)
	-- Hold body: stretch it to reach the NEXT segment's SV position so bodies tile
	-- seamlessly even across SV changes (scale by the average SV over the segment's step,
	-- multiplying the engine's final base scale -- runs once, so it never compounds).
	if note.sustainBaseScaleY > 0 then
		local tail = note.parent.tail
		if tail ~= nil and #tail >= 2 then
			local step = tail[2].strumTime - tail[1].strumTime
			if step > 0 then
				note.scale.y = note.scale.y * (scrollPosAt(strumTime + step) - scrollPosAt(strumTime)) / step
			end
		end
	end
end

function onUpdate(elapsed)
	if not ready then return end

	local songPos = Conductor.songPosition
	local scrollNow = scrollPosAt(songPos)
	local grp = game.notes
	local members = grp.members

	for i = 1, #grp do
		local note = members[i]
		if note ~= nil then
			local st = note.strumTime
			local dt = songPos - st
			if dt > -0.001 and dt < 0.001 then
				note.multSpeed = velAt(st) -- limit of the ratio at the receptor
			else
				note.multSpeed = (scrollNow - note.svScrollPos) / dt
			end
		end
	end
end
";
	}

	function genSvHScript():String {
		return "/*
 * Auto-generated by the osu! converter (HScript SV script).
 * Reproduces osu!mania slider-velocity scrolling (BPM-independent 'fixed scroll'):
 * note distance follows the INTEGRAL of the SV timeline (spacing changes forward only,
 * no teleporting) and hold bodies stretch/squash with the local SV. Auto-loads whenever a
 * chart has an 'Osu SV' event (value 1 = normalized SV; the map's most-common SV = 1).
 *
 * Performance: each note's scroll position + hold scale are precomputed ONCE in onSpawnNote
 * (the only binary searches), so onUpdate is O(1) per note -- just one subtract+divide and
 * a single scroll lookup for the whole frame.
 */

var svTimes:Array<Float> = [];
var svVels:Array<Float> = [];
var svCum:Array<Float> = []; // cumulative scroll position at each control point
var ready:Bool = false;

function onCreatePost() {
	buildTimeline();
}

function buildTimeline() {
	svTimes = [];
	svVels = [];
	svCum = [];
	ready = false;

	if (getModSetting('osu_mimicSV', '"
			+ opts.packName
			+ "') == false) return;

	if (PlayState.SONG == null || PlayState.SONG.events == null) return;
	var events = PlayState.SONG.events;

	for (e in events) {
		var subList = e[1];
		if (subList == null) continue;
		for (sub in subList) {
			if (sub[0] == 'Osu SV') {
				var v:Float = Std.parseFloat(sub[1]);
				if (Math.isNaN(v) || v <= 0) v = 1;
				svTimes.push(e[0]);
				svVels.push(v);
			}
		}
	}

	if (svTimes.length < 1) return;

	/* scroll position = integral of velocity; velocity is 1.0 before the first event. */
	svCum.push(svTimes[0]);
	for (i in 1...svTimes.length)
		svCum.push(svCum[i - 1] + (svTimes[i] - svTimes[i - 1]) * svVels[i - 1]);
	ready = true;
}

function svIndexAt(t:Float):Int {
	var lo:Int = 0;
	var hi:Int = svTimes.length - 1;
	var idx:Int = 0;
	while (lo <= hi) {
		var mid:Int = Std.int((lo + hi) / 2);
		if (svTimes[mid] <= t) {
			idx = mid;
			lo = mid + 1;
		} else {
			hi = mid - 1;
		}
	}
	return idx;
}

function scrollPosAt(t:Float):Float {
	if (t <= svTimes[0]) return t;
	var i:Int = svIndexAt(t);
	return svCum[i] + (t - svTimes[i]) * svVels[i];
}

function velAt(t:Float):Float {
	if (t <= svTimes[0]) return 1;
	return svVels[svIndexAt(t)];
}

/* Precompute this note's scroll position + hold scale once, so onUpdate stays O(1)/note. */
function onSpawnNote(note) {
	if (!ready) return;
	var st:Float = note.strumTime;
	note.svScrollPos = scrollPosAt(st);
	/*
	 * Hold body: stretch it to reach the NEXT segment's SV position so bodies tile seamlessly
	 * even across SV changes (scale by the average SV over the segment's step, multiplying the
	 * engine's final base scale -- runs once, so it never compounds).
	 */
	if (note.sustainBaseScaleY > 0) {
		var tail = note.parent.tail;
		if (tail != null && tail.length >= 2) {
			var step:Float = tail[1].strumTime - tail[0].strumTime;
			if (step > 0)
				note.scale.y = note.scale.y * (scrollPosAt(st + step) - scrollPosAt(st)) / step;
		}
	}
}

function onUpdate(elapsed:Float) {
	if (!ready) return;

	var songPos:Float = Conductor.songPosition;
	var scrollNow:Float = scrollPosAt(songPos);
	game.notes.forEachAlive(function(note) {
		var st:Float = note.strumTime;
		var dt:Float = songPos - st;
		if (dt > -0.001 && dt < 0.001)
			note.multSpeed = velAt(st); // limit of the ratio at the receptor
		else
			note.multSpeed = (scrollNow - note.svScrollPos) / dt;
	});
}
";
	}
	#end
}
