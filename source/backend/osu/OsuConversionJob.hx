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
 * script, and registers the song in a week so it shows in Freeplay/Story.
 *
 * All steps are logged through the `log` callback; failures are non-fatal where
 * possible (a missing ffmpeg skips audio/video but still writes charts).
 */
class OsuConversionJob {
	var log:String->Void;
	var progress:Float->String->Void;
	var isCancelled:Void->Bool;

	var totalSteps:Int = 1;
	var doneSteps:Int = 0;

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
		if (src == null || src.osuFiles == null || src.osuFiles.length < 1) {
			log('No .osu files found in the input.');
			return false;
		}

		var packDir:String = Paths.mods(opts.packName);
		for (sub in ['', 'data', 'songs', 'images', 'videos', 'stages'])
			OszArchive.ensureDir(sub.length < 1 ? packDir : '$packDir/$sub');
		ensurePack(opts.packName);

		// Parse + filter the mania difficulties.
		var maps:Array<OsuBeatmap> = [];
		for (osuPath in src.osuFiles) {
			var map:OsuBeatmap = OsuParser.parse(File.getContent(osuPath));
			if (!map.isMania()) {
				log('Skipped (not osu!mania): ${Path.withoutDirectory(osuPath)}');
				continue;
			}
			if (map.keyCount > 9) {
				log('Skipped (${map.keyCount}K co-op, >9 columns): ${Path.withoutDirectory(osuPath)}');
				continue;
			}
			maps.push(map);
		}
		if (maps.length < 1) {
			log('No supported osu!mania (1K-9K) difficulties found.');
			return false;
		}

		var first:OsuBeatmap = maps[0];
		var display:String = (first.title != null && first.title.trim().length > 0) ? first.title.trim() : 'osu song';
		var songKey:String = Paths.formatToSongPath(display);
		if (songKey.length < 1)
			songKey = 'osu-song';
		var stageName:String = 'osu_$songKey';

		log('Converting "$display" ($songKey) - ${maps.length} difficulty(ies).');

		var audioName:String = first.audioFilename;
		totalSteps = (audioName != null ? 1 : 0) + (opts.convertBackground ? 1 : 0) + (opts.convertVideo ? 1 : 0) + maps.length + 2;
		report('Starting...');

		// --- Audio (shared across difficulties) ---
		if (audioName != null) {
			if (cancelledNow())
				return false;
			var inAudio:String = findFile(src.dir, audioName);
			if (inAudio != null) {
				OszArchive.ensureDir('$packDir/songs/$songKey');
				report('Transcoding audio...');
				log('Transcoding audio -> Inst.ogg (${opts.audioBitrate})...');
				if (MediaConverter.convertAudio(inAudio, '$packDir/songs/$songKey/Inst.ogg', opts.audioBitrate))
					log('  audio OK');
				else
					log('  audio FAILED (is ffmpeg available?) - song will have no instrumental');
			} else
				log('Audio file not found in mapset: $audioName');
			if (cancelledNow())
				return false;
			stepDone();
		}

		// --- Background ---
		var hasBg:Bool = false;
		if (opts.convertBackground) {
			report('Resizing background...');
			for (map in maps) {
				if (map.background == null)
					continue;
				var inBg:String = findFile(src.dir, map.background);
				if (inBg != null) {
					log('Resizing background -> 1280x720...');
					hasBg = MediaConverter.resizeImage(inBg, '$packDir/images/${stageName}_bg.png');
					log(hasBg ? '  background OK' : '  background resize FAILED');
				} else
					log('Background file not found: ${map.background}');
				break;
			}
			if (cancelledNow())
				return false;
			stepDone();
		}

		// --- Video ---
		var hasVideo:Bool = false;
		if (opts.convertVideo) {
			report('Transcoding video (slow)...');
			for (map in maps) {
				if (map.video == null)
					continue;
				var inVid:String = findFile(src.dir, map.video);
				if (inVid != null) {
					log('Transcoding video -> ${opts.videoCodec} WebM (this can be slow)...');
					hasVideo = MediaConverter.convertVideo(inVid, '$packDir/videos/$stageName.webm', opts.videoCodec, opts.videoExtraArgs);
					log(hasVideo ? '  video OK (experimental playback)' : '  video FAILED (is ffmpeg available?)');
				} else
					log('Video file not found: ${map.video}');
				break;
			}
			if (cancelledNow())
				return false;
			stepDone();
		}

		if (opts.convertStoryboard)
			log('Storyboard conversion is deferred in this version - skipped.');

		// --- Charts (one per difficulty) ---
		OszArchive.ensureDir('$packDir/data/$songKey');
		var diffEntries:Array<{label:String, notes:Int}> = [];
		var usedKeys:Map<String, Bool> = new Map();
		var chartIdx:Int = 0;
		for (map in maps) {
			if (cancelledNow())
				return false;
			report('Writing chart ${++chartIdx}/${maps.length}...');
			var song:SwagSong = OsuChartConverter.convert(map, display, stageName, opts.mimicSV);
			if (song == null) {
				log('Chart conversion failed for version "${map.version}".');
				stepDone();
				continue;
			}

			var versionKey:String = Paths.formatToSongPath(map.version);
			if (versionKey.length < 1)
				versionKey = 'normal';
			var baseKey:String = versionKey;
			var suffixNum:Int = 1;
			while (usedKeys.exists(versionKey))
				versionKey = '$baseKey-${++suffixNum}';
			usedKeys.set(versionKey, true);

			var fileName:String = '$songKey-$versionKey.json';
			var json:String = '{"song":' + PsychJsonPrinter.print(song, ['sectionNotes', 'events']) + '}';
			File.saveContent('$packDir/data/$songKey/$fileName', json);

			var noteCount:Int = countNotes(song);
			var diffLabel:String = (Paths.formatToSongPath(map.version) == versionKey && map.version != null && map.version.trim().length > 0) ? map.version.trim() : versionKey;
			diffEntries.push({label: diffLabel, notes: noteCount});
			log('  chart -> $fileName (${map.keyCount}K, $noteCount notes, speed ${song.speed})');
			stepDone();
		}
		if (diffEntries.length < 1) {
			log('No charts were written.');
			return false;
		}

		// Order difficulties easiest-first (by note count) for the metadata list.
		diffEntries.sort((a, b) -> a.notes - b.notes);
		var versions:Array<String> = [for (entry in diffEntries) entry.label];

		if (cancelledNow())
			return false;
		report('Finalizing (stage + week)...');

		// --- Stage script (LuaProxy) ---
		File.saveContent('$packDir/stages/$stageName.lua', genStageLua(opts.packName, songKey, stageName, hasBg, hasVideo));
		// Drop a stale .hx stage from an older conversion so both don't load at once.
		var oldStage:String = '$packDir/stages/$stageName.hx';
		if (FileSystem.exists(oldStage))
			try
				FileSystem.deleteFile(oldStage)
			catch (error:Dynamic) {}

		// --- Per-song metadata (display name, icon, difficulty order, osu! info) ---
		// Freeplay discovers the song from disk; no week file is needed.
		writeSongMetadata(packDir, songKey, display, versions, first);
		stepDone();
		stepDone();
		report('Done.');

		log('Done. Launch the "${opts.packName}" mod to play "$display".');
		return true;
		#else
		return false;
		#end
	}

	#if sys
	function cancelledNow():Bool {
		if (isCancelled()) {
			log('Conversion cancelled. Partial files may remain in the modpack.');
			return true;
		}
		return false;
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
			description: 'Songs converted from osu!mania beatmaps.',
			runsGlobally: false,
			color: [255, 100, 200],
			restart: false
		});
	}

	function writeSongMetadata(packDir:String, songKey:String, songDisplay:String, diffs:Array<String>, first:OsuBeatmap) {
		var meta:Dynamic = {
			songName: songDisplay,
			icon: 'face',
			color: [255, 100, 200],
			difficulties: diffs,
			source: 'osu!',
			artist: first.artist,
			charter: first.creator,
			beatmapId: first.beatmapSetId
		};
		File.saveContent('$packDir/data/$songKey/metadata.json', haxe.Json.stringify(meta, null, '\t'));
	}

	function genStageLua(packName:String, songKey:String, stageName:String, hasBg:Bool, hasVideo:Bool):String {
		var buf:StringBuf = new StringBuf();
		buf.add('-- Auto-generated by the osu! converter for "$songKey" (LuaProxy stage).\n');
		buf.add("local FlxSprite = import('flixel.FlxSprite')\n");
		if (hasVideo)
			buf.add("local FlxVideoSprite = import('hxvlc.flixel.FlxVideoSprite')\n");
		buf.add('\n');
		if (hasBg)
			buf.add('local osuBg\n');
		if (hasVideo)
			buf.add('local osuVid\n');

		buf.add('\nfunction onCreate()\n');
		if (hasBg) {
			buf.add("\tosuBg = FlxSprite.new(0, 0)\n");
			buf.add("\tosuBg:loadGraphic(Paths.image('${stageName}_bg'))\n");
			// Always stretch the background to fill the game window.
			buf.add("\tosuBg:setGraphicSize(FlxG.width, FlxG.height)\n");
			buf.add("\tosuBg:updateHitbox()\n");
			buf.add("\tosuBg:screenCenter()\n");
			buf.add("\tosuBg.scrollFactor:set(0, 0)\n");
			buf.add("\tgame:add(osuBg)\n");
		}
		if (hasVideo) {
			// hxvlc/VLC playback is experimental; guard so a failure can't break the stage.
			buf.add("\tpcall(function()\n");
			buf.add("\t\tosuVid = FlxVideoSprite.new(0, 0)\n");
			buf.add("\t\tosuVid.camera = game.camGame\n");
			buf.add("\t\tosuVid:load('mods/$packName/videos/$stageName.webm')\n");
			buf.add("\t\tgame:add(osuVid)\n");
			buf.add("\t\tosuVid:play()\n");
			buf.add("\t\tosuVid:setGraphicSize(FlxG.width, FlxG.height)\n");
			buf.add("\t\tosuVid:updateHitbox()\n");
			buf.add("\tend)\n");
		}
		if (hasBg || hasVideo) {
			// osu-style background dim: a 1x1 black sprite scaled to the window, over
			// the bg/video but under the notes (added before PlayState's HUD/notes).
			buf.add("\tlocal osuDim = FlxSprite.new(0, 0)\n");
			buf.add("\tosuDim:makeGraphic(1, 1, 0xFF000000)\n");
			buf.add("\tosuDim.scale:set(FlxG.width, FlxG.height)\n");
			buf.add("\tosuDim:updateHitbox()\n");
			buf.add("\tosuDim:screenCenter()\n");
			buf.add("\tosuDim.scrollFactor:set(0, 0)\n");
			buf.add("\tosuDim.alpha = 0.5\n");
			buf.add("\tgame:add(osuDim)\n");
		}
		buf.add('end\n');
		return buf.toString();
	}
	#end
}
