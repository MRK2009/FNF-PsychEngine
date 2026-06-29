package options;

import objects.Character;
import objects.Bar;
import states.stages.StageWeek1 as BackgroundStage;

/**
 * Note/Beat delay calibration menu. Positioning of the rating popups / combo / numbers used to live here
 * (drag the combo sprites), but that is now owned entirely by the UI Skin and its editor
 * (`editors.UISkinEditorState`), so this screen only tunes the audio `noteOffset` delay.
 */
class NoteOffsetState extends MusicBeatState {
	var stageDirectory:String = 'week1';
	var boyfriend:Character;
	var gf:Character;

	public var camHUD:FlxCamera;
	public var camGame:FlxCamera;
	public var camOther:FlxCamera;

	var barPercent:Float = 0;
	var delayMin:Int = -500;
	var delayMax:Int = 500;
	var timeBar:Bar;
	var timeTxt:FlxText;
	var beatText:Alphabet;
	var beatTween:FlxTween;

	var titleText:FlxText;

	override public function create() {
		#if DISCORD_ALLOWED
		DiscordClient.changePresence("Note Delay Menu", null);
		#end

		// Cameras
		camGame = initPsychCamera();

		camHUD = new FlxCamera();
		camHUD.bgColor.alpha = 0;
		FlxG.cameras.add(camHUD, false);

		camOther = new FlxCamera();
		camOther.bgColor.alpha = 0;
		FlxG.cameras.add(camOther, false);

		FlxG.camera.scroll.set(120, 130);

		persistentUpdate = true;
		FlxG.sound.pause();

		// Stage
		Paths.setCurrentLevel(stageDirectory);
		new BackgroundStage();

		// Characters
		gf = new Character(400, 130, 'gf');
		gf.x += gf.positionArray[0];
		gf.y += gf.positionArray[1];
		gf.scrollFactor.set(0.95, 0.95);
		boyfriend = new Character(770, 100, 'bf', true);
		boyfriend.x += boyfriend.positionArray[0];
		boyfriend.y += boyfriend.positionArray[1];
		add(gf);
		add(boyfriend);

		// Note delay stuff
		beatText = new Alphabet(0, 0, Language.getPhrase('delay_beat_hit', 'Beat Hit!'), true);
		beatText.setScale(0.6, 0.6);
		beatText.x += 260;
		beatText.alpha = 0;
		beatText.acceleration.y = 250;
		add(beatText);

		timeTxt = new FlxText(0, 600, FlxG.width, "", 32);
		timeTxt.setFormat(Paths.font("vcr.ttf"), 32, FlxColor.WHITE, CENTER, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		timeTxt.scrollFactor.set();
		timeTxt.borderSize = 2;
		timeTxt.cameras = [camHUD];

		barPercent = ClientPrefs.data.noteOffset;
		updateNoteDelay();

		timeBar = new Bar(0, timeTxt.y + (timeTxt.height / 3), 'healthBar', function() return barPercent, delayMin, delayMax);
		timeBar.scrollFactor.set();
		timeBar.screenCenter(X);
		timeBar.cameras = [camHUD];
		timeBar.leftBar.color = FlxColor.LIME;

		add(timeBar);
		add(timeTxt);

		///////////////////////

		var blackBox:FlxSprite = new FlxSprite().makeGraphic(FlxG.width, 40, FlxColor.BLACK);
		blackBox.scrollFactor.set();
		blackBox.alpha = 0.6;
		blackBox.cameras = [camHUD];
		add(blackBox);

		titleText = new FlxText(0, 4, FlxG.width, "", 32);
		titleText.setFormat(Paths.font("vcr.ttf"), 32, FlxColor.WHITE, CENTER);
		titleText.scrollFactor.set();
		titleText.cameras = [camHUD];
		titleText.text = '< ${Language.getPhrase('note_delay', 'Note/Beat Delay').toUpperCase()} >';
		add(titleText);

		FlxG.mouse.visible = false;

		Conductor.bpm = 128.0;
		FlxG.sound.playMusic(Paths.music('offsetSong'), 1, true);

		super.create();

		#if mobile
		// LEFT/RIGHT adjust, A confirm, B back, C reset (controls.RESET).
		addTouchPad('LEFT_RIGHT', 'A_B_C');
		#end
	}

	var holdTime:Float = 0;

	override public function update(elapsed:Float) {
		var addNum:Int = 3;
		if (FlxG.keys.pressed.SHIFT || FlxG.gamepads.anyPressed(LEFT_SHOULDER))
			addNum = 10;

		if (controls.UI_LEFT_P) {
			barPercent = Math.max(delayMin, Math.min(ClientPrefs.data.noteOffset - 1, delayMax));
			updateNoteDelay();
		} else if (controls.UI_RIGHT_P) {
			barPercent = Math.max(delayMin, Math.min(ClientPrefs.data.noteOffset + 1, delayMax));
			updateNoteDelay();
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
			barPercent = Math.max(delayMin, Math.min(barPercent, delayMax));
			updateNoteDelay();
		}

		if (controls.RESET) {
			holdTime = 0;
			barPercent = 0;
			updateNoteDelay();
		}

		if (controls.BACK) {
			if (beatTween != null)
				beatTween.cancel();

			persistentUpdate = false;
			MusicBeatState.switchState(new options.OptionsState());
			if (OptionsState.onPlayState) {
				if (ClientPrefs.data.pauseMusic != 'None')
					FlxG.sound.playMusic(Paths.music(Paths.formatToSongPath(ClientPrefs.data.pauseMusic)));
				else if (FlxG.sound.music != null)
					FlxG.sound.music.volume = 0;
			} else
				FlxG.sound.playMusic(Paths.music('freakyMenu'));
			FlxG.mouse.visible = false;
		}

		if (FlxG.sound.music != null)
			Conductor.songPosition = FlxG.sound.music.time;
		super.update(elapsed);
	}

	var zoomTween:FlxTween;
	var lastBeatHit:Int = -1;

	override public function beatHit() {
		super.beatHit();

		if (lastBeatHit == curBeat)
			return;

		if (curBeat % 2 == 0) {
			boyfriend.dance();
			gf.dance();
		}

		if (curBeat % 4 == 2) {
			FlxG.camera.zoom = 1.15;

			if (zoomTween != null)
				zoomTween.cancel();
			zoomTween = FlxTween.tween(FlxG.camera, {zoom: 1}, 1, {
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

		lastBeatHit = curBeat;
	}

	function updateNoteDelay() {
		ClientPrefs.data.noteOffset = Math.round(barPercent);
		timeTxt.text = Language.getPhrase('delay_current_offset', 'Current offset: {1} ms', [Math.floor(barPercent)]);
	}
}
