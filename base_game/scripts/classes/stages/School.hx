package stages;

import stages.objects.SenpaiDialogueBox;
import stages.objects.BackgroundGirls;
import substates.GameOverSubstate;

/**
	Week 6, Senpai and Roses. Ported from the compiled `states.stages.School`.

	Callbacks handed to the dialogue box are wrapped in closures rather than passed as bare method
	references: a script's method is not a compiled `Void->Void`, so the closure keeps the boundary
	honest.
**/
class School extends BaseStage {
	var bgGirls:BackgroundGirls;
	var doof:SenpaiDialogueBox = null;

	override function create():Void {
		var song:Dynamic = PlayState.SONG;
		if (song.gameOverSound == null || song.gameOverSound.trim().length < 1) {
			GameOverSubstate.deathSoundName = 'fnf_loss_sfx-pixel';
		}
		if (song.gameOverLoop == null || song.gameOverLoop.trim().length < 1) {
			GameOverSubstate.loopSoundName = 'gameOver-pixel';
		}
		if (song.gameOverEnd == null || song.gameOverEnd.trim().length < 1) {
			GameOverSubstate.endSoundName = 'gameOverEnd-pixel';
		}
		if (song.gameOverChar == null || song.gameOverChar.trim().length < 1) {
			GameOverSubstate.characterName = 'bf-pixel-dead';
		}

		var bgSky:BGSprite = new BGSprite('weeb/weebSky', 0, 0, 0.1, 0.1);
		add(bgSky);
		bgSky.antialiasing = false;

		var repositionShit:Int = -200;

		var bgSchool:BGSprite = new BGSprite('weeb/weebSchool', repositionShit, 0, 0.6, 0.90);
		add(bgSchool);
		bgSchool.antialiasing = false;

		var bgStreet:BGSprite = new BGSprite('weeb/weebStreet', repositionShit, 0, 0.95, 0.95);
		add(bgStreet);
		bgStreet.antialiasing = false;

		var widShit:Int = Std.int(bgSky.width * PlayState.daPixelZoom);
		if (!ClientPrefs.data.lowQuality) {
			var fgTrees:BGSprite = new BGSprite('weeb/weebTreesBack', repositionShit + 170, 130, 0.9, 0.9);
			fgTrees.setGraphicSize(Std.int(widShit * 0.8));
			fgTrees.updateHitbox();
			add(fgTrees);
			fgTrees.antialiasing = false;
		}

		var bgTrees:FlxSprite = new FlxSprite(repositionShit - 380, -800);
		bgTrees.frames = Paths.getPackerAtlas('weeb/weebTrees');
		bgTrees.animation.add('treeLoop', [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18], 12);
		bgTrees.animation.play('treeLoop');
		bgTrees.scrollFactor.set(0.85, 0.85);
		add(bgTrees);
		bgTrees.antialiasing = false;

		if (!ClientPrefs.data.lowQuality) {
			var treeLeaves:BGSprite = new BGSprite('weeb/petals', repositionShit, -40, 0.85, 0.85, ['PETALS ALL'], true);
			treeLeaves.setGraphicSize(widShit);
			treeLeaves.updateHitbox();
			add(treeLeaves);
			treeLeaves.antialiasing = false;
		}

		bgSky.setGraphicSize(widShit);
		bgSchool.setGraphicSize(widShit);
		bgStreet.setGraphicSize(widShit);
		bgTrees.setGraphicSize(Std.int(widShit * 1.4));

		bgSky.updateHitbox();
		bgSchool.updateHitbox();
		bgStreet.updateHitbox();
		bgTrees.updateHitbox();

		if (!ClientPrefs.data.lowQuality) {
			bgGirls = new BackgroundGirls(-100, 190);
			bgGirls.scrollFactor.set(0.9, 0.9);
			add(bgGirls);
		}
		setDefaultGF('gf-pixel');

		if (songName == 'senpai') {
			FlxG.sound.playMusic(Paths.music('Lunchbox'), 0);
			FlxG.sound.music.fadeIn(1, 0, 0.8);
		} else if (songName == 'roses') {
			FlxG.sound.play(Paths.sound('ANGRY_TEXT_BOX'));
		}

		if (isStoryMode && !seenCutscene) {
			if (songName == 'roses') {
				FlxG.sound.play(Paths.sound('ANGRY'));
			}
			initDoof();
			setStartCallback(schoolIntro);
		}
	}

	override function beatHit():Void {
		if (bgGirls != null) {
			bgGirls.dance();
		}
	}

	// For events
	override function eventCalled(eventName:String, value1:String, value2:String, flValue1:Null<Float>, flValue2:Null<Float>, strumTime:Float):Void {
		if (eventName == 'BG Freaks Expression' && bgGirls != null) {
			bgGirls.swapDanceType();
		}
	}

	function initDoof():Void {
		// Checks for vanilla/Senpai dialogue
		var file:String = Paths.txt(songName + '/' + songName + 'Dialogue_' + ClientPrefs.data.language);
		if (!FileSystem.exists(file)) {
			file = Paths.txt(songName + '/' + songName + 'Dialogue');
		}

		if (!FileSystem.exists(file)) {
			startCountdown();
			return;
		}

		doof = new SenpaiDialogueBox(false, CoolUtil.coolTextFile(file));
		doof.cameras = [camHUD];
		doof.scrollFactor.set(0, 0);
		doof.finishThing = function():Void {
			startCountdown();
		};
		doof.nextDialogueThing = function():Void {
			PlayState.instance.startNextDialogue();
		};
		doof.skipDialogueThing = function():Void {
			PlayState.instance.skipDialogue();
		};
	}

	function schoolIntro():Void {
		inCutscene = true;
		var black:FlxSprite = new FlxSprite(-100, -100);
		black.makeGraphic(FlxG.width * 2, FlxG.height * 2, FlxColor.BLACK);
		black.scrollFactor.set(0, 0);
		if (songName == 'senpai') {
			add(black);
		}

		new FlxTimer().start(0.3, function(tmr:FlxTimer):Void {
			black.alpha -= 0.15;

			if (black.alpha <= 0) {
				if (doof != null) {
					add(doof);
				} else {
					startCountdown();
				}

				remove(black);
				black.destroy();
			} else {
				tmr.reset(0.3);
			}
		});
	}
}
