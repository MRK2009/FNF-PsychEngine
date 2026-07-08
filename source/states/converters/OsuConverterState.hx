package states.converters;

#if CONVERTERS_ALLOWED
import backend.osu.OsuConvertOptions;
import backend.osu.OsuConvertOptions.OsuConvertDefaults;
import backend.osu.OszArchive;
import backend.osu.OsuConversionJob;
import backend.tools.MediaConverter;
import editors.content.FileDialogHandler;
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
	static inline var ACCENT:Int = 0xFFFF64C8;
	static inline var PANEL:Int = 0xFF14141F;
	static inline var BOX_W:Int = 360;
	static inline var BOX_H:Int = 470;

	var box:PsychUIBox;
	var queueText:FlxText;
	var statusText:FlxText;
	var fileDialog:FileDialogHandler;

	var pathInput:PsychUIInputText;
	var packInput:PsychUIInputText;
	var extraInput:PsychUIInputText;
	var bitrateDrop:PsychUIDropDownMenu;
	var codecDrop:PsychUIDropDownMenu;
	var bgCheck:PsychUICheckBox;
	var videoCheck:PsychUICheckBox;
	var sbCheck:PsychUICheckBox;
	var hsCheck:PsychUICheckBox;
	var svCheck:PsychUICheckBox;
	var quantizeCheck:PsychUICheckBox;
	var stdKeyDrop:PsychUIDropDownMenu;
	var stdKeysLabel:FlxText;
	var stdKeys:Array<Int> = [4];

	var logText:FlxText;
	var logLines:Array<String> = [];
	var logScroll:Float = 0;
	var logAutoScroll:Bool = true;
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
		bg.color = 0xFF15151F;
		add(bg);

		var titleBar:FlxSprite = new FlxSprite(0, 0).makeGraphic(FlxG.width, 60, 0xFF1B1B26);
		titleBar.alpha = 0.92;
		titleBar.scrollFactor.set();
		add(titleBar);

		var accentLine:FlxSprite = new FlxSprite(0, 60).makeGraphic(FlxG.width, 3, ACCENT);
		accentLine.scrollFactor.set();
		add(accentLine);

		var title:FlxText = new FlxText(0, 8, FlxG.width, 'osu! -> Psych Converter', 30);
		title.setFormat(font(), 30, FlxColor.WHITE, CENTER, OUTLINE, FlxColor.BLACK);
		title.scrollFactor.set();
		add(title);

		var subtitle:FlxText = new FlxText(0, 40, FlxG.width, 'mania & std beatmaps to Friday Night Funkin', 14);
		subtitle.setFormat(font(), 14, 0xFFB7B7C9, CENTER);
		subtitle.scrollFactor.set();
		add(subtitle);

		buildDropZone();

		box = new PsychUIBox(FlxG.width - 380, 80, BOX_W, BOX_H, ['Input', 'Options', 'Log']);
		box.canMove = box.canMinimize = true;
		box.scrollFactor.set();
		add(box);

		statusText = new FlxText(12, FlxG.height - 26, FlxG.width - 24, 'ESC: back to Converters menu', 13);
		statusText.setFormat(font(), 13, 0xFFB7B7C9, LEFT, OUTLINE, FlxColor.BLACK);
		statusText.scrollFactor.set();
		add(statusText);

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

	function buildDropZone() {
		var px:Int = 40, py:Int = 80, pw:Int = 820, ph:Int = 430;

		var border:FlxSprite = new FlxSprite(px, py).makeGraphic(pw, ph, ACCENT);
		border.alpha = 0.5;
		border.scrollFactor.set();
		add(border);

		var inner:FlxSprite = new FlxSprite(px + 3, py + 3).makeGraphic(pw - 6, ph - 6, PANEL);
		inner.alpha = 0.92;
		inner.scrollFactor.set();
		add(inner);

		var heading:FlxText = new FlxText(px, py + 64, pw, 'DROP BEATMAP HERE', 42);
		heading.setFormat(font(), 42, FlxColor.WHITE, CENTER, OUTLINE, FlxColor.BLACK);
		heading.scrollFactor.set();
		add(heading);

		var hint:FlxText = new FlxText(px, py + 126, pw, 'drag a .osz, .osu, or a folder anywhere on the window', 17);
		hint.setFormat(font(), 17, 0xFFB7B7C9, CENTER);
		hint.scrollFactor.set();
		add(hint);

		var hint2:FlxText = new FlxText(px, py + 152, pw, 'or use Browse in the Input tab', 14);
		hint2.setFormat(font(), 14, 0xFF8A8AA0, CENTER);
		hint2.scrollFactor.set();
		add(hint2);

		var divider:FlxSprite = new FlxSprite(px + 24, py + 200).makeGraphic(pw - 48, 2, ACCENT);
		divider.alpha = 0.4;
		divider.scrollFactor.set();
		add(divider);

		var qHead:FlxText = new FlxText(px + 24, py + 210, pw - 48, 'QUEUE', 15);
		qHead.setFormat(font(), 15, ACCENT, LEFT);
		qHead.scrollFactor.set();
		add(qHead);

		queueText = new FlxText(px + 24, py + 234, pw - 48, '', 14);
		queueText.setFormat(font(), 14, FlxColor.WHITE, LEFT);
		queueText.wordWrap = true;
		queueText.scrollFactor.set();
		add(queueText);

		var clearBtn:PsychUIButton = new PsychUIButton(px + 24, py + ph - 42, 'Clear queue', function() clearQueue(), 130, 28);
		clearBtn.scrollFactor.set();
		add(clearBtn);

		updateQueueText();
	}

	function clearQueue() {
		queuedPaths = [];
		if (pathInput != null)
			pathInput.text = '';
		updateQueueText();
		log('Queue cleared.');
	}

	function updateQueueText() {
		if (queueText == null)
			return;
		if (queuedPaths.length < 1) {
			queueText.text = 'nothing queued yet';
			return;
		}
		var lines:Array<String> = [];
		var max:Int = Std.int(Math.min(queuedPaths.length, 10));
		for (i in 0...max)
			lines.push('${i + 1}.  ' + haxe.io.Path.withoutDirectory(queuedPaths[i]));
		if (queuedPaths.length > max)
			lines.push('... and ${queuedPaths.length - max} more');
		queueText.text = lines.join('\n');
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

		sbCheck = new PsychUICheckBox(10, 198, 'Convert storyboard (experimental)', 220);
		tab.add(sbCheck);

		svCheck = new PsychUICheckBox(10, 224, 'Mimic SV (osu! scroll behavior)', 220);
		tab.add(svCheck);

		// SV now uses the engine's native Scroll Velocity events -- no bundled script, so no script choice.

		quantizeCheck = new PsychUICheckBox(10, 258, 'Quantize notes (auto-snap timing)', 260);
		tab.add(quantizeCheck);

		label(tab, 10, 312, 'osu!std -> mania:');
		stdKeyDrop = new PsychUIDropDownMenu(140, 308, ['4K', '5K', '6K', '7K', '8K', '9K'], function(index, name) {}, 80);
		stdKeyDrop.selectedLabel = '4K';
		tab.add(stdKeyDrop);

		var addKeyBtn:PsychUIButton = new PsychUIButton(226, 308, '+', function() addStdKey(), 30, 22);
		tab.add(addKeyBtn);

		var resetKeyBtn:PsychUIButton = new PsychUIButton(262, 308, 'Reset', function() resetStdKeys(), 72, 22);
		tab.add(resetKeyBtn);

		stdKeysLabel = label(tab, 10, 338, '');
		updateStdKeysLabel();

		hsCheck = new PsychUICheckBox(10, 364, 'Convert hitsounds', 220);
		hsCheck.checked = true;
		tab.add(hsCheck);
	}

	function addStdKey() {
		var k:Int = parseKeyLabel(stdKeyDrop.selectedLabel);
		if (k >= 1 && !stdKeys.contains(k)) {
			stdKeys.push(k);
			stdKeys.sort((a, b) -> a - b);
			updateStdKeysLabel();
		}
	}

	function resetStdKeys() {
		stdKeys = [4];
		updateStdKeysLabel();
	}

	function updateStdKeysLabel() {
		if (stdKeysLabel != null)
			stdKeysLabel.text = 'Generates: ' + (stdKeys.length > 0 ? [for (k in stdKeys) '${k}K'].join(', ') : '(none -> 4K)');
	}

	function parseKeyLabel(label:String):Int {
		var n:Null<Int> = Std.parseInt(label.split('K')[0]);
		return (n == null) ? 4 : n;
	}

	function buildLogTab() {
		logText = new FlxText(0, 0, BOX_W - 20, '', 11);
		logText.setFormat(font(), 11, FlxColor.WHITE);
		logText.wordWrap = true;
		logText.scrollFactor.set();
		logText.visible = false;
		add(logText);
	}

	function updateLogView() {
		if (logText == null || box == null)
			return;

		var show:Bool = !box.isMinimized && box.selectedIndex == 2;
		logText.visible = show;
		if (!show)
			return;

		var viewTop:Float = box.y + box.tabHeight + 8;
		var viewH:Float = BOX_H - box.tabHeight - 16;
		var maxScroll:Float = Math.max(0, logText.height - viewH);

		var mx:Float = FlxG.mouse.x, my:Float = FlxG.mouse.y;
		var overBox:Bool = mx >= box.x && mx <= box.x + BOX_W && my >= box.y && my <= box.y + BOX_H;
		if (overBox && FlxG.mouse.wheel != 0) {
			logScroll -= FlxG.mouse.wheel * 32;
			logAutoScroll = false;
		}

		if (logAutoScroll)
			logScroll = maxScroll;
		if (logScroll < 0)
			logScroll = 0;
		if (logScroll > maxScroll)
			logScroll = maxScroll;
		if (logScroll >= maxScroll - 1)
			logAutoScroll = true;

		logText.x = box.x + 10;
		logText.y = viewTop - logScroll;
		logText.clipRect = new flixel.math.FlxRect(0, logScroll, logText.width, viewH);
	}

	function buildProgressBar() {
		var barX:Float = (FlxG.width - BAR_W) / 2;
		var barY:Float = FlxG.height - 86;

		progLabel = new FlxText(0, barY - 30, FlxG.width, '', 16);
		progLabel.setFormat(font(), 16, FlxColor.WHITE, CENTER, OUTLINE, FlxColor.BLACK);
		progLabel.scrollFactor.set();
		add(progLabel);

		progBarBG = new FlxSprite(barX, barY).makeGraphic(BAR_W, 24, 0xFF0E0E16);
		progBarBG.scrollFactor.set();
		add(progBarBG);

		progBarFill = new FlxSprite(barX + 2, barY + 2).makeGraphic(FILL_W, 20, ACCENT);
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
		updateQueueText();
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
		opts.convertHitsounds = hsCheck.checked;
		opts.mimicSV = svCheck.checked;
		opts.quantize = quantizeCheck.checked;
		opts.stdTargetKeys = stdKeys.copy();

		queuedPaths = []; // consumed by this run
		updateQueueText();
		logLines = [];
		logScroll = 0;
		logAutoScroll = true;
		box.selectedIndex = 2; // jump to the Log tab
		log('Starting conversion...');

		#if desktop
		busy = true;
		cancelRequested = false;
		showProgressBar(true);
		setProgress(0, 'Starting...');
		refreshStopButton();

		sys.thread.Thread.create(function() {
			/* Expand each picked path (a folder of .osz becomes one item per archive), dedupe. */
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
			case 'cancel':
				log('Conversion stopped.');
			case 'ok':
				log('Conversion complete.');
			default:
				log('Conversion finished with errors (see log above).');
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
		updateLogView();
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
