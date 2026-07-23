package options;

import objects.Character;
import objects.notes.Receptor;
import objects.notes.NoteSprite;
import objects.notes.NoteData;
import backend.LatencyProbe;
import states.stages.StageWeek1 as BackgroundStage;
import smidr.UIRoot;
import smidr.UITheme;
import smidr.types.UITone;
import smidr.widgets.UILabel;
import smidr.widgets.UIButton;
import smidr.widgets.UISlider;
import smidr.widgets.UISegmentedControl;
import smidr.flixel.FlxSmidr;
import openfl.text.TextFormatAlign;

/**
 * Offset calibration menu. Two tabs:
 *
 * - AUDIO: tunes `ClientPrefs.data.noteOffset` (the judgement offset baked into note times).
 * - VISUAL: tunes `ClientPrefs.data.visualOffset` (render-only note shift).
 *
 * Each offset can be set three ways: the manual slider / arrow keys, a hardware estimate (audio only,
 * via `LatencyProbe`), or a guided **Start Calibration** run:
 * - Audio calibration plays a metronome beep with NO visual aid and asks the user to tap along.
 * - Visual calibration shows a single receptor lane and asks the user to press when a note lands.
 *
 * Either guided run is free tapping: sixteen presses are collected and averaged into the offset.
 *
 * The chrome (tabs, slider, buttons, readouts) is built with **Smidr** over an OpenFL overlay. The game
 * assets (week1 stage + characters, and the receptor/falling notes) render underneath in a framed flixel
 * viewport: `camGame` is a sub-rect camera and the receptor/notes ride the fullscreen `camHUD`.
 */
class NoteOffsetState extends MusicBeatState {
	static inline var TAB_AUDIO:Int = 0;
	static inline var TAB_VISUAL:Int = 1;

	static inline var VP_X:Int = 340;
	static inline var VP_Y:Int = 108;
	static inline var VP_W:Int = 600;
	static inline var VP_H:Int = 300;

	static inline var NOTE_POOL:Int = 5;
	static inline var PX_PER_MS:Float = 0.4;

	static inline var CALIB_HITS:Int = 16;

	var stageDirectory:String = 'week1';
	var boyfriend:Character;
	var gf:Character;

	public var camHUD:FlxCamera;
	public var camGame:FlxCamera;

	var delayMin:Int = -500;
	var delayMax:Int = 500;

	var barPercent:Float = 0;
	var tab:Int = TAB_AUDIO;

	var beatText:Alphabet;
	var beatTween:FlxTween;

	var receptor:Receptor;
	var notes:Array<NoteSprite> = [];
	var noteTargets:Array<Float> = [];
	var receptorY:Float = 0;
	var receptorCX:Float = 0;
	var receptorCY:Float = 0;
	var frameBars:Array<FlxSprite> = [];
	var backdrop:FlxSprite;

	var tapSamples:Array<Float> = [];
	var hardwareMs:Null<Int> = null;

	var calibActive:Bool = false;
	var calibSamples:Array<Float> = [];
	var metroBeat:Int = -1;

	var uiRoot:UIRoot;
	var titleLbl:UILabel;
	var tabsCtrl:UISegmentedControl;
	var instrLbl:UILabel;
	var tapLbl:UILabel;
	var statusLbl:UILabel;
	var calibPrompt:UILabel;
	var slider:UISlider;
	var startBtn:UIButton;
	var detectBtn:UIButton;
	var resetBtn:UIButton;
	var backBtn:UIButton;
	var statusTime:Float = 0;

	override public function create() {
		#if DISCORD_ALLOWED
		DiscordClient.changePresence("Offset Calibration", null);
		#end

		camGame = new FlxCamera(VP_X, VP_Y, VP_W, VP_H);
		camGame.bgColor = FlxColor.BLACK;
		FlxG.cameras.reset(camGame);
		FlxG.cameras.setDefaultDrawTarget(camGame, true);

		camHUD = new FlxCamera();
		camHUD.bgColor.alpha = 0;
		FlxG.cameras.add(camHUD, false);

		_psychCameraInitialized = true;

		camGame.scroll.set(220, 130);
		camGame.zoom = 0.85;

		persistentUpdate = true;
		FlxG.sound.pause();

		Paths.setCurrentLevel(stageDirectory);
		new BackgroundStage();

		gf = new Character(400, 130, 'gf');
		gf.x += gf.positionArray[0];
		gf.y += gf.positionArray[1];
		gf.scrollFactor.set(0.95, 0.95);
		boyfriend = new Character(770, 100, 'bf', true);
		boyfriend.x += boyfriend.positionArray[0];
		boyfriend.y += boyfriend.positionArray[1];
		add(gf);
		add(boyfriend);

		beatText = new Alphabet(0, 0,
			Language.getPhrase('delay_beat_hit', 'Beat Hit!'), true);
		beatText.setScale(0.6, 0.6);
		beatText.x += 260;
		beatText.alpha = 0;
		beatText.acceleration.y = 250;
		add(beatText);

		buildBackdrop();
		buildFrame();
		buildVisualTarget();

		hardwareMs = LatencyProbe.estimateMs();

		#if mobile
		UITheme.applyMobilePreset();
		#end
		uiRoot = FlxSmidr.init();
		FlxSmidr.autoBlockMouse = true;
		FlxG.mouse.visible = true;
		buildChrome();
		FlxG.signals.gameResized.add(onGameResized);

		Conductor.bpm = 128.0;
		FlxG.sound.playMusic(Paths.music('offsetSong'), 1, true);

		super.create();

		#if mobile
		addTouchPad('LEFT_RIGHT', 'A_B_C');
		#end

		applyTab(TAB_AUDIO);
	}

	/** Full-screen 50% black backing, always on, so the viewport and chrome read against a dimmed stage. **/
	function buildBackdrop():Void {
		backdrop = new FlxSprite().makeGraphic(FlxG.width, FlxG.height, FlxColor.BLACK);
		backdrop.scrollFactor.set();
		backdrop.cameras = [camHUD];
		backdrop.alpha = 0.5;
		add(backdrop);
	}

	/** Draws the flixel viewport frame (four thin bars around the asset camera's rect) on camHUD. **/
	function buildFrame():Void {
		var frameColor:FlxColor = 0xFF3D2E57;
		frameBars = [
			makeFrameBar(VP_X - 4, VP_Y - 4, VP_W + 8, 4, frameColor),
			makeFrameBar(VP_X - 4, VP_Y + VP_H, VP_W + 8, 4, frameColor),
			makeFrameBar(VP_X - 4, VP_Y, 4, VP_H, frameColor),
			makeFrameBar(VP_X + VP_W, VP_Y, 4, VP_H, frameColor)
		];
		for (bar in frameBars)
			add(bar);
	}

	inline function makeFrameBar(x:Float, y:Float, w:Int, h:Int,
			color:FlxColor):FlxSprite {
		var s:FlxSprite = new FlxSprite(x, y).makeGraphic(w, h, color);
		s.scrollFactor.set();
		s.cameras = [camHUD];
		return s;
	}

	/** Builds the real receptor landing target and its pool of falling note markers (visual tab). **/
	function buildVisualTarget():Void {
		var prevOverride:String = backend.NoteSkinConfig.editorOverride;
		var prevMania:Int = Mania.current;
		backend.NoteSkinConfig.editorOverride = backend.NoteSkinConfig.DEFAULT;
		Mania.apply(4);

		receptor = new Receptor(0, 0, 2, 0, 4);
		receptor.x = VP_X + (VP_W - receptor.width) / 2;
		receptor.y = VP_Y + 64;
		receptor.cameras = [camHUD];
		receptorY = receptor.y;
		receptorCX = receptor.x + receptor.width / 2;
		receptorCY = receptor.y + receptor.height / 2;
		add(receptor);

		var noteData:NoteData = new NoteData();
		noteData.column = 2;
		for (i in 0...NOTE_POOL) {
			var note:NoteSprite = new NoteSprite();
			note.apply(noteData, 4);
			note.scrollFactor.set();
			note.cameras = [camHUD];
			note.visible = false;
			notes.push(note);
			noteTargets.push(0);
			add(note);
		}

		backend.NoteSkinConfig.editorOverride = prevOverride;
		Mania.apply(prevMania);
	}

	/** Builds the Smidr chrome widgets and lays them out. **/
	function buildChrome():Void {
		titleLbl = new UILabel(Language.getPhrase('offset_calibration',
			'Offset Calibration')
			.toUpperCase(),
			30, PRIMARY, TextFormatAlign.CENTER);
		uiRoot.content.addChild(titleLbl);

		tabsCtrl = new UISegmentedControl('', 360, [
			Language.getPhrase('offset_tab_audio', 'AUDIO'),
			Language.getPhrase('offset_tab_visual', 'VISUAL')
		], function(i:Int) applyTab(i));
		uiRoot.content.addChild(tabsCtrl);

		instrLbl = new UILabel('', 15, SECONDARY, TextFormatAlign.CENTER);
		uiRoot.content.addChild(instrLbl);

		tapLbl = new UILabel('', 16, PRIMARY, TextFormatAlign.CENTER);
		uiRoot.content.addChild(tapLbl);

		statusLbl = new UILabel('', 16, PRIMARY, TextFormatAlign.CENTER);
		uiRoot.content.addChild(statusLbl);

		calibPrompt = new UILabel('', 24, PRIMARY, TextFormatAlign.CENTER);
		calibPrompt.visible = false;
		uiRoot.content.addChild(calibPrompt);

		slider = new UISlider(Language.getPhrase('offset_value_audio',
			'Audio Offset (ms)'), 520,
			delayMin, delayMax, 0, function(v:Float) {
				barPercent = v;
				writeOffset();
				clearTaps();
		});
		slider.decimals = 0;
		uiRoot.content.addChild(slider);

		startBtn = new UIButton(Language.getPhrase('offset_btn_start',
			'Start Calibration'), 220, 44,
			function() startCalibration(), true);
		uiRoot.content.addChild(startBtn);

		detectBtn = new UIButton(Language.getPhrase('offset_btn_detect',
			'Detect Hardware'), 220, 44,
			function() detectHardware());
		uiRoot.content.addChild(detectBtn);

		resetBtn = new UIButton(Language.getPhrase('offset_btn_reset', 'Reset'), 140,
			44, function() {
				barPercent = 0;
				writeOffset();
				slider.value = 0;
				clearTaps();
		});
		uiRoot.content.addChild(resetBtn);

		backBtn = new UIButton(Language.getPhrase('offset_btn_back', 'Back'), 140, 44,
			function() exitState());
		uiRoot.content.addChild(backBtn);

		layoutChrome();
	}

	/** Positions the Smidr chrome from the current screen size (re-run on resize). **/
	function layoutChrome():Void {
		var cx:Float = FlxG.width / 2;

		titleLbl.x = cx - titleLbl.width / 2;
		titleLbl.y = 16;

		tabsCtrl.x = cx - 180;
		tabsCtrl.y = 56;

		instrLbl.wrapWidth = 900;
		instrLbl.x = cx - 450;
		instrLbl.y = VP_Y + VP_H + 14;

		tapLbl.wrapWidth = 600;
		tapLbl.x = cx - 300;
		tapLbl.y = VP_Y + VP_H + 40;

		statusLbl.wrapWidth = 600;
		statusLbl.x = cx - 300;
		statusLbl.y = VP_Y + VP_H + 66;

		calibPrompt.wrapWidth = 900;
		calibPrompt.x = cx - 450;
		calibPrompt.y = VP_Y + VP_H + 30;

		slider.x = cx - 260;
		slider.y = VP_Y + VP_H + 98;

		var by:Float = VP_Y + VP_H + 148;
		var row:Array<UIButton> = (tab == TAB_AUDIO) ? [startBtn, detectBtn, resetBtn, backBtn] : [startBtn, resetBtn, backBtn];
		var gap:Float = 18;
		var total:Float = 0;
		for (b in row)
			total += b.width + gap;
		total -= gap;
		var x:Float = cx - total / 2;
		for (b in row) {
			b.x = x;
			b.y = by;
			x += b.width + gap;
		}
	}

	function onGameResized(w:Int, h:Int):Void {
		if (uiRoot != null)
			layoutChrome();
	}

	override public function update(elapsed:Float) {
		if (statusTime > 0) {
			statusTime -= elapsed;
			if (statusTime <= 0)
				statusLbl.text = '';
		}

		if (FlxG.sound.music != null)
			Conductor.songPosition = FlxG.sound.music.time;

		if (calibActive)
			updateCalibration(elapsed);
		else
			updateMenu(elapsed);

		super.update(elapsed);
	}

	var holdTime:Float = 0;

	/** Normal (non-calibrating) menu input: tabs, free-form tap, manual adjust, reset, back. **/
	function updateMenu(elapsed:Float):Void {
		if (FlxG.keys.justPressed.Q)
			pickTab(TAB_AUDIO);
		else if (FlxG.keys.justPressed.E)
			pickTab(TAB_VISUAL);

		if (FlxG.keys.justPressed.SPACE || FlxG.keys.justPressed.ENTER
			|| touchPadJustPressed('A'))
			registerTap();

		var addNum:Int = 3;
		if (FlxG.keys.pressed.SHIFT || FlxG.gamepads.anyPressed(LEFT_SHOULDER))
			addNum = 10;

		if (controls.UI_LEFT_P) {
			barPercent -= 1;
			nudge();
		} else if (controls.UI_RIGHT_P) {
			barPercent += 1;
			nudge();
		}

		var mult:Int = 1;
		if (controls.UI_LEFT || controls.UI_RIGHT) {
			holdTime += elapsed;
			if (controls.UI_LEFT)
				mult = -1;
		}

		if (controls.UI_LEFT_R || controls.UI_RIGHT_R)
			holdTime = 0;

		if (holdTime > 0.5) {
			barPercent += 100 * addNum * elapsed * mult;
			nudge();
		}

		if (controls.RESET) {
			holdTime = 0;
			barPercent = 0;
			nudge();
		}

		if (controls.BACK)
			exitState();

		if (tab == TAB_VISUAL)
			positionNotes();
	}

	/** Applies a keyboard-driven offset change: writes the pref, syncs the slider and drops tap samples. **/
	function nudge():Void {
		writeOffset();
		slider.value = barPercent;
		clearTaps();
	}

	/** Keyboard tab switch: moves the segmented control (no callback) then runs the tab logic. **/
	function pickTab(which:Int):Void {
		tabsCtrl.select(which);
		applyTab(which);
	}

	function applyTab(which:Int):Void {
		tab = which;
		holdTime = 0;
		barPercent = activeOffset();
		tapSamples = [];

		var isAudio:Bool = (tab == TAB_AUDIO);
		beatText.visible = isAudio;
		receptor.visible = !isAudio;
		for (n in notes)
			n.visible = false;

		detectBtn.visible = isAudio;
		detectBtn.alpha = (hardwareMs != null) ? 1 : 0.5;

		slider.label = isAudio ? Language.getPhrase('offset_value_audio',
			'Audio Offset (ms)') : Language.getPhrase('offset_value_visual',
				'Visual Offset (ms)');
		slider.value = barPercent;

		instrLbl.text = isAudio ? Language.getPhrase('offset_help_audio',
			'Tap Space to the beat, drag the slider, or press Start Calibration.') : Language.getPhrase('offset_help_visual',
				'Tap Space when a note lands, drag the slider, or press Start Calibration.');

		if (!isAudio)
			seedNotes();

		layoutChrome();
		updateTapLabel();
	}

	inline function activeOffset():Int {
		return
			(tab == TAB_AUDIO) ? ClientPrefs.data.noteOffset : ClientPrefs.data.visualOffset;
	}

	/** Time between presses: half the song BPM, so the user has a beat's rest between each tap. **/
	inline function pressInterval():Float {
		return Conductor.crochet * 2;
	}

	/** Clamps the working value and writes it to the active pref. **/
	function writeOffset():Void {
		if (barPercent < delayMin)
			barPercent = delayMin;
		else if (barPercent > delayMax)
			barPercent = delayMax;
		var v:Int = Math.round(barPercent);
		if (tab == TAB_AUDIO)
			ClientPrefs.data.noteOffset = v;
		else
			ClientPrefs.data.visualOffset = v;
	}

	function updateTapLabel():Void {
		if (tapSamples.length > 0)
			tapLbl.text = Language.getPhrase('offset_taps', 'Taps: {1}   avg: {2} ms',
				[tapSamples.length, Math.round(avgTap())]);
		else
			tapLbl.text = '';
	}

	/** Records a free-form tap-vs-nearest-beat error and averages it into the active offset. **/
	function registerTap():Void {
		if (FlxG.sound.music == null)
			return;
		var interval:Float = pressInterval();
		if (interval <= 0)
			return;
		var pos:Float = FlxG.sound.music.time;
		var err:Float = pos - Math.round(pos / interval) * interval;
		tapSamples.push(err);
		barPercent = avgTap();
		writeOffset();
		slider.value = barPercent;
		updateTapLabel();
	}

	inline function avgTap():Float {
		var sum:Float = 0;
		for (s in tapSamples)
			sum += s;
		return sum / tapSamples.length;
	}

	function clearTaps():Void {
		if (tapSamples.length > 0) {
			tapSamples = [];
			updateTapLabel();
		}
	}

	function detectHardware():Void {
		if (hardwareMs == null) {
			flash(Language.getPhrase('offset_hw_unavailable',
				'Hardware latency unavailable'));
			return;
		}
		barPercent = hardwareMs;
		tapSamples = [];
		writeOffset();
		slider.value = barPercent;
		updateTapLabel();
		flash(Language.getPhrase('offset_hw_set', 'Hardware estimate: {1} ms',
			[hardwareMs]));
	}

	function flash(text:String):Void {
		statusLbl.text = text;
		statusTime = 2.2;
	}

	/** Begins the guided calibration run for the current tab (audio metronome, or visual note lane). **/
	function startCalibration():Void {
		calibActive = true;
		calibSamples = [];
		metroBeat = -1;

		barPercent = 0;
		writeOffset();
		slider.value = 0;
		clearTaps();

		setChromeVisible(false);
		camGame.visible = false;
		for (bar in frameBars)
			bar.visible = false;
		statusLbl.text = '';

		var isAudio:Bool = (tab == TAB_AUDIO);
		if (isAudio) {
			if (FlxG.sound.music != null)
				FlxG.sound.music.volume = 0;
			receptor.visible = false;
			for (n in notes)
				n.visible = false;
		} else {
			receptor.visible = true;
			seedNotes();
		}
		updateCalibPrompt();
	}

	function updateCalibration(elapsed:Float):Void {
		if (controls.BACK) {
			cancelCalibration();
			return;
		}

		if (tab == TAB_AUDIO)
			updateAudioCalibration();
		else
			updateVisualCalibration();
	}

	function updateAudioCalibration():Void {
		if (FlxG.sound.music == null)
			return;
		var interval:Float = pressInterval();
		if (interval <= 0)
			return;
		var pos:Float = FlxG.sound.music.time;

		var beat:Int = Math.floor(pos / interval);
		if (beat >= 0 && beat != metroBeat) {
			metroBeat = beat;
			var snd = FlxG.sound.play(Paths.sound('metronome/beep'), 0.6);
			#if FLX_PITCH
			if (snd != null && beat % 4 == 0)
				snd.pitch = 1.5;
			#end
		}

		if (calibTapped()) {
			var b:Int = Math.round(pos / interval);
			calibSamples.push(pos - b * interval);
			if (calibSamples.length >= CALIB_HITS)
				finishCalibration();
			else
				updateCalibPrompt();
		}
	}

	function updateVisualCalibration():Void {
		positionNotes();
		if (FlxG.sound.music == null)
			return;

		if (calibTapped()) {
			var pos:Float = FlxG.sound.music.time;
			var interval:Float = pressInterval();
			var b:Int = Math.round(pos / interval);
			calibSamples.push(pos - b * interval);
			receptor.playAnim('confirm', true);
			receptor.resetAnim = 0.14;
			var bi:Int = nearestNote(pos);
			noteTargets[bi] = maxTarget() + interval;
			notes[bi].visible = false;
			if (calibSamples.length >= CALIB_HITS)
				finishCalibration();
			else
				updateCalibPrompt();
		}
	}

	/** True when the user pressed any tap key this frame (anything except Esc/Enter) or the mobile A pad. **/
	function calibTapped():Bool {
		var k:Int = FlxG.keys.firstJustPressed();
		if (k == 27 || k == 13)
			return false;
		if (k != -1)
			return true;
		return touchPadJustPressed('A');
	}

	function updateCalibPrompt():Void {
		if (tab == TAB_AUDIO) {
			calibPrompt.text = Language.getPhrase('offset_calib_audio',
				'Listen and tap any key to the beep\n{1} / {2}    (Esc to cancel)',
				[calibSamples.length, CALIB_HITS]);
		} else {
			calibPrompt.text = Language.getPhrase('offset_calib_visual',
				'Press any key when the note lands on the receptor\n{1} / {2}    (Esc to cancel)',
				[calibSamples.length, CALIB_HITS]);
		}
	}

	function finishCalibration():Void {
		var avg:Float = 0;
		if (calibSamples.length > 0) {
			for (s in calibSamples)
				avg += s;
			avg /= calibSamples.length;
		}
		endCalibration();
		barPercent = avg;
		writeOffset();
		slider.value = barPercent;
		flash(Language.getPhrase('offset_calib_done', 'Calibrated: {1} ms',
			[Math.round(barPercent)]));
	}

	function cancelCalibration():Void {
		endCalibration();
		flash(Language.getPhrase('offset_calib_cancel', 'Calibration cancelled'));
	}

	/** Tears down a calibration run and restores the normal menu/ambiance for the active tab. **/
	function endCalibration():Void {
		calibActive = false;
		calibPrompt.visible = false;
		camGame.visible = true;
		for (bar in frameBars)
			bar.visible = true;
		if (FlxG.sound.music != null)
			FlxG.sound.music.volume = 1;
		setChromeVisible(true);
		applyTab(tab);
	}

	/** Shows/hides the interactive chrome (everything but the status flash + calibration prompt). **/
	function setChromeVisible(v:Bool):Void {
		tabsCtrl.visible = v;
		slider.visible = v;
		instrLbl.visible = v;
		tapLbl.visible = v;
		startBtn.visible = v;
		resetBtn.visible = v;
		backBtn.visible = v;
		detectBtn.visible = v && (tab == TAB_AUDIO);
		calibPrompt.visible = !v;
	}

	/** Seeds the falling-note targets to the next few beats from the current song time. **/
	function seedNotes():Void {
		var interval:Float = pressInterval();
		var pos:Float = (FlxG.sound.music != null) ? FlxG.sound.music.time : 0;
		var base:Float = Math.ceil(pos / interval);
		for (i in 0...notes.length)
			noteTargets[i] = (base + i) * interval;
	}

	/** Positions each falling marker (centered on the receptor) so it lands on its target beat. **/
	function positionNotes():Void {
		if (FlxG.sound.music == null)
			return;
		var interval:Float = pressInterval();
		var pos:Float = FlxG.sound.music.time;
		for (i in 0...notes.length) {
			if (pos > noteTargets[i] + 120)
				noteTargets[i] = maxTarget() + interval;
			var note:NoteSprite = notes[i];
			note.x = receptorCX - note.width / 2;
			note.y = receptorCY - note.height / 2 - (pos - noteTargets[i]) * PX_PER_MS;
			var ncy:Float = note.y + note.height / 2;
			note.visible = (ncy <= VP_Y + VP_H) && (ncy >= VP_Y - 40);
		}
	}

	/** The furthest-out target time among the note pool (used when recycling a note to a new beat). **/
	inline function maxTarget():Float {
		var m:Float = noteTargets[0];
		for (t in noteTargets)
			if (t > m)
				m = t;
		return m;
	}

	/** Index of the note whose target time is nearest `pos`. **/
	function nearestNote(pos:Float):Int {
		var bi:Int = 0;
		var bestAbs:Float = Math.abs(pos - noteTargets[0]);
		for (i in 1...notes.length) {
			var d:Float = Math.abs(pos - noteTargets[i]);
			if (d < bestAbs) {
				bestAbs = d;
				bi = i;
			}
		}
		return bi;
	}

	var zoomTween:FlxTween;
	var lastBeatHit:Int = -1;

	override public function beatHit() {
		super.beatHit();

		if (lastBeatHit == curBeat)
			return;

		if (!calibActive) {
			if (curBeat % 2 == 0) {
				boyfriend.dance();
				gf.dance();
			}

			if (tab == TAB_AUDIO && curBeat % 4 == 2) {
				camGame.zoom = 1.0;
				if (zoomTween != null)
					zoomTween.cancel();
				zoomTween = FlxTween.tween(camGame, {zoom: 0.85}, 1, {
					ease: FlxEase.circOut,
					onComplete: function(twn:FlxTween) {
						zoomTween = null;
					}
				});

				beatText.alpha = 1;
				beatText.y = 320;
				beatText.velocity.y = -150;
				if (beatTween != null)
					beatTween.cancel();
				beatTween = FlxTween.tween(beatText, {alpha: 0}, 1, {
					ease: FlxEase.sineIn,
					onComplete: function(twn:FlxTween) {
						beatTween = null;
					}
				});
			}
		}

		lastBeatHit = curBeat;
	}

	function exitState():Void {
		if (beatTween != null)
			beatTween.cancel();
		if (zoomTween != null)
			zoomTween.cancel();

		ClientPrefs.saveSettings();
		persistentUpdate = false;
		MusicBeatState.switchState(new options.OptionsState());
		if (OptionsState.onPlayState) {
			if (ClientPrefs.data.pauseMusic != 'None')
				FlxG.sound.playMusic(Paths.music(Paths.formatToSongPath(ClientPrefs.data.pauseMusic)));
			else if (FlxG.sound.music != null)
				FlxG.sound.music.volume = 0;
		} else
			FlxG.sound.playMusic(Paths.music('freakyMenu'));
	}

	override public function destroy():Void {
		FlxG.mouse.visible = false;
		FlxG.signals.gameResized.remove(onGameResized);
		FlxSmidr.dispose();
		#if mobile
		UITheme.clearMobilePreset();
		#end
		uiRoot = null;
		super.destroy();
	}
}
