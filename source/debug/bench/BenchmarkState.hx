package debug.bench;

import flixel.text.FlxText;
import flixel.util.FlxColor;
import flixel.group.FlxGroup.FlxTypedGroup;

class BenchmarkState extends MusicBeatState {
	var options:Array<String> = BenchSuites.SUITE_NAMES;
	var grpTexts:FlxTypedGroup<Alphabet>;
	var curSelected:Int = 0;
	var summaryTxt:FlxText;

	override function create() {
		FlxG.camera.bgColor = FlxColor.BLACK;

		var bg:FlxSprite = new FlxSprite().loadGraphic(Paths.image('menuDesat'));
		CoolUtil.fillScreen(bg);
		bg.scrollFactor.set();
		bg.color = 0xFF303030;
		add(bg);

		grpTexts = new FlxTypedGroup<Alphabet>();
		add(grpTexts);

		for (i in 0...options.length) {
			var leText:Alphabet = new Alphabet(90, 100 + i * 92, options[i], true);
			leText.scaleX = 0.75;
			leText.scaleY = 0.75;
			grpTexts.add(leText);
		}

		var textBG:FlxSprite = new FlxSprite(0, FlxG.height - 42).makeGraphic(FlxG.width, 42, 0xFF000000);
		textBG.alpha = 0.6;
		add(textBG);

		var titleTxt:FlxText = new FlxText(textBG.x, textBG.y + 4, FlxG.width, 'BENCHMARK -- ACCEPT TO RUN, F8 ABORTS A RUN', 32);
		titleTxt.setFormat(Paths.font("vcr.ttf"), 24, FlxColor.WHITE, CENTER);
		titleTxt.scrollFactor.set();
		titleTxt.y += 6;
		add(titleTxt);

		summaryTxt = new FlxText(20, 470, FlxG.width - 40, '', 12);
		summaryTxt.setFormat(Paths.font("vcr.ttf"), 12, FlxColor.WHITE, LEFT, OUTLINE, FlxColor.BLACK);
		summaryTxt.borderSize = 1;
		summaryTxt.scrollFactor.set();
		add(summaryTxt);

		if (BenchmarkRunner.lastSummary.length > 0) {
			summaryTxt.text = BenchmarkRunner.lastSummary
				+ (BenchmarkRunner.lastLogPath.length > 0 ? '\nSaved to: ' + BenchmarkRunner.lastLogPath : '');
		} else {
			summaryTxt.text = 'No results yet. Results are logged to <game folder>/benchmarks/ as .txt and .json.\n'
				+ 'Suites run botplay gameplay scenarios from a near-empty baseline up to dense charts,\n'
				+ 'event floods and heavy Lua/HScript workloads. FPS is uncapped while a suite runs.';
		}

		if (FlxG.sound.music == null || !FlxG.sound.music.playing)
			FlxG.sound.playMusic(Paths.music('freakyMenu'), 0.8);

		changeSelection();
		FlxG.mouse.visible = false;
		super.create();
	}

	override function update(elapsed:Float) {
		if (controls.UI_UP_P)
			changeSelection(-1);
		if (controls.UI_DOWN_P)
			changeSelection(1);

		if (controls.BACK)
			MusicBeatState.switchState(new editors.MasterEditorMenu());

		if (controls.ACCEPT) {
			final name:String = options[curSelected];
			FlxG.sound.music.volume = 0;
			BenchmarkRunner.start(name, BenchSuites.byName(name));
		}

		super.update(elapsed);
	}

	function changeSelection(change:Int = 0) {
		FlxG.sound.play(Paths.sound('scrollMenu'), 0.4);
		curSelected = FlxMath.wrap(curSelected + change, 0, options.length - 1);
		for (num => item in grpTexts.members)
			item.alpha = (num == curSelected) ? 1 : 0.6;
	}
}
