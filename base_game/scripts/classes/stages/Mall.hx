package stages;

import backend.BaseStage;
import backend.ClientPrefs;
import backend.Paths;
import flixel.FlxG;
import flixel.FlxSprite;
import flixel.util.FlxColor;
import flixel.util.FlxTimer;
import objects.BGSprite;
import states.PlayState;
import stages.objects.MallCrowd;

/** Week 5, Cocoa and Eggnog. Ported from the compiled `states.stages.Mall`. **/
class Mall extends BaseStage {
	var upperBoppers:BGSprite;
	var bottomBoppers:MallCrowd;
	var santa:BGSprite;

	override function create():Void {
		var bg:BGSprite = new BGSprite('christmas/bgWalls', -1000, -500, 0.2, 0.2);
		bg.setGraphicSize(Std.int(bg.width * 0.8));
		bg.updateHitbox();
		add(bg);

		if (!ClientPrefs.data.lowQuality) {
			upperBoppers = new BGSprite('christmas/upperBop', -240, -90, 0.33, 0.33, ['Upper Crowd Bob']);
			upperBoppers.setGraphicSize(Std.int(upperBoppers.width * 0.85));
			upperBoppers.updateHitbox();
			add(upperBoppers);

			var bgEscalator:BGSprite = new BGSprite('christmas/bgEscalator', -1100, -600, 0.3, 0.3);
			bgEscalator.setGraphicSize(Std.int(bgEscalator.width * 0.9));
			bgEscalator.updateHitbox();
			add(bgEscalator);
		}

		var tree:BGSprite = new BGSprite('christmas/christmasTree', 370, -250, 0.40, 0.40);
		add(tree);

		bottomBoppers = new MallCrowd(-300, 140);
		add(bottomBoppers);

		var fgSnow:BGSprite = new BGSprite('christmas/fgSnow', -600, 700);
		add(fgSnow);

		Paths.sound('Lights_Shut_off');
		setDefaultGF('gf-christmas');

		if (isStoryMode && !seenCutscene) {
			setEndCallback(eggnogEndCutscene);
		}
	}

	override function createPost():Void {
		// Added after the characters exist so it renders in front of dad (who sits behind santa)
		// while staying behind bf.
		santa = new BGSprite('christmas/santa', -840, 150, 1, 1, ['santa idle in fear']);
		addBehindBF(santa);
	}

	override function countdownTick(count:Countdown, num:Int):Void {
		everyoneDance();
	}

	override function beatHit():Void {
		everyoneDance();
	}

	override function eventCalled(eventName:String, value1:String, value2:String, flValue1:Null<Float>, flValue2:Null<Float>, strumTime:Float):Void {
		if (eventName != 'Hey!') {
			return;
		}

		var who:String = value1.toLowerCase().trim();
		if (who == 'bf' || who == 'boyfriend' || who == '0') {
			return;
		}

		bottomBoppers.animation.play('hey', true);
		bottomBoppers.heyTimer = flValue2;
	}

	function everyoneDance():Void {
		if (!ClientPrefs.data.lowQuality) {
			upperBoppers.dance(true);
		}

		bottomBoppers.dance(true);
		santa.dance(true);
	}

	function eggnogEndCutscene():Void {
		if (PlayState.storyPlaylist[1] == null) {
			endSong();
			return;
		}

		var nextSong:String = Paths.formatToSongPath(PlayState.storyPlaylist[1]);
		if (nextSong != 'winter-horrorland') {
			endSong();
			return;
		}

		FlxG.sound.play(Paths.sound('Lights_Shut_off'));

		var blackShit:FlxSprite = new FlxSprite(-FlxG.width * FlxG.camera.zoom, -FlxG.height * FlxG.camera.zoom);
		blackShit.makeGraphic(FlxG.width * 3, FlxG.height * 3, FlxColor.BLACK);
		blackShit.scrollFactor.set(0, 0);
		add(blackShit);
		camHUD.visible = false;

		inCutscene = true;
		canPause = false;

		new FlxTimer().start(1.5, function(tmr:FlxTimer):Void {
			endSong();
		});
	}
}
