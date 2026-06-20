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

		maps = parseManiaCharts();
		if (maps.length < 1) {
			log('No supported osu!mania (1K-9K) difficulties found.');
			return false;
		}

		resolveNames();
		createPackFolders();

		log('Converting "$display" ($songKey) - ${maps.length} difficulty(ies).');
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

		if (opts.convertStoryboard)
			log('Storyboard conversion is deferred in this version - skipped.');

		var versions:Array<String> = writeCharts();
		if (versions == null)
			return false;

		report('Finalizing (stage + metadata)...');

		writeStage(hasBg, hasVideo);
		stepDone();

		writeSongMetadata(versions);
		stepDone();

		report('Done.');

		log('Done. Launch the "${opts.packName}" mod to play "$display".');
		return true;
		#else
		return false;
		#end
	}

	// -- Conversion --
	#if sys
	function parseManiaCharts():Array<OsuBeatmap> {
		var result:Array<OsuBeatmap> = [];
		for (osuPath in src.osuFiles) {
			var map:OsuBeatmap = OsuParser.parse(File.getContent(osuPath));
			var fileName:String = Path.withoutDirectory(osuPath);
			if (!map.isMania())
				log('Skipped (not osu!mania): $fileName');
			else if (map.keyCount > 9)
				log('Skipped (${map.keyCount}K co-op, >9 columns): $fileName');
			else
				result.push(map);
		}
		return result;
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
		for (sub in ['', 'data', 'songs', 'images', 'videos', 'stages'])
			OszArchive.ensureDir(sub.length < 1 ? packDir : '$packDir/$sub');
		ensurePack(opts.packName);
		ensureBlankCharacters();
	}

	function countSteps():Int {
		var audio:Int = (maps[0].audioFilename != null) ? 1 : 0;
		var bg:Int = opts.convertBackground ? 1 : 0;
		var video:Int = opts.convertVideo ? 1 : 0;
		return audio + bg + video + maps.length + 2; // +2 = stage + metadata
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
			log('Transcoding audio -> Inst.ogg (${opts.audioBitrate})...');

			var ok:Bool = MediaConverter.convertAudio(input, '$packDir/songs/$songKey/Inst.ogg', opts.audioBitrate);
			log(ok ? '  audio OK' : '  audio FAILED (is ffmpeg available?) - song will have no instrumental');
		}
		stepDone();
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

	function writeCharts():Array<String> {
		OszArchive.ensureDir('$packDir/data/$songKey');
		var entries:Array<{label:String, notes:Int}> = [];
		var usedKeys:Map<String, Bool> = new Map();
		var index:Int = 0;

		for (map in maps) {
			if (cancelledNow())
				return null;

			report('Writing chart ${++index}/${maps.length}...');

			var song:SwagSong = OsuChartConverter.convert(map, display, stageName, opts.mimicSV);
			if (song == null) {
				log('Chart conversion failed for version "${map.version}".');
				stepDone();
				continue;
			}

			var versionKey:String = uniqueVersionKey(map.version, usedKeys);
			var fileName:String = '$songKey-$versionKey.json';
			File.saveContent('$packDir/data/$songKey/$fileName', '{"song":' + PsychJsonPrinter.print(song, ['sectionNotes', 'events']) + '}');

			var notes:Int = countNotes(song);
			entries.push({label: difficultyLabel(map.version, versionKey), notes: notes});

			log('  chart -> $fileName (${map.keyCount}K, $notes notes, speed ${song.speed})');
			stepDone();
		}

		if (entries.length < 1) {
			log('No charts were written.');
			return null;
		}
		entries.sort((a, b) -> a.notes - b.notes);
		return [for (entry in entries) entry.label];
	}

	function writeStage(hasBg:Bool, hasVideo:Bool) {
		File.saveContent('$packDir/stages/$stageName.lua', genStageLua(hasBg, hasVideo));
		OszArchive.ensureDir('$packDir/data/stages');
		File.saveContent('$packDir/data/stages/$stageName.json', genStageJson());
	}

	// -- Helpers --
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

	function uniqueVersionKey(version:String, used:Map<String, Bool>):String {
		var key:String = Paths.formatToSongPath(version);
		if (key.length < 1)
			key = 'normal';

		var base:String = key;
		var suffix:Int = 1;

		while (used.exists(key))
			key = '$base-${++suffix}';
		used.set(key, true);

		return key;
	}

	function difficultyLabel(version:String, versionKey:String):String {
		var trimmed:String = (version != null) ? version.trim() : '';
		return (trimmed.length > 0 && Paths.formatToSongPath(trimmed) == versionKey) ? trimmed : versionKey;
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

	// -- Generate characters --
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
		File.saveContent('$packDir/data/$songKey/metadata.json', haxe.Json.stringify({
			songName: display,
			icon: OsuChartConverter.BLANK_ART,
			color: [255, 100, 200],
			difficulties: diffs,
			source: 'osu!',
			artist: first.artist,
			charter: first.creator,
			beatmapId: first.beatmapSetId
		}, null, '\t'));
	}

	// -- Stage generation --
	function genStageLua(hasBg:Bool, hasVideo:Bool):String {
		var buf:StringBuf = new StringBuf();
		buf.add('-- Auto-generated by the osu! converter for "$songKey" (LuaProxy stage).\n');

		buf.add("local FlxSprite = import('flixel.FlxSprite')\n");
		if (hasVideo)
			buf.add("local FlxVideoSprite = import('hxvlc.flixel.FlxVideoSprite')\n");

		buf.add('\n');
		if (hasBg)
			buf.add("local osuBg = nil\n");
		if (hasVideo)
			buf.add("local osuVideo = nil\n");
		if (hasBg || hasVideo)
			buf.add("local osuDim = nil\n");

		buf.add('\nfunction onCreate()\n');
		if (hasBg) {
			buf.add("\tosuBg = FlxSprite.new(0, 0)\n");
			buf.add("\tosuBg:loadGraphic(Paths.image('" + stageName + "_bg'))\n");
			buf.add("\tosuBg:setGraphicSize(FlxG.width, FlxG.height)\n");
			buf.add("\tosuBg:updateHitbox()\n");
			buf.add("\tosuBg:screenCenter()\n");
			buf.add("\tosuBg.scrollFactor:set(0, 0)\n");
			buf.add("\tgame:add(osuBg)\n");
		}

		if (hasBg && !hasVideo)
			buf.add(dimLua());
		buf.add('end\n');

		if (hasVideo) {
			buf.add('\nfunction onCreatePost()\n');
			buf.add("\tpcall(function()\n");
			buf.add("\t\tosuVideo = FlxVideoSprite.new(0, 0)\n");
			buf.add("\t\tosuVideo:load('mods/" + opts.packName + "/videos/" + stageName + ".webm')\n");
			buf.add("\t\tosuVideo:screenCenter()\n");
			buf.add("\t\tosuVideo.scrollFactor:set(0, 0)\n");
			buf.add("\t\tgame:add(osuVideo)\n");
			buf.add("\tend)\n");
			buf.add(dimLua());
			buf.add('end\n');

			buf.add('\nfunction onSongStart()\n');
			buf.add("\tif osuVideo ~= nil then osuVideo:play() end\n");
			buf.add('end\n');
		}
		return buf.toString();
	}

	function dimLua():String {
		return "\tosuDim = FlxSprite.new(0, 0)\n" + "\tosuDim:makeGraphic(1, 1, 0xFF000000)\n" + "\tosuDim.scale:set(FlxG.width, FlxG.height)\n"
			+ "\tosuDim:updateHitbox()\n" + "\tosuDim:screenCenter()\n" + "\tosuDim.scrollFactor:set(0, 0)\n" + "\tosuDim.alpha = 0.5\n"
			+ "\tgame:add(osuDim)\n";
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
	#end
}
