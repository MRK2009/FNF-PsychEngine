package states.converters;

#if CONVERTERS_ALLOWED
import backend.osu.OsuConvertOptions;
import backend.osu.OsuConvertOptions.OsuConvertDefaults;
import backend.osu.OszArchive;
import backend.osu.OsuConversionJob;
import backend.tools.MediaConverter;
import editors.content.FileDialogHandler;
import flash.net.FileFilter;
import openfl.display.Sprite;
import smidr.UIRoot;
import smidr.UITheme;
import smidr.UIFonts;
import smidr.UILocale;
import smidr.UIComponent;
import smidr.input.UIFocus;
import smidr.widgets.UIButton;
import smidr.widgets.UICheckbox;
import smidr.widgets.UIDropdown;
import smidr.widgets.UILabel;
import smidr.widgets.UILoadingBar;
import smidr.widgets.UIPanel;
import smidr.widgets.UIScrollPane;
import smidr.widgets.UISeparator;
import smidr.widgets.UITabs;
import smidr.widgets.UITextInput;
import smidr.widgets.UIToast;
import smidr.widgets.UITooltip;

using StringTools;

/**
 * UI for the osu! beatmap converter. Drop or browse an `.osz` / `.osu` / folder,
 * tweak options, and convert into a playable modpack. Reached from MasterConverterState,
 * which guarantees ffmpeg is installed before this state opens.
 */
class OsuConverterState extends MusicBeatState {
	static inline var TMP_ROOT:String = '.osu_tmp';
	static inline var BAR_W:Int = 500;
	static inline var ZONE_X:Int = 40;
	static inline var ZONE_Y:Int = 80;
	static inline var ZONE_W:Int = 820;
	static inline var ZONE_H:Int = 430;
	static inline var BOX_W:Int = 360;
	static inline var BOX_H:Int = 470;

	var uiRoot:UIRoot;
	var queueLabel:UILabel;
	var statusLabel:UILabel;
	var fileDialog:FileDialogHandler;

	var tabs:UITabs;
	var tabPanes:Array<Sprite> = [];

	var pathInput:UITextInput;
	var packInput:UITextInput;
	var extraInput:UITextInput;
	var bitrateSel:String = '192k';
	var codecSel:String = 'vp9';
	var bgCheck:UICheckbox;
	var videoCheck:UICheckbox;
	var sbCheck:UICheckbox;
	var hsCheck:UICheckbox;
	var svCheck:UICheckbox;
	var quantizeCheck:UICheckbox;
	var stdKeySel:String = '4K';
	var stdKeysLabel:UILabel;
	var stdKeys:Array<Int> = [4];

	var logPane:UIScrollPane;
	var logLabel:UILabel;
	var logLines:Array<String> = [];
	var selectedPath:String = null;
	var queuedPaths:Array<String> = []; // batch: multiple dropped/browsed sources, all into one pack
	var busy:Bool = false;
	var cancelRequested:Bool = false;

	#if desktop
	var msgQueue:sys.thread.Deque<String> = new sys.thread.Deque<String>();
	#end

	var progBar:UILoadingBar;
	var stopBtn:UIButton;

	override function create() {
		FlxG.camera.bgColor = FlxColor.BLACK;
		persistentUpdate = true;
		FlxG.mouse.visible = true;
		FlxG.mouse.useSystemCursor = true;

		var bg:FlxSprite = new FlxSprite().loadGraphic(Paths.image('menuDesat'));
		bg.scrollFactor.set();
		bg.color = 0xFF15151F;
		add(bg);

		UILocale.translate = function(k:String, f:String):String return Language.getPhrase(k, f);
		UIFonts.register('assets/fonts/vcr.ttf');

		uiRoot = new UIRoot();
		attachRoot();
		syncViewport();
		UITooltip.install();
		FlxG.signals.gameResized.add(onGameResized);

		buildChrome();
		buildDropZone();
		buildBox();
		buildProgressBar();

		selectTab(0);
		log('Drop a .osz / .osu / folder onto the window, or use Browse.');

		#if desktop
		try
			openfl.Lib.application.window.onDropFile.add(onDropFile)
		catch (error:Dynamic)
			trace('drop listener failed: $error');
		#end

		super.create();
	}

	/** Layers the UI root above the game view but below the FPS counter (mirrors the other converters). **/
	function attachRoot():Void {
		var fps = Main.fpsVar;
		if (fps != null && fps.parent != null)
			uiRoot.attach(fps.parent, fps.parent.getChildIndex(fps));
		else
			uiRoot.attach(FlxG.stage);
	}

	function onGameResized(_:Int, _:Int):Void
		syncViewport();

	function syncViewport():Void {
		var sm = FlxG.scaleMode;
		uiRoot.setViewport(sm.offset.x, sm.offset.y, sm.scale.x, sm.scale.y);
	}

	function buildChrome():Void {
		var title:UILabel = new UILabel('osu! -> Psych Converter', 30, 0);
		title.x = ZONE_X;
		title.y = 14;
		uiRoot.content.addChild(title);

		var subtitle:UILabel = new UILabel('mania & std beatmaps to Friday Night Funkin', 14, 2);
		subtitle.x = ZONE_X;
		subtitle.y = 52;
		uiRoot.content.addChild(subtitle);

		statusLabel = new UILabel('ESC: back to Converters menu', 13, 2);
		statusLabel.x = 12;
		statusLabel.y = FlxG.height - 26;
		uiRoot.content.addChild(statusLabel);
	}

	function buildDropZone():Void {
		var panel:UIPanel = new UIPanel(ZONE_W, ZONE_H, UITheme.panel);
		panel.x = ZONE_X;
		panel.y = ZONE_Y;
		uiRoot.content.addChild(panel);

		var heading:UILabel = new UILabel('DROP BEATMAP HERE', 42, 0);
		heading.render();
		heading.x = ZONE_X + (ZONE_W - heading.width) / 2;
		heading.y = ZONE_Y + 64;
		uiRoot.content.addChild(heading);

		var hint:UILabel = new UILabel('drag a .osz, .osu, or a folder anywhere on the window', 17, 2);
		hint.render();
		hint.x = ZONE_X + (ZONE_W - hint.width) / 2;
		hint.y = ZONE_Y + 126;
		uiRoot.content.addChild(hint);

		var hint2:UILabel = new UILabel('or use Browse in the Input tab', 14, 3);
		hint2.render();
		hint2.x = ZONE_X + (ZONE_W - hint2.width) / 2;
		hint2.y = ZONE_Y + 152;
		uiRoot.content.addChild(hint2);

		var divider:UISeparator = new UISeparator(ZONE_W - 48, false);
		divider.x = ZONE_X + 24;
		divider.y = ZONE_Y + 200;
		uiRoot.content.addChild(divider);

		var qHead:UILabel = new UILabel('QUEUE', 15, 0);
		qHead.colorOverride = UITheme.accent;
		qHead.x = ZONE_X + 24;
		qHead.y = ZONE_Y + 210;
		uiRoot.content.addChild(qHead);

		queueLabel = new UILabel('', 14, 1);
		queueLabel.wrapWidth = ZONE_W - 48;
		queueLabel.x = ZONE_X + 24;
		queueLabel.y = ZONE_Y + 234;
		uiRoot.content.addChild(queueLabel);

		var clearBtn:UIButton = new UIButton('Clear queue', 130, 28, clearQueue);
		clearBtn.x = ZONE_X + 24;
		clearBtn.y = ZONE_Y + ZONE_H - 42;
		uiRoot.content.addChild(clearBtn);

		updateQueueText();
	}

	/** The right-hand tabbed box: Input / Options / Log panes under a shared panel + tab strip. **/
	function buildBox():Void {
		var boxX:Float = FlxG.width - 380;
		var boxY:Float = ZONE_Y;

		var panel:UIPanel = new UIPanel(BOX_W, BOX_H, UITheme.panel);
		panel.x = boxX;
		panel.y = boxY;
		uiRoot.content.addChild(panel);

		tabs = new UITabs(BOX_W, [{label: 'Input'}, {label: 'Options'}, {label: 'Log'}], selectTab);
		tabs.x = boxX;
		tabs.y = boxY;
		uiRoot.content.addChild(tabs);

		var paneY:Float = boxY + tabs.h + 8;
		tabPanes = [];
		for (i in 0...3) {
			var pane:Sprite = new Sprite();
			pane.x = boxX + 10;
			pane.y = paneY;
			pane.visible = false;
			uiRoot.content.addChild(pane);
			tabPanes.push(pane);
		}

		buildInputTab(tabPanes[0]);
		buildOptionsTab(tabPanes[1]);
		buildLogTab(tabPanes[2], BOX_H - tabs.h - 26);
	}

	function selectTab(index:Int):Void {
		for (i in 0...tabPanes.length)
			tabPanes[i].visible = (i == index);
		if (tabs.selectedIndex != index)
			tabs.select(index);
	}

	function paneLabel(pane:Sprite, x:Float, y:Float, text:String, size:Int = 12, tone:Int = 0):UILabel {
		var l:UILabel = new UILabel(text, size, tone);
		l.wrapWidth = BOX_W - 20 - x;
		l.x = x;
		l.y = y;
		pane.addChild(l);
		return l;
	}

	function buildInputTab(pane:Sprite):Void {
		paneLabel(pane, 0, 0, 'Source (.osz / .osu / folder):');
		pathInput = new UITextInput('', 340, '');
		pathInput.y = 22;
		pane.addChild(pathInput);

		var browse:UIButton = new UIButton('Browse file', 160, 26, browseFile);
		browse.y = 56;
		pane.addChild(browse);

		var browseDir:UIButton = new UIButton('Browse folder', 160, 26, browseFolder);
		browseDir.x = 172;
		browseDir.y = 56;
		pane.addChild(browseDir);

		paneLabel(pane, 0, 94, 'Tip: drag & drop anywhere. Batch: drop several files, or pick a folder of .osz - all go to one pack.', 11, 2);

		var convert:UIButton = new UIButton('CONVERT', 340, 40, startConvert, true);
		convert.fontSize = 15;
		convert.y = 150;
		pane.addChild(convert);
	}

	function buildOptionsTab(pane:Sprite):Void {
		var rowW:Float = 340;

		packInput = new UITextInput('Modpack name:', rowW, OsuConvertDefaults.PACK_NAME);
		packInput.boxWidth = 180;
		pane.addChild(packInput);

		var bitrateDrop:UIDropdown = new UIDropdown('Audio quality:', rowW, function(i:Int, v:String):Void bitrateSel = v);
		bitrateDrop.setItems(OsuConvertDefaults.AUDIO_BITRATES.copy());
		bitrateDrop.select(OsuConvertDefaults.AUDIO_BITRATES.indexOf('192k'));
		bitrateDrop.y = 30;
		pane.addChild(bitrateDrop);

		bgCheck = new UICheckbox('Convert background -> 1280x720', rowW, true);
		bgCheck.y = 62;
		pane.addChild(bgCheck);

		videoCheck = new UICheckbox('Convert video -> WebM', rowW);
		videoCheck.y = 88;
		pane.addChild(videoCheck);

		var codecDrop:UIDropdown = new UIDropdown('Video codec:', rowW, function(i:Int, v:String):Void codecSel = v);
		codecDrop.setItems(OsuConvertDefaults.VIDEO_CODECS.copy());
		codecDrop.select(OsuConvertDefaults.VIDEO_CODECS.indexOf('vp9'));
		codecDrop.y = 116;
		pane.addChild(codecDrop);

		extraInput = new UITextInput('Video extra ffmpeg args:', rowW, '');
		extraInput.boxWidth = 140;
		extraInput.y = 148;
		pane.addChild(extraInput);

		sbCheck = new UICheckbox('Convert storyboard (experimental)', rowW);
		sbCheck.y = 180;
		pane.addChild(sbCheck);

		svCheck = new UICheckbox('Mimic SV (osu! scroll behavior)', rowW);
		svCheck.y = 206;
		pane.addChild(svCheck);

		// SV now uses the engine's native Scroll Velocity events -- no bundled script, so no script choice.

		quantizeCheck = new UICheckbox('Quantize notes (auto-snap timing)', rowW);
		quantizeCheck.y = 232;
		pane.addChild(quantizeCheck);

		var stdKeyDrop:UIDropdown = new UIDropdown('osu!std -> mania:', 220, function(i:Int, v:String):Void stdKeySel = v);
		stdKeyDrop.setItems(['4K', '5K', '6K', '7K', '8K', '9K']);
		stdKeyDrop.select(0);
		stdKeyDrop.y = 272;
		pane.addChild(stdKeyDrop);

		var addKeyBtn:UIButton = new UIButton('+', 30, 22, addStdKey);
		addKeyBtn.x = 232;
		addKeyBtn.y = 272;
		pane.addChild(addKeyBtn);

		var resetKeyBtn:UIButton = new UIButton('Reset', 72, 22, resetStdKeys);
		resetKeyBtn.x = 268;
		resetKeyBtn.y = 272;
		pane.addChild(resetKeyBtn);

		stdKeysLabel = paneLabel(pane, 0, 304, '');
		updateStdKeysLabel();

		hsCheck = new UICheckbox('Convert hitsounds', rowW, true);
		hsCheck.y = 330;
		pane.addChild(hsCheck);
	}

	function buildLogTab(pane:Sprite, viewH:Float):Void {
		logPane = new UIScrollPane(BOX_W - 20, viewH);
		pane.addChild(logPane);

		logLabel = new UILabel('', 11, 1);
		logLabel.wrapWidth = BOX_W - 20 - UITheme.px(4) - 12;
		logLabel.x = 2;
		logLabel.y = 2;
		logPane.content.addChild(logLabel);
	}

	function buildProgressBar():Void {
		var barX:Float = (FlxG.width - BAR_W) / 2;
		var barY:Float = FlxG.height - 86;

		progBar = new UILoadingBar('', BAR_W);
		progBar.x = barX;
		progBar.y = barY;
		progBar.visible = false;
		uiRoot.content.addChild(progBar);

		stopBtn = new UIButton('Stop', 90, 24, requestStop);
		stopBtn.danger = true;
		stopBtn.x = barX + BAR_W + 12;
		stopBtn.y = barY;
		stopBtn.visible = false;
		uiRoot.content.addChild(stopBtn);
	}

	function clearQueue():Void {
		queuedPaths = [];
		if (pathInput != null)
			pathInput.text = '';
		updateQueueText();
		log('Queue cleared.');
	}

	function updateQueueText():Void {
		if (queueLabel == null)
			return;
		if (queuedPaths.length < 1) {
			queueLabel.text = 'nothing queued yet';
			return;
		}
		var lines:Array<String> = [];
		var max:Int = Std.int(Math.min(queuedPaths.length, 10));
		for (i in 0...max)
			lines.push('${i + 1}.  ' + haxe.io.Path.withoutDirectory(queuedPaths[i]));
		if (queuedPaths.length > max)
			lines.push('... and ${queuedPaths.length - max} more');
		queueLabel.text = lines.join('\n');
	}

	function addStdKey():Void {
		var k:Int = parseKeyLabel(stdKeySel);
		if (k >= 1 && !stdKeys.contains(k)) {
			stdKeys.push(k);
			stdKeys.sort((a, b) -> a - b);
			updateStdKeysLabel();
		}
	}

	function resetStdKeys():Void {
		stdKeys = [4];
		updateStdKeysLabel();
	}

	function updateStdKeysLabel():Void {
		if (stdKeysLabel != null)
			stdKeysLabel.text = 'Generates: ' + (stdKeys.length > 0 ? [for (k in stdKeys) '${k}K'].join(', ') : '(none -> 4K)');
	}

	function parseKeyLabel(label:String):Int {
		var n:Null<Int> = Std.parseInt(label.split('K')[0]);
		return (n == null) ? 4 : n;
	}

	function showProgressBar(show:Bool):Void {
		if (progBar != null)
			progBar.visible = show;
	}

	function setProgress(frac:Float, text:String):Void {
		if (frac < 0)
			frac = 0;
		if (frac > 1)
			frac = 1;
		if (progBar != null) {
			progBar.setProgress(frac);
			progBar.label = text;
		}
	}

	function ensureDialog():Void {
		if (fileDialog == null) {
			fileDialog = new FileDialogHandler();
			add(fileDialog);
		}
	}

	function browseFile():Void {
		if (busy)
			return;
		ensureDialog();
		if (!fileDialog.completed)
			return;
		fileDialog.open(null, 'Select an osu! beatmap', [new FileFilter('osu! beatmap', '*.osz;*.osu')], function() setPath(fileDialog.path));
	}

	function browseFolder():Void {
		if (busy)
			return;
		ensureDialog();
		if (!fileDialog.completed)
			return;
		fileDialog.openDirectory('Select a beatmap folder', function() setPath(fileDialog.path));
	}

	#if desktop
	function onDropFile(path:String):Void {
		if (busy)
			return;
		setPath(path);
	}
	#end

	function setPath(path:String):Void {
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

	function startConvert():Void {
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
		opts.audioBitrate = bitrateSel;
		opts.convertBackground = bgCheck.checked;
		opts.convertVideo = videoCheck.checked;
		opts.videoCodec = codecSel;
		opts.videoExtraArgs = extraInput.text;
		opts.convertStoryboard = sbCheck.checked;
		opts.convertHitsounds = hsCheck.checked;
		opts.mimicSV = svCheck.checked;
		opts.quantize = quantizeCheck.checked;
		opts.stdTargetKeys = stdKeys.copy();

		queuedPaths = []; // consumed by this run
		updateQueueText();
		logLines = [];
		refreshLog();
		selectTab(2); // jump to the Log tab
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

	function requestStop():Void {
		if (!busy || cancelRequested)
			return;
		cancelRequested = true;
		log('Stopping... (waiting for the current step to halt)');
		MediaConverter.cancel();
		refreshStopButton();
	}

	function refreshStopButton():Void {
		if (stopBtn != null)
			stopBtn.visible = busy && !cancelRequested;
	}

	function finishConvert(result:String):Void {
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
				UIToast.show('Conversion complete.');
			default:
				log('Conversion finished with errors (see log above).');
		}
	}

	function log(line:String):Void {
		logLines.push(line);
		while (logLines.length > 200)
			logLines.shift();
		refreshLog();
		trace('[osu-convert] $line');
	}

	function refreshLog():Void {
		if (logLabel == null || logPane == null)
			return;
		logLabel.text = logLines.join('\n');
		logPane.refreshContent(logLabel.measure() + 8);
		logPane.setScroll(1e9); // clamped to the bottom
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

		if (!busy && subState == null && !UIRoot.overlayOpen && UIFocus.focused == null && controls.BACK) {
			#if desktop
			try
				openfl.Lib.application.window.onDropFile.remove(onDropFile)
			catch (error:Dynamic) {}
			#end
			FlxG.sound.play(Paths.sound('cancelMenu'));
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
		FlxG.signals.gameResized.remove(onGameResized);
		FlxG.mouse.useSystemCursor = false;
		FlxG.mouse.visible = false;
		UITooltip.reset();
		if (uiRoot != null) {
			uiRoot.dispose();
			uiRoot = null;
		}
		super.destroy();
	}
}
#end
