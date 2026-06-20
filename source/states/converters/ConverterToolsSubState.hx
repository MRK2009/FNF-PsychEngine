package states.converters;

#if CONVERTERS_ALLOWED
import flixel.FlxG;
import flixel.FlxSprite;
import flixel.text.FlxText;
import flixel.util.FlxColor;
import flixel.math.FlxRect;
import backend.tools.MediaConverter;

using StringTools;

/**
 * Popup shown by MasterConverterState when a converter needs an external tool
 * (ffmpeg) that isn't installed yet. Explains that a free third-party tool will
 * be downloaded, and on Accept downloads + installs it with a progress bar.
 * Mirrors the ModSecuritySubstate trust-prompt style. Reusable across converters.
 */
class ConverterToolsSubState extends MusicBeatSubstate {
	static inline final PANEL_W:Int = 760;
	static inline final PANEL_H:Int = 380;
	static inline final BORDER:Int = 3;
	static inline final BAR_W:Int = PANEL_W - 80;
	static inline final BAR_FILL_W:Int = PANEL_W - 84;

	// 'prompt' -> ask; 'downloading' -> progress; 'failed' -> retry/cancel.
	var phase:String = 'prompt';
	var onReady:Void->Void;

	var titleTxt:FlxText;
	var bodyTxt:FlxText;
	var hintTxt:FlxText;

	var acceptTxt:Alphabet;
	var cancelTxt:Alphabet;
	var arrowL:FlxText;
	var arrowR:FlxText;
	var onAccept:Bool = true;

	var barBG:FlxSprite;
	var barFill:FlxSprite;

	var panelX:Float = 0;
	var panelY:Float = 0;
	var btnY:Float = 0;

	#if desktop
	var msgQueue:sys.thread.Deque<String> = new sys.thread.Deque<String>();
	#end
	var downloading:Bool = false;
	var dlTotal:Int = -1;
	var dlDest:String = null;

	public function new(onReady:Void->Void) {
		super();
		this.onReady = onReady;
	}

	override function create() {
		super.create();

		var dim:FlxSprite = new FlxSprite().makeGraphic(1, 1, FlxColor.BLACK);
		dim.scale.set(FlxG.width, FlxG.height);
		dim.updateHitbox();
		dim.alpha = 0.78;
		dim.scrollFactor.set();
		add(dim);

		panelX = (FlxG.width - PANEL_W) * 0.5;
		panelY = (FlxG.height - PANEL_H) * 0.5;

		var border:FlxSprite = new FlxSprite(panelX - BORDER, panelY - BORDER).makeGraphic(1, 1, 0xFFFFD24A);
		border.scale.set(PANEL_W + BORDER * 2, PANEL_H + BORDER * 2);
		border.updateHitbox();
		border.scrollFactor.set();
		add(border);

		var panel:FlxSprite = new FlxSprite(panelX, panelY).makeGraphic(1, 1, 0xFF14161E);
		panel.scale.set(PANEL_W, PANEL_H);
		panel.updateHitbox();
		panel.alpha = 0.96;
		panel.scrollFactor.set();
		add(panel);

		var headerBar:FlxSprite = new FlxSprite(panelX, panelY).makeGraphic(1, 1, 0xFF1F2230);
		headerBar.scale.set(PANEL_W, 56);
		headerBar.updateHitbox();
		headerBar.scrollFactor.set();
		add(headerBar);

		titleTxt = new FlxText(panelX + 18, panelY + 12, PANEL_W - 36, 'External Tools Required', 24);
		titleTxt.setFormat(Paths.font('vcr.ttf'), 24, 0xFFFFD24A, LEFT, OUTLINE, FlxColor.BLACK);
		titleTxt.borderSize = 1.5;
		titleTxt.scrollFactor.set();
		add(titleTxt);

		bodyTxt = new FlxText(panelX + 18, panelY + 74, PANEL_W - 36, '', 16);
		bodyTxt.setFormat(Paths.font('vcr.ttf'), 16, FlxColor.WHITE, LEFT, OUTLINE, FlxColor.BLACK);
		bodyTxt.borderSize = 1.25;
		bodyTxt.scrollFactor.set();
		add(bodyTxt);

		btnY = panelY + PANEL_H - 96;

		acceptTxt = new Alphabet(0, btnY, 'ACCEPT', true);
		acceptTxt.scrollFactor.set();
		add(acceptTxt);

		cancelTxt = new Alphabet(0, btnY, 'CANCEL', true);
		cancelTxt.scrollFactor.set();
		add(cancelTxt);

		arrowL = makeArrow('>');
		arrowR = makeArrow('<');

		hintTxt = new FlxText(panelX, panelY + PANEL_H - 30, PANEL_W, 'Left/Right to choose -- Enter to confirm', 14);
		hintTxt.setFormat(Paths.font('vcr.ttf'), 14, 0xFFB0B0B0, CENTER, OUTLINE, FlxColor.BLACK);
		hintTxt.borderSize = 1;
		hintTxt.scrollFactor.set();
		add(hintTxt);

		// Progress bar (hidden until a download starts).
		barBG = new FlxSprite(panelX + 40, btnY + 6).makeGraphic(BAR_W, 26, 0xFF1E1E1E);
		barBG.scrollFactor.set();
		add(barBG);
		barFill = new FlxSprite(panelX + 42, btnY + 8).makeGraphic(BAR_FILL_W, 22, 0xFF55CC55);
		barFill.scrollFactor.set();
		add(barFill);

		setPromptBody();
		showButtons(true);
		updateButtons();
	}

	function makeArrow(symbol:String):FlxText {
		var arrow:FlxText = new FlxText(0, btnY, 40, symbol, 36);
		arrow.setFormat(Paths.font('vcr.ttf'), 36, FlxColor.YELLOW, CENTER, OUTLINE, FlxColor.BLACK);
		arrow.borderSize = 2;
		arrow.scrollFactor.set();
		add(arrow);
		return arrow;
	}

	function setPromptBody() {
		bodyTxt.text = 'This converter uses ffmpeg, a free third-party tool, to convert\n'
			+ 'audio and video files.\n\n'
			+ 'ffmpeg is not installed. Press ACCEPT to download it (~100 MB)\n'
			+ 'from the BtbN FFmpeg-Builds GitHub release into tools/ffmpeg/.\n\n'
			+ 'Nothing is uploaded; the tool is only used locally on your PC.';
	}

	function showButtons(show:Bool) {
		acceptTxt.visible = show;
		cancelTxt.visible = show;
		arrowL.visible = show;
		arrowR.visible = show;
		hintTxt.visible = show;
		barBG.visible = !show;
		barFill.visible = !show;
	}

	function updateButtons() {
		var acceptScale:Float = onAccept ? 1.0 : 0.65;
		var cancelScale:Float = onAccept ? 0.65 : 1.0;
		acceptTxt.setScale(acceptScale);
		cancelTxt.setScale(cancelScale);
		acceptTxt.alpha = onAccept ? 1.0 : 0.4;
		cancelTxt.alpha = onAccept ? 0.4 : 1.0;

		var acceptColor:FlxColor = onAccept ? 0xFF22FF55 : 0xFFAAAAAA;
		var cancelColor:FlxColor = onAccept ? 0xFFAAAAAA : 0xFFFF3344;
		for (letter in acceptTxt.letters)
			letter.color = acceptColor;
		for (letter in cancelTxt.letters)
			letter.color = cancelColor;

		acceptTxt.x = (panelX + PANEL_W * 0.32) - acceptTxt.width * 0.5;
		acceptTxt.y = btnY + (1.0 - acceptScale) * 22;
		cancelTxt.x = (panelX + PANEL_W * 0.68) - cancelTxt.width * 0.5;
		cancelTxt.y = btnY + (1.0 - cancelScale) * 22;

		var selected = onAccept ? acceptTxt : cancelTxt;
		var gap:Float = 8;
		arrowL.x = selected.x - arrowL.width - gap;
		arrowL.y = selected.y + (selected.height - arrowL.height) * 0.5;
		arrowR.x = selected.x + selected.width + gap;
		arrowR.y = selected.y + (selected.height - arrowR.height) * 0.5;
		arrowL.color = onAccept ? 0xFF22FF55 : 0xFFFF3344;
		arrowR.color = arrowL.color;
	}

	function setProgress(frac:Float, text:String) {
		if (frac < 0)
			frac = 0;
		if (frac > 1)
			frac = 1;
		barFill.clipRect = new FlxRect(0, 0, BAR_FILL_W * frac, 22);
		bodyTxt.text = text;
	}

	function startDownload() {
		#if desktop
		if (downloading)
			return;
		phase = 'downloading';
		downloading = true;
		dlTotal = -1;
		var zip:String = '.osu_tmp/ffmpeg_dl.zip';
		dlDest = zip;
		titleTxt.text = 'Downloading ffmpeg';
		showButtons(false);
		setProgress(0, 'Preparing download...');

		sys.thread.Thread.create(function() {
			msgQueue.add('__TOTAL__:' + MediaConverter.getContentLength(MediaConverter.DOWNLOAD_URL));
			var ok:Bool = MediaConverter.downloadFile(MediaConverter.DOWNLOAD_URL, zip);
			if (ok) {
				msgQueue.add('__EXTRACT__');
				ok = MediaConverter.installFfmpegFromZip(zip);
			}
			try
				if (sys.FileSystem.exists(zip)) sys.FileSystem.deleteFile(zip)
			catch (error:Dynamic) {}
			msgQueue.add(ok ? '__DONE__:ok' : '__DONE__:fail');
		});
		#else
		fail();
		#end
	}

	function succeed() {
		downloading = false;
		if (onReady != null)
			onReady();
		close();
	}

	function fail() {
		downloading = false;
		dlDest = null;
		phase = 'failed';
		titleTxt.text = 'Download Failed';
		bodyTxt.text = 'ffmpeg could not be downloaded.\n\n'
			+ 'Check your internet connection (the download uses the system curl)\n'
			+ 'and press ACCEPT to retry, or CANCEL to go back.';
		onAccept = true;
		showButtons(true);
		updateButtons();
	}

	override function update(elapsed:Float) {
		super.update(elapsed);

		#if desktop
		if (downloading && msgQueue != null) {
			var msg:String = msgQueue.pop(false);
			while (msg != null) {
				if (msg.startsWith('__TOTAL__:')) {
					var parsed:Null<Int> = Std.parseInt(msg.substr(10));
					dlTotal = (parsed == null) ? -1 : parsed;
				} else if (msg == '__EXTRACT__') {
					dlDest = null;
					setProgress(1, 'Installing ffmpeg.exe...');
				} else if (msg == '__DONE__:ok') {
					succeed();
					return;
				} else if (msg == '__DONE__:fail') {
					fail();
				}
				msg = msgQueue.pop(false);
			}
			pollProgress();
		}
		#end

		if (downloading)
			return; // ignore input while a download is in flight

		if (controls.BACK) {
			FlxG.sound.play(Paths.sound('cancelMenu'), 0.6);
			close();
			return;
		}
		if (controls.UI_LEFT_P || controls.UI_RIGHT_P) {
			FlxG.sound.play(Paths.sound('scrollMenu'), 0.6);
			onAccept = !onAccept;
			updateButtons();
		}
		if (controls.ACCEPT) {
			if (onAccept) {
				FlxG.sound.play(Paths.sound('confirmMenu'), 0.6);
				startDownload();
			} else {
				FlxG.sound.play(Paths.sound('cancelMenu'), 0.6);
				close();
			}
		}
	}

	#if desktop
	function pollProgress() {
		if (dlDest == null)
			return;
		var size:Float = 0;
		try
			if (sys.FileSystem.exists(dlDest)) size = sys.FileSystem.stat(dlDest).size
		catch (error:Dynamic) {}
		var mb:Float = size / 1048576;
		if (dlTotal > 0) {
			var frac:Float = size / dlTotal;
			setProgress(frac, 'Downloading ffmpeg: ${Math.round(frac * 100)}%\n(${fmt1(mb)} / ${fmt1(dlTotal / 1048576)} MB)');
		} else {
			setProgress(Math.min(0.95, size / (100 * 1048576)), 'Downloading ffmpeg...\n${fmt1(mb)} MB');
		}
	}
	#end

	inline function fmt1(value:Float):String
		return Std.string(Math.round(value * 10) / 10);
}
#end
