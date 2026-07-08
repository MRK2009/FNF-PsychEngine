package states.converters;

#if CONVERTERS_ALLOWED
import backend.osu.OsuManiaSkinConvertJob;
import editors.content.FileDialogHandler;
import flash.net.FileFilter;
import smidr.UIRoot;
import smidr.UITheme;
import smidr.UIFonts;
import smidr.UILocale;
import smidr.input.UIFocus;
import smidr.widgets.UIButton;
import smidr.widgets.UILabel;
import smidr.widgets.UIPanel;

using StringTools;

/**
	UI for the osu! mania SKIN converter. Drop (or browse) a `.osk` archive or a folder containing
	`skin.ini`, and convert it into a Psych folder note skin under `mods/osu!Mania skin conversions`.
	Needs no external tools (just file copies + a `skin.json`), so it's reached directly from
	MasterConverterState without the ffmpeg gate.
**/
class OsuSkinConverterState extends MusicBeatState {
	static inline var TMP_ROOT:String = '.osu_skin_tmp';
	static inline var ZONE_X:Int = 40;
	static inline var ZONE_Y:Int = 70;
	static inline var ZONE_W:Int = 820;
	static inline var ZONE_H:Int = 230;

	var uiRoot:UIRoot;
	var fileDialog:FileDialogHandler;
	var queued:Array<String> = [];
	var queueLabel:UILabel;
	var logLabel:UILabel;
	var logLines:Array<String> = [];
	var busy:Bool = false;

	override function create() {
		FlxG.camera.bgColor = FlxColor.BLACK;
		persistentUpdate = true;
		FlxG.mouse.visible = true;
		FlxG.mouse.useSystemCursor = true;
		fileDialog = new FileDialogHandler();

		var bg:FlxSprite = new FlxSprite().loadGraphic(Paths.image('menuDesat'));
		bg.scrollFactor.set();
		bg.color = 0xFF20202A;
		add(bg);

		UILocale.translate = function(k:String, f:String):String return Language.getPhrase(k, f);
		UIFonts.register('assets/fonts/vcr.ttf');

		uiRoot = new UIRoot();
		attachRoot();
		syncViewport();
		FlxG.signals.gameResized.add(onGameResized);

		var title:UILabel = new UILabel('osu!Mania SKIN CONVERTER', 22, 0);
		title.x = 20;
		title.y = 18;
		uiRoot.content.addChild(title);

		var panel:UIPanel = new UIPanel(ZONE_W, ZONE_H, UITheme.panel);
		panel.x = ZONE_X;
		panel.y = ZONE_Y;
		uiRoot.content.addChild(panel);

		var heading:UILabel = new UILabel('DROP osu! SKIN HERE', 40, 0);
		heading.render();
		heading.x = ZONE_X + (ZONE_W - heading.width) / 2;
		heading.y = ZONE_Y + 44;
		uiRoot.content.addChild(heading);

		var hint:UILabel = new UILabel('drag a .osk file or a folder containing skin.ini onto the window', 16, 2);
		hint.render();
		hint.x = ZONE_X + (ZONE_W - hint.width) / 2;
		hint.y = ZONE_Y + 104;
		uiRoot.content.addChild(hint);

		queueLabel = new UILabel('', 16, 1);
		queueLabel.colorOverride = UITheme.warning;
		queueLabel.x = ZONE_X;
		queueLabel.y = ZONE_Y + 150;
		uiRoot.content.addChild(queueLabel);

		var btnY:Float = ZONE_Y + ZONE_H + 12;
		addButton('Browse .osk', ZONE_X, btnY, 160, browseFile);
		addButton('Browse folder', ZONE_X + 170, btnY, 160, browseFolder);
		var convert:UIButton = addButton('Convert', ZONE_X + 340, btnY, 160, startConvert);
		convert.accent = true;
		addButton('Clear', ZONE_X + 510, btnY, 120, clearQueue);

		logLabel = new UILabel('', 15, 1);
		logLabel.wrapWidth = ZONE_W;
		logLabel.x = ZONE_X;
		logLabel.y = btnY + 44;
		uiRoot.content.addChild(logLabel);

		log('Drop a .osk / skin folder onto the window, or use Browse.');
		updateQueueText();

		#if desktop
		try
			openfl.Lib.application.window.onDropFile.add(onDropFile)
		catch (e:Dynamic)
			trace('drop listener failed: $e');
		#end

		super.create();
	}

	function addButton(label:String, x:Float, y:Float, w:Float, onClick:Void->Void):UIButton {
		var btn:UIButton = new UIButton(label, w, 28, onClick);
		btn.x = x;
		btn.y = y;
		uiRoot.content.addChild(btn);
		return btn;
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

	override function update(elapsed:Float) {
		super.update(elapsed);
		if (!busy && subState == null && !UIRoot.overlayOpen && UIFocus.focused == null && controls.BACK) {
			#if desktop
			try
				openfl.Lib.application.window.onDropFile.remove(onDropFile)
			catch (e:Dynamic) {}
			#end
			FlxG.sound.play(Paths.sound('cancelMenu'));
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
		queueLabel.text = (queued.length < 1) ? 'Nothing queued.' : '${queued.length} skin(s) queued';
		queueLabel.render();
		queueLabel.x = ZONE_X + (ZONE_W - queueLabel.width) / 2;
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
		if (logLabel != null)
			logLabel.text = logLines.join('\n');
		trace('[osu skin] ' + line);
	}

	override function destroy() {
		#if desktop
		try
			openfl.Lib.application.window.onDropFile.remove(onDropFile)
		catch (e:Dynamic) {}
		#end
		FlxG.signals.gameResized.remove(onGameResized);
		FlxG.mouse.useSystemCursor = false;
		FlxG.mouse.visible = false;
		if (uiRoot != null) {
			uiRoot.dispose();
			uiRoot = null;
		}
		super.destroy();
	}
}
#end
