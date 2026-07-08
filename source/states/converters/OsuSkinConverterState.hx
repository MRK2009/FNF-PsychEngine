package states.converters;

#if CONVERTERS_ALLOWED
import backend.osu.OsuManiaSkinConvertJob;
import editors.content.FileDialogHandler;
import flash.net.FileFilter;

using StringTools;

/**
	UI for the osu! mania SKIN converter. Drop (or browse) a `.osk` archive or a folder containing
	`skin.ini`, and convert it into a Psych folder note skin under `mods/osu!Mania skin conversions`.
	Needs no external tools (just file copies + a `skin.json`), so it's reached directly from
	MasterConverterState without the ffmpeg gate.
**/
class OsuSkinConverterState extends MusicBeatState {
	static inline var TMP_ROOT:String = '.osu_skin_tmp';
	static inline var ACCENT:Int = 0xFF64C8FF;
	static inline var PANEL:Int = 0xFF14141F;

	var fileDialog:FileDialogHandler;
	var queued:Array<String> = [];
	var queueText:FlxText;
	var logText:FlxText;
	var logLines:Array<String> = [];
	var busy:Bool = false;

	inline function font()
		return Paths.font('vcr.ttf');

	override function create() {
		FlxG.camera.bgColor = FlxColor.BLACK;
		fileDialog = new FileDialogHandler();

		var bg:FlxSprite = new FlxSprite().loadGraphic(Paths.image('menuDesat'));
		bg.scrollFactor.set();
		bg.color = 0xFF20202A;
		add(bg);

		var px:Int = 40, py:Int = 70, pw:Int = 820, ph:Int = 230;
		var border:FlxSprite = new FlxSprite(px, py).makeGraphic(pw, ph, ACCENT);
		border.alpha = 0.5;
		add(border);
		var inner:FlxSprite = new FlxSprite(px + 3, py + 3).makeGraphic(pw - 6, ph - 6, PANEL);
		inner.alpha = 0.92;
		add(inner);

		var heading:FlxText = new FlxText(px, py + 44, pw, 'DROP osu! SKIN HERE', 40);
		heading.setFormat(font(), 40, FlxColor.WHITE, CENTER, OUTLINE, FlxColor.BLACK);
		add(heading);

		var hint:FlxText = new FlxText(px, py + 104, pw, 'drag a .osk file or a folder containing skin.ini onto the window', 16);
		hint.setFormat(font(), 16, 0xFFB7B7C9, CENTER);
		add(hint);

		var title:FlxText = new FlxText(20, 18, FlxG.width - 40, 'osu!Mania SKIN CONVERTER', 22);
		title.setFormat(font(), 22, FlxColor.WHITE, LEFT, OUTLINE, FlxColor.BLACK);
		add(title);

		queueText = new FlxText(px, py + 150, pw, '', 16);
		queueText.setFormat(font(), 16, 0xFFFFD24A, CENTER);
		add(queueText);

		add(new PsychUIButton(px, py + ph + 12, 'Browse .osk', function() browseFile(), 160, 28));
		add(new PsychUIButton(px + 170, py + ph + 12, 'Browse folder', function() browseFolder(), 160, 28));
		add(new PsychUIButton(px + 340, py + ph + 12, 'Convert', function() startConvert(), 160, 28));
		add(new PsychUIButton(px + 510, py + ph + 12, 'Clear', function() clearQueue(), 120, 28));

		logText = new FlxText(px, py + ph + 56, pw, '', 15);
		logText.setFormat(font(), 15, 0xFFDDDDEE, LEFT);
		add(logText);

		log('Drop a .osk / skin folder onto the window, or use Browse.');
		updateQueueText();

		#if desktop
		try
			openfl.Lib.application.window.onDropFile.add(onDropFile)
		catch (e:Dynamic)
			trace('drop listener failed: $e');
		#end

		FlxG.mouse.visible = true;
		super.create();
	}

	override function update(elapsed:Float) {
		super.update(elapsed);
		if (!busy && controls.BACK) {
			#if desktop
			try
				openfl.Lib.application.window.onDropFile.remove(onDropFile)
			catch (e:Dynamic) {}
			#end
			MusicBeatState.switchState(new MasterConverterState());
		}
	}

	#if desktop
	function onDropFile(path:String) {
		if (busy)
			return;
		addPath(path);
	}
	#end

	function browseFile() {
		if (busy)
			return;
		fileDialog.open(null, 'Choose an .osk skin', [new FileFilter('osu! skin (*.osk)', '*.osk')], function() {
			if (fileDialog.path != null)
				addPath(fileDialog.path);
		});
	}

	function browseFolder() {
		if (busy)
			return;
		fileDialog.openDirectory('Choose a skin folder (with skin.ini)', function() {
			if (fileDialog.path != null)
				addPath(fileDialog.path);
		});
	}

	function addPath(path:String) {
		if (path == null || path.trim().length < 1)
			return;
		path = path.trim();
		if (!queued.contains(path))
			queued.push(path);
		updateQueueText();
		log('Added: $path (${queued.length} queued)');
	}

	function clearQueue() {
		if (busy)
			return;
		queued = [];
		updateQueueText();
		log('Queue cleared.');
	}

	function updateQueueText() {
		queueText.text = (queued.length < 1) ? 'Nothing queued.' : '${queued.length} skin(s) queued';
	}

	function startConvert() {
		if (busy || queued.length < 1) {
			if (queued.length < 1)
				log('Nothing to convert -- drop or browse a skin first.');
			return;
		}
		busy = true;
		var inputs:Array<String> = queued.copy();
		queued = [];
		updateQueueText();

		var made:Int = 0;
		for (input in inputs) {
			log('Converting: ${haxe.io.Path.withoutDirectory(input)}...');
			var job:OsuManiaSkinConvertJob = new OsuManiaSkinConvertJob(log);
			var result:String = job.run(input, TMP_ROOT);
			if (result != null)
				made++;
		}
		log('Done. $made/${inputs.length} skin(s) converted into mods/${OsuManiaSkinConvertJob.PACK_NAME}.');
		busy = false;
	}

	function log(line:String) {
		logLines.push(line);
		while (logLines.length > 12)
			logLines.shift();
		if (logText != null)
			logText.text = logLines.join('\n');
		trace('[osu skin] ' + line);
	}
}
#end
