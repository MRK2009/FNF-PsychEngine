package states.converters;

#if CONVERTERS_ALLOWED
import backend.osu.OsuConvertOptions;
import backend.osu.OsuConvertOptions.OsuConvertDefaults;
import backend.osu.OszArchive;
import backend.osu.OsuConversionJob;
import backend.tools.MediaConverter;
import states.editors.content.FileDialogHandler;
import flash.net.FileFilter;
import flixel.group.FlxSpriteGroup;

using StringTools;

/**
 * UI for the osu! beatmap converter. Drop or browse an `.osz` / `.osu` / folder,
 * tweak options, and convert into a playable modpack. Reached from MasterConverterState,
 * which guarantees ffmpeg is installed before this state opens.
 */
class OsuConverterState extends MusicBeatState {
	static inline var TMP_ROOT:String = '.osu_tmp';
	static inline var BAR_W:Int = 500;
	static inline var FILL_W:Int = 496;

	var box:PsychUIBox;
	var fileDialog:FileDialogHandler;

	var pathInput:PsychUIInputText;
	var packInput:PsychUIInputText;
	var extraInput:PsychUIInputText;
	var bitrateDrop:PsychUIDropDownMenu;
	var codecDrop:PsychUIDropDownMenu;
	var bgCheck:PsychUICheckBox;
	var videoCheck:PsychUICheckBox;
	var sbCheck:PsychUICheckBox;
	var svCheck:PsychUICheckBox;
	var svScriptDrop:PsychUIDropDownMenu;
	var quantizeCheck:PsychUICheckBox;

	var logText:FlxText;
	var logLines:Array<String> = [];
	var selectedPath:String = null;
	var queuedPaths:Array<String> = []; // batch: multiple dropped/browsed sources, all into one pack
	var busy:Bool = false;
	var cancelRequested:Bool = false;

	#if desktop
	var msgQueue:sys.thread.Deque<String> = new sys.thread.Deque<String>();
	#end

	var progLabel:FlxText;
	var progBarBG:FlxSprite;
	var progBarFill:FlxSprite;
	var stopBtn:PsychUIButton;

	inline function font()
		return Paths.font('vcr.ttf');

	override function create() {
		FlxG.camera.bgColor = FlxColor.BLACK;

		var bg:FlxSprite = new FlxSprite().loadGraphic(Paths.image('menuDesat'));
		bg.scrollFactor.set();
		bg.color = 0xFF1A1A1A;
		add(bg);

		var title:FlxText = new FlxText(0, 14, FlxG.width, 'osu!mania -> Psych Converter', 28);
		title.setFormat(font(), 28, FlxColor.WHITE, CENTER);
		title.scrollFactor.set();
		add(title);

		box = new PsychUIBox(FlxG.width - 380, 70, 360, 470, ['Input', 'Options', 'Log']);
		box.scrollFactor.set();
		add(box);

		buildInputTab();
		buildOptionsTab();
		buildLogTab();
		buildProgressBar();

		box.selectedIndex = 0;
		log('Drop a .osz / .osu / folder onto the window, or use Browse.');

		#if desktop
		try
			openfl.Lib.application.window.onDropFile.add(onDropFile)
		catch (error:Dynamic)
			trace('drop listener failed: $error');
		#end

		FlxG.mouse.visible = true;
		super.create();
	}

	function label(tab:FlxSpriteGroup, x:Float, y:Float, text:String, size:Int = 12):FlxText {
		var field:FlxText = new FlxText(x, y, 340, text, size);
		field.setFormat(font(), size, FlxColor.WHITE);
		tab.add(field);
		return field;
	}

	function buildInputTab() {
		var tab = box.getTab('Input').menu;
		label(tab, 10, 8, 'Source (.osz / .osu / folder):');
		pathInput = new PsychUIInputText(10, 28, 330, '', 8);
		tab.add(pathInput);

		var browse:PsychUIButton = new PsychUIButton(10, 56, 'Browse file', function() browseFile());
		browse.resize(150, 26);
		tab.add(browse);

		var browseDir:PsychUIButton = new PsychUIButton(180, 56, 'Browse folder', function() browseFolder());
		browseDir.resize(150, 26);
		tab.add(browseDir);

		label(tab, 10, 90, 'Tip: drag & drop anywhere. Batch: drop several\nfiles, or pick a folder of .osz - all go to one pack.', 11);

		var convert:PsychUIButton = new PsychUIButton(10, 150, 'CONVERT', function() startConvert());
		convert.resize(330, 40);
		tab.add(convert);
	}

	function buildOptionsTab() {
		var tab = box.getTab('Options').menu;

		label(tab, 10, 8, 'Modpack name:');
		packInput = new PsychUIInputText(140, 6, 200, OsuConvertDefaults.PACK_NAME, 8);
		tab.add(packInput);

		label(tab, 10, 36, 'Audio quality:');
		bitrateDrop = new PsychUIDropDownMenu(140, 32, OsuConvertDefaults.AUDIO_BITRATES.copy(), function(index, name) {}, 120);
		bitrateDrop.selectedLabel = '192k';
		tab.add(bitrateDrop);

		bgCheck = new PsychUICheckBox(10, 70, 'Convert background -> 1280x720', 220);
		bgCheck.checked = true;
		tab.add(bgCheck);

		videoCheck = new PsychUICheckBox(10, 96, 'Convert video -> WebM', 220);
		tab.add(videoCheck);

		label(tab, 10, 122, 'Video codec:');
		codecDrop = new PsychUIDropDownMenu(140, 118, OsuConvertDefaults.VIDEO_CODECS.copy(), function(index, name) {}, 120);
		codecDrop.selectedLabel = 'vp9';
		tab.add(codecDrop);

		label(tab, 10, 150, 'Video extra ffmpeg args:');
		extraInput = new PsychUIInputText(10, 170, 330, '', 8);
		tab.add(extraInput);

		sbCheck = new PsychUICheckBox(10, 198, 'Convert storyboard (deferred)', 220);
		tab.add(sbCheck);

		svCheck = new PsychUICheckBox(10, 224, 'Mimic SV (osu! scroll behavior)', 220);
		tab.add(svCheck);

		label(tab, 10, 254, 'SV script:');
		svScriptDrop = new PsychUIDropDownMenu(140, 250, OsuConvertDefaults.SV_SCRIPTS.copy(), function(index, name) {}, 120);
		svScriptDrop.selectedLabel = 'Lua';
		tab.add(svScriptDrop);

		quantizeCheck = new PsychUICheckBox(10, 282, 'Quantize notes (auto-snap timing)', 260);
		tab.add(quantizeCheck);
	}

	function buildLogTab() {
		var tab = box.getTab('Log').menu;
		logText = new FlxText(8, 8, 336, '', 11);
		logText.setFormat(font(), 11, FlxColor.WHITE);
		logText.wordWrap = true;
		tab.add(logText);
	}

	function buildProgressBar() {
		var barX:Float = (FlxG.width - BAR_W) / 2;
		var barY:Float = FlxG.height - 86;

		progLabel = new FlxText(0, barY - 30, FlxG.width, '', 16);
		progLabel.setFormat(font(), 16, FlxColor.WHITE, CENTER);
		progLabel.scrollFactor.set();
		add(progLabel);

		progBarBG = new FlxSprite(barX, barY).makeGraphic(BAR_W, 24, 0xFF1E1E1E);
		progBarBG.scrollFactor.set();
		add(progBarBG);

		progBarFill = new FlxSprite(barX + 2, barY + 2).makeGraphic(FILL_W, 20, 0xFF55CC55);
		progBarFill.scrollFactor.set();
		add(progBarFill);

		stopBtn = new PsychUIButton(barX + BAR_W + 12, barY, 'Stop', function() requestStop(), 90, 24);
		stopBtn.scrollFactor.set();
		stopBtn.visible = false;
		add(stopBtn);

		showProgressBar(false);
	}

	function showProgressBar(show:Bool) {
		if (progLabel != null)
			progLabel.visible = show;
		if (progBarBG != null)
			progBarBG.visible = show;
		if (progBarFill != null)
			progBarFill.visible = show;
	}

	function setProgress(frac:Float, text:String) {
		if (frac < 0)
			frac = 0;
		if (frac > 1)
			frac = 1;
		if (progBarFill != null)
			progBarFill.clipRect = new flixel.math.FlxRect(0, 0, FILL_W * frac, 20);
		if (progLabel != null)
			progLabel.text = text;
	}

	function ensureDialog() {
		if (fileDialog == null) {
			fileDialog = new FileDialogHandler();
			add(fileDialog);
		}
	}

	function browseFile() {
		if (busy)
			return;
		ensureDialog();
		if (!fileDialog.completed)
			return;
		fileDialog.open(null, 'Select an osu! beatmap', [new FileFilter('osu! beatmap', '*.osz;*.osu')], function() setPath(fileDialog.path));
	}

	function browseFolder() {
		if (busy)
			return;
		ensureDialog();
		if (!fileDialog.completed)
			return;
		fileDialog.openDirectory('Select a beatmap folder', function() setPath(fileDialog.path));
	}

	#if desktop
	function onDropFile(path:String) {
		if (busy)
			return;
		setPath(path);
	}
	#end

	function setPath(path:String) {
		if (path == null || path.trim().length < 1)
			return;
		path = path.trim();
		selectedPath = path;
		if (!queuedPaths.contains(path))
			queuedPaths.push(path); // drops/browses accumulate so several beatmaps batch at once
		if (pathInput != null)
			pathInput.text = (queuedPaths.length > 1) ? '${queuedPaths.length} sources queued' : path;
		log('Added: $path (${queuedPaths.length} queued)');
	}

	function startConvert() {
		if (busy)
			return;

		var inputs:Array<String> = queuedPaths.copy();
		if (inputs.length < 1 && pathInput != null && pathInput.text.trim().length > 0)
			inputs.push(pathInput.text.trim()); // fall back to a manually typed path
		if (inputs.length < 1) {
			log('No source selected.');
			return;
		}

		if (!MediaConverter.hasFfmpeg()) {
			log('ffmpeg is not available. Go back to the Converters menu to install it.');
			return;
		}

		var opts:OsuConvertOptions = OsuConvertDefaults.make();
		opts.packName = (packInput.text.trim().length > 0) ? packInput.text.trim() : OsuConvertDefaults.PACK_NAME;
		opts.audioBitrate = bitrateDrop.selectedLabel;
		opts.convertBackground = bgCheck.checked;
		opts.convertVideo = videoCheck.checked;
		opts.videoCodec = codecDrop.selectedLabel;
		opts.videoExtraArgs = extraInput.text;
		opts.convertStoryboard = sbCheck.checked;
		opts.mimicSV = svCheck.checked;
		opts.svScript = OsuConvertDefaults.svScriptValue(svScriptDrop.selectedLabel);
		opts.quantize = quantizeCheck.checked;

		queuedPaths = []; // consumed by this run
		logLines = [];
		box.selectedIndex = 2; // jump to the Log tab
		log('Starting conversion...');

		#if desktop
		busy = true;
		cancelRequested = false;
		showProgressBar(true);
		setProgress(0, 'Starting...');
		refreshStopButton();

		sys.thread.Thread.create(function() {
			// Expand each picked path (a folder of .osz becomes one item per archive), dedupe.
			var items:Array<String> = [];
			for (input in inputs)
				for (expanded in OszArchive.expandInputs(input))
					if (!items.contains(expanded))
						items.push(expanded);

			var total:Int = items.length;
			if (total < 1) {
				msgQueue.add('No .osz / .osu / folder inputs found.');
				msgQueue.add('__CONVDONE__:fail');
				return;
			}
			msgQueue.add('Batch: $total beatmap(s) -> "${opts.packName}".');

			var okCount:Int = 0;
			for (i in 0...total) {
				if (cancelRequested)
					break;

				var index:Int = i; // stable capture for the progress closure
				var itemPath:String = items[index];
				msgQueue.add('--- [${index + 1}/$total] ' + haxe.io.Path.withoutDirectory(itemPath) + ' ---');

				var src = null;
				try {
					src = OszArchive.prepare(itemPath, TMP_ROOT);
					if (src == null)
						msgQueue.add('  Skipped (not a readable .osz/.osu/folder).');
					else {
						var job = new OsuConversionJob(function(line) msgQueue.add(line),
							function(frac, label) msgQueue.add('__PROGRESS__:' + ((index + frac) / total) + '|[${index + 1}/$total] $label'),
							function() return cancelRequested);
						if (job.run(src, opts))
							okCount++;
					}
				} catch (error:Dynamic) {
					msgQueue.add('  ERROR: $error');
				}
				if (src != null)
					OszArchive.cleanup(src);
			}

			msgQueue.add('Batch finished: $okCount/$total succeeded.');
			msgQueue.add('__CONVDONE__:' + (cancelRequested ? 'cancel' : (okCount > 0 ? 'ok' : 'fail')));
		});
		#else
		log('Conversion is only available on desktop builds.');
		#end
	}

	function requestStop() {
		if (!busy || cancelRequested)
			return;
		cancelRequested = true;
		log('Stopping... (waiting for the current step to halt)');
		MediaConverter.cancel();
		refreshStopButton();
	}

	function refreshStopButton() {
		if (stopBtn != null)
			stopBtn.visible = busy && !cancelRequested;
	}

	function finishConvert(result:String) {
		busy = false;
		cancelRequested = false;
		showProgressBar(false);
		refreshStopButton();
		#if desktop
		Mods.updatedOnState = false; // re-scan mods so the new pack shows up
		#end
		switch (result) {
			case 'cancel': log('Conversion stopped.');
			case 'ok': log('Conversion complete.');
			default: log('Conversion finished with errors (see log above).');
		}
	}

	function log(line:String) {
		logLines.push(line);
		while (logLines.length > 200)
			logLines.shift();
		if (logText != null)
			logText.text = logLines.join('\n');
		trace('[osu-convert] $line');
	}

	override function update(elapsed:Float) {
		#if desktop
		if (busy && msgQueue != null) {
			var msg:String = msgQueue.pop(false);
			while (msg != null) {
				if (msg.startsWith('__PROGRESS__:')) {
					var rest:String = msg.substr(13);
					var sep:Int = rest.indexOf('|');
					var frac:Float = (sep >= 0) ? Std.parseFloat(rest.substr(0, sep)) : 0;
					if (Math.isNaN(frac))
						frac = 0;
					setProgress(frac, (sep >= 0) ? rest.substr(sep + 1) : rest);
				} else if (msg.startsWith('__CONVDONE__:')) {
					finishConvert(msg.substr(13));
				} else
					log(msg);
				msg = msgQueue.pop(false);
			}
		}
		#end

		if (!busy && controls.BACK) {
			#if desktop
			try
				openfl.Lib.application.window.onDropFile.remove(onDropFile)
			catch (error:Dynamic) {}
			#end
			MusicBeatState.switchState(new MasterConverterState());
		}
		super.update(elapsed);
	}

	override function destroy() {
		#if desktop
		try
			openfl.Lib.application.window.onDropFile.remove(onDropFile)
		catch (error:Dynamic) {}
		#end
		super.destroy();
	}
}
#end
