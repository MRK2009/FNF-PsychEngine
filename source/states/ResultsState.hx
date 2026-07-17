package states;

import openfl.display.BitmapData;
import smidr.UIRoot;
import smidr.UIFonts;
import smidr.UITheme;
import smidr.UILocale;
import smidr.widgets.UIPanel;
import smidr.widgets.UILabel;
import smidr.widgets.UIButton;
import smidr.flixel.FlxSmidr;
import backend.profiles.ScoreRecord;
import backend.profiles.ProfileManager;
import backend.replay.ReplayData;
import backend.scoring.SessionStats;
import backend.Song;
import backend.WeekData;

/**
 * The osu!-style results screen, shown after finishing a song outside story mode and reopenable
 * from any stored highscore in Freeplay.
 *
 * Two modes share the layout: **live** (`fromPlay = true`, carries the run's `SessionStats` for
 * the hit-offset graph and offers Retry) and **view** (a stored `ScoreRecord` only). The left
 * Smidr panel lists score / accuracy / per-judgement counts with the scoring system's own names /
 * combo / Wife3-at-J4 / SSR; the right side is the big grade letter. Watch Replay appears once the
 * record carries a replay file.
 */
class ResultsState extends MusicBeatState {
	var record:ScoreRecord;
	var stats:SessionStats;
	var fromPlay:Bool;

	var uiRoot:UIRoot;
	var panel:UIPanel;
	var labels:Array<UILabel> = [];
	var gradeTxt:FlxText;
	var graph:FlxSprite;

	/**
	 * @param record the play to present
	 * @param stats the live session stats for the hit graph, null in view mode
	 * @param fromPlay true right after gameplay (enables Retry and keeps the song's mod context)
	 */
	public function new(record:ScoreRecord, ?stats:SessionStats, fromPlay:Bool = false) {
		super();
		this.record = record;
		this.stats = stats;
		this.fromPlay = fromPlay;
	}

	override function create():Void {
		persistentUpdate = false;

		if (FlxG.sound.music == null || !FlxG.sound.music.playing)
			FlxG.sound.playMusic(Paths.music('freakyMenu'));

		var bg:FlxSprite = new FlxSprite().loadGraphic(Paths.image('menuDesat'));
		bg.color = 0xFF223344;
		CoolUtil.fillScreen(bg);
		add(bg);

		gradeTxt = new FlxText(0, 0, 520, record.grade, 96);
		gradeTxt.setFormat(Paths.font('vcr.ttf'), gradeSize(record.grade), gradeColor(), CENTER, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		gradeTxt.borderSize = 3;
		gradeTxt.x = FlxG.width - 560;
		gradeTxt.y = 130;
		add(gradeTxt);

		var fcTxt:FlxText = new FlxText(gradeTxt.x, gradeTxt.y + 170, 520, record.fc, 28);
		fcTxt.setFormat(Paths.font('vcr.ttf'), 28, FlxColor.WHITE, CENTER, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		add(fcTxt);

		if (stats != null && stats.hitCount > 0) {
			graph = buildGraph(520, 150);
			graph.x = FlxG.width - 560;
			graph.y = 380;
			add(graph);
		}

		setupSmidr();
		super.create();

		#if mobile
		addTouchPad('NONE', 'B');
		#end
	}

	/** Builds the Smidr chrome: the stats panel and the action buttons. */
	function setupSmidr():Void {
		UILocale.translate = function(k:String, f:String):String return Language.getPhrase(k, f);
		UIFonts.register('assets/fonts/vcr.ttf');
		#if mobile
		UITheme.applyMobilePreset();
		#end
		uiRoot = FlxSmidr.init();
		FlxSmidr.autoBlockMouse = true;
		FlxG.mouse.visible = true;
		FlxG.mouse.useSystemCursor = true;

		var px:Float = 40;
		var py:Float = 60;
		var pw:Float = Math.min(520, FlxG.width * 0.44);

		panel = new UIPanel(pw, 540);
		panel.alpha = 0.5;
		panel.x = px;
		panel.y = py;
		uiRoot.content.addChild(panel);

		var cy:Float = py + 18;
		cy = line('${record.songName}  [${record.diffName}]', 24, 0, px, cy, pw) + 6;
		var sub:String = record.systemId != null ? systemLabel() : '';
		if (record.playbackRate != 1)
			sub += '    ${record.playbackRate}x';
		if (record.keyCount != 4)
			sub += '    ${record.keyCount}K';
		cy = line(sub, 13, 1, px, cy, pw) + 14;

		cy = line('SCORE', 11, 2, px, cy, pw) + 2;
		cy = line(commas(record.score), 34, 0, px, cy, pw) + 10;
		cy = line('ACCURACY   ' + fmt2(record.accuracy * 100) + '%', 16, 0, px, cy, pw) + 14;

		cy = line('JUDGEMENTS', 11, 2, px, cy, pw) + 4;
		var names:Array<String> = record.judgementNames;
		for (i in 0...names.length) {
			var n:Int = (record.counts != null && i < record.counts.length) ? record.counts[i] : 0;
			cy = line(rpad(names[i], 12) + Std.string(n), 15, 1, px, cy, pw) + 2;
		}
		cy = line(rpad('Misses', 12) + Std.string(record.misses), 15, 1, px, cy, pw) + 12;

		cy = line('Max Combo   ${record.maxCombo}x        Notes   ${record.totalNotes}', 14, 1, px, cy, pw) + 6;
		cy = line('Wife3 (J4)   ' + fmt2(record.wifePercent * 100) + '%', 14, 1, px, cy, pw) + 6;
		if (record.ssr != null && record.ssr.length >= 8)
			cy = line('SSR   ' + fmt2(record.ssr[0]), 14, 1, px, cy, pw) + 6;
		cy = line(dateStr(record.dateSec), 12, 2, px, cy, pw) + 6;

		var by:Float = py + 540 + 16;
		var bx:Float = px;
		if (fromPlay) {
			addButton('Retry', bx, by, 150, retry);
			bx += 162;
		}
		if (record.replayFile != null) {
			addButton('Watch Replay', bx, by, 180, watchReplay);
			bx += 192;
		}
		addButton(fromPlay ? 'Continue' : 'Back', bx, by, 150, leave, true);
	}

	/** Loads the record's replay file and boots PlayState in replay playback. */
	function watchReplay():Void {
		var pid:Int = backend.profiles.ProfileManager.active().id;
		var data:backend.replay.ReplayData = backend.replay.ReplayData.load(backend.profiles.ProfileManager.replaysDir(pid) + '/' + record.replayFile);
		if (data == null)
			return;
		FlxG.mouse.visible = false;
		PlayState.startReplay = data;
		PlayState.isStoryMode = false;
		PlayState.storyDifficulty = record.diff;
		Mods.currentModDirectory = record.folder;
		Song.loadFromJson(chartFileFromKey(record.songKey), Paths.formatToSongPath(record.songName));
		LoadingState.prepareToSong();
		LoadingState.loadAndSwitchState(new PlayState());
	}

	/**
	 * Strips the keycount suffix off a score-DB songKey, leaving the chart file name.
	 * @param key the songKey ('song-name-suffix_4k')
	 * @return the chart json name the song loader expects
	 */
	static function chartFileFromKey(key:String):String {
		var r:EReg = ~/_\d+k$/;
		return r.match(key) ? r.matchedLeft() : key;
	}

	/**
	 * Adds one stat line to the panel.
	 * @param text the line text
	 * @param size the font size
	 * @param tone the theme tone
	 * @param px the panel's left edge
	 * @param cy the line's top
	 * @param pw the panel width
	 * @return the y below the measured line
	 */
	function line(text:String, size:Int, tone:Int, px:Float, cy:Float, pw:Float):Float {
		var l:UILabel = new UILabel(text, size, tone);
		l.wrapWidth = pw - 36;
		var h:Float = l.measure();
		l.x = px + 18;
		l.y = cy;
		uiRoot.content.addChild(l);
		labels.push(l);
		return cy + h;
	}

	/**
	 * Adds an action button.
	 * @param label the caption
	 * @param x the left edge
	 * @param y the top edge
	 * @param w the width
	 * @param onClick the click action, null renders it disabled
	 * @param accent whether the button uses the accent style
	 */
	function addButton(label:String, x:Float, y:Float, w:Float, onClick:Null<Void->Void>, accent:Bool = false):Void {
		var b:UIButton = new UIButton(label, w, 38, onClick != null ? onClick : function():Void {}, accent);
		b.x = x;
		b.y = y;
		if (onClick == null)
			b.alpha = 0.4;
		uiRoot.content.addChild(b);
	}

	/**
	 * Renders the run's signed hit offsets over song time onto a scatter bitmap.
	 * @param w the graph width
	 * @param h the graph height
	 * @return the finished sprite
	 */
	function buildGraph(w:Int, h:Int):FlxSprite {
		var bmp:BitmapData = new BitmapData(w, h, true, 0x88000000);
		var mid:Int = h >> 1;
		for (x in 0...w)
			bmp.setPixel32(x, mid, 0xFFFFFFFF);

		var lastTime:Float = stats.times[stats.hitCount - 1];
		if (lastTime <= 0)
			lastTime = 1;
		var range:Float = 180.0;
		for (i in 0...stats.hitCount) {
			var x:Int = Std.int((stats.times[i] / lastTime) * (w - 3)) + 1;
			var off:Float = stats.offsets[i];
			if (off < -range)
				off = -range;
			else if (off > range)
				off = range;
			var y:Int = mid + Std.int(off / range * (mid - 2));
			var abs:Float = off < 0 ? -off : off;
			var color:Int = abs <= 45 ? 0xFF6FE3FF : (abs <= 90 ? 0xFF9EE86F : (abs <= 135 ? 0xFFF2C94C : 0xFFEB5757));
			bmp.setPixel32(x, y, color);
			bmp.setPixel32(x, y + 1, color);
		}

		var spr:FlxSprite = new FlxSprite();
		spr.pixels = bmp;
		return spr;
	}

	/** Re-enters the same loaded song for another run. */
	function retry():Void {
		FlxG.mouse.visible = false;
		LoadingState.prepareToSong();
		LoadingState.loadAndSwitchState(new PlayState());
	}

	/** Leaves to Freeplay, restoring the top mod context. */
	function leave():Void {
		Mods.loadTopMod();
		WeekData.setDirectoryFromWeek();
		MusicBeatState.switchState(new FreeplayState());
	}

	override function update(elapsed:Float):Void {
		if (controls.BACK)
			leave();
		super.update(elapsed);
	}

	override function destroy():Void {
		FlxG.mouse.useSystemCursor = false;
		FlxG.mouse.visible = false;
		if (uiRoot != null) {
			uiRoot = null;
			FlxSmidr.dispose();
		}
		super.destroy();
	}

	/** @return the display label of the record's scoring system */
	function systemLabel():String {
		var i:Int = backend.scoring.ScoreSystems.IDS.indexOf(record.systemId);
		return i >= 0 ? backend.scoring.ScoreSystems.LABELS[i] : record.systemId;
	}

	/** @return the grade letter's display color, keyed off the record's accuracy */
	function gradeColor():FlxColor {
		if (record.accuracy >= 0.995)
			return 0xFFFFD75E;
		if (record.accuracy >= 0.93)
			return 0xFF6FE3FF;
		if (record.accuracy >= 0.8)
			return 0xFF9EE86F;
		if (record.accuracy >= 0.6)
			return 0xFFF2C94C;
		return 0xFFEB5757;
	}

	/**
	 * @param grade the grade string
	 * @return a font size that keeps long grade names inside the column
	 */
	static function gradeSize(grade:String):Int {
		if (grade == null)
			return 96;
		return grade.length <= 3 ? 120 : (grade.length <= 6 ? 72 : 48);
	}

	/**
	 * Formats an integer with thousands separators.
	 * @param v the value
	 * @return the comma-grouped string
	 */
	static function commas(v:Int):String {
		var s:String = Std.string(v);
		var out:String = '';
		var c:Int = 0;
		var i:Int = s.length - 1;
		while (i >= 0) {
			out = s.charAt(i) + out;
			if (++c % 3 == 0 && i > 0)
				out = ',' + out;
			i--;
		}
		return out;
	}

	/**
	 * Formats a number with exactly two decimals.
	 * @param v the value
	 * @return the formatted string
	 */
	static function fmt2(v:Float):String {
		var r:Float = Math.round(v * 100) / 100;
		var s:String = Std.string(r);
		var dot:Int = s.indexOf('.');
		if (dot < 0)
			return s + '.00';
		while (s.length - s.indexOf('.') - 1 < 2)
			s += '0';
		return s;
	}

	/**
	 * Right-pads a string with spaces for aligned columns.
	 * @param s the string
	 * @param n the minimum length
	 * @return the padded string
	 */
	static function rpad(s:String, n:Int):String {
		while (s.length < n)
			s += ' ';
		return s;
	}

	/**
	 * @param sec a unix timestamp in seconds
	 * @return a compact local date-time string
	 */
	static function dateStr(sec:Float):String {
		var d:Date = Date.fromTime(sec * 1000);
		return DateTools.format(d, '%Y-%m-%d %H:%M');
	}
}
