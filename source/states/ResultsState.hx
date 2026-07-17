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
 * Two modes share the layout: **live** (`fromPlay = true`, carries the run's `SessionStats` and
 * offers Retry) and **view** (a stored `ScoreRecord` only). The left Smidr panel names the scoring
 * system up front, then lists score / accuracy / per-judgement counts with the system's own names /
 * combo / Wife3-at-J4 / unstable rate / SSR; the right side is the big grade letter plus an osu!-style
 * hit-offset scatter and a rolling unstable-rate line. The graphs draw from the live session or, when
 * a stored score is reopened, from its downsampled offset spread. Watch Replay appears once the record
 * carries a replay file.
 */
class ResultsState extends MusicBeatState {
	var record:ScoreRecord;
	var stats:SessionStats;
	var fromPlay:Bool;

	var uiRoot:UIRoot;
	var panel:UIPanel;
	var labels:Array<UILabel> = [];
	var bg:FlxSprite;
	var gradeTxt:FlxText;
	var fcTxt:FlxText;
	var graph:FlxSprite;
	var urGraph:FlxSprite;
	// The right-hand column (grade, FC, graphs, their captions) is anchored to FlxG.width, so it must
	// re-x on a window resize (SmidrUI is OpenFL-based and the widescreen mode changes FlxG.width).
	var graphLabels:Array<FlxText> = [];

	// Judged-tap offset samples, from the live session or a stored score's downsampled spread.
	var sampleTimes:Array<Float> = null;
	var sampleOffsets:Array<Float> = null;
	var unstable:Float = 0;

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

		bg = new FlxSprite().loadGraphic(Paths.image('menuDesat'));
		bg.color = 0xFF223344;
		CoolUtil.fillScreen(bg);
		add(bg);

		gradeTxt = new FlxText(0, 0, 520, record.grade, 96);
		gradeTxt.setFormat(Paths.font('vcr.ttf'), gradeSize(record.grade), gradeColor(), CENTER, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		gradeTxt.borderSize = 3;
		gradeTxt.x = FlxG.width - 560;
		gradeTxt.y = 130;
		add(gradeTxt);

		fcTxt = new FlxText(gradeTxt.x, gradeTxt.y + 170, 520, record.fc, 28);
		fcTxt.setFormat(Paths.font('vcr.ttf'), 28, FlxColor.WHITE, CENTER, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		add(fcTxt);

		resolveSamples();
		if (sampleTimes != null && sampleTimes.length > 0) {
			var gx:Float = FlxG.width - 560;
			addGraphLabel('HIT OFFSET (ms)', gx, 352);
			graph = buildOffsetGraph(520, 116);
			graph.x = gx;
			graph.y = 372;
			add(graph);

			addGraphLabel('UNSTABLE RATE  ' + fmt2(unstable), gx, 500);
			urGraph = buildURGraph(520, 92);
			urGraph.x = gx;
			urGraph.y = 520;
			add(urGraph);
		}

		setupSmidr();
		FlxG.signals.gameResized.add(onGameResized);
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
		// Name the scoring system that judged the play up front, so it's never ambiguous which ruleset
		// the score/grade came from (they aren't comparable across systems).
		cy = line('SCORING SYSTEM   ' + (record.systemId != null ? systemLabel() : 'Psych'), 13, 2, px, cy, pw) + 2;
		var meta:String = '';
		if (record.playbackRate != 1)
			meta += '${record.playbackRate}x';
		if (record.keyCount != 4)
			meta += (meta.length > 0 ? '    ' : '') + '${record.keyCount}K';
		if (meta.length > 0)
			cy = line(meta, 13, 1, px, cy, pw) + 2;
		cy += 12;

		cy = line('SCORE', 11, 2, px, cy, pw) + 2;
		cy = line(commas(record.score), 34, 0, px, cy, pw) + 10;
		cy = line('ACCURACY   ' + fmt2(record.accuracy * 100) + '%', 16, 0, px, cy, pw) + 14;

		cy = line('JUDGEMENTS', 11, 2, px, cy, pw) + 4;
		var names:Array<String> = record.judgementNames;
		for (i in 0...names.length) {
			var n:Int = (record.counts != null && i < record.counts.length) ? record.counts[i] : 0;
			cy = line(rpad(names[i], 12) + Std.string(n), 15, 1, px, cy, pw) + 2;
		}
		cy = line(rpad('Misses', 12) + Std.string(record.misses), 15, 1, px, cy, pw) + 2;
		if (record.holdDrops != null && record.holdDrops > 0)
			cy = line(rpad('Hold Drops', 12) + Std.string(record.holdDrops), 15, 1, px, cy, pw) + 2;
		if (record.ghostTaps != null && record.ghostTaps > 0)
			cy = line(rpad('Ghost Taps', 12) + Std.string(record.ghostTaps), 15, 1, px, cy, pw) + 2;
		cy += 10;

		cy = line('Max Combo   ${record.maxCombo}x        Notes   ${record.totalNotes}', 14, 1, px, cy, pw) + 6;
		cy = line('Wife3 (J4)   ' + fmt2(record.wifePercent * 100) + '%', 14, 1, px, cy, pw) + 6;
		var ur:Float = (record.unstableRate != null && record.unstableRate > 0) ? record.unstableRate : unstable;
		if (ur > 0)
			cy = line('Unstable Rate   ' + fmt2(ur), 14, 1, px, cy, pw) + 6;
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
	 * Resolves the judged-tap offset samples used by both graphs: the live session's full log when
	 * present, otherwise the stored score's downsampled spread. Also computes the run's unstable rate
	 * from those samples (falling back on the record's stored value).
	 */
	function resolveSamples():Void {
		if (stats != null && stats.hitCount > 0) {
			sampleTimes = [];
			sampleOffsets = [];
			for (i in 0...stats.hitCount) {
				sampleTimes.push(stats.times[i]);
				sampleOffsets.push(stats.offsets[i]);
			}
		} else if (record.spreadTimes != null && record.spreadOffsets != null && record.spreadTimes.length > 0) {
			sampleTimes = record.spreadTimes;
			sampleOffsets = record.spreadOffsets;
		} else
			return;
		unstable = computeUR(sampleOffsets);
		if (unstable <= 0 && record.unstableRate != null)
			unstable = record.unstableRate;
	}

	/**
	 * The unstable rate (10x the offset std-dev in ms) of a sample set.
	 * @param offsets the signed offsets
	 * @return the unstable rate, 0 with fewer than two samples
	 */
	static function computeUR(offsets:Array<Float>):Float {
		var n:Int = offsets.length;
		if (n < 2)
			return 0;
		var mean:Float = 0;
		for (o in offsets)
			mean += o;
		mean /= n;
		var v:Float = 0;
		for (o in offsets) {
			var d:Float = o - mean;
			v += d * d;
		}
		return Math.sqrt(v / n) * 10;
	}

	/**
	 * Adds a small caption above a graph.
	 * @param text the caption
	 * @param x the caption's left edge
	 * @param y the caption's top
	 */
	function addGraphLabel(text:String, x:Float, y:Float):Void {
		var t:FlxText = new FlxText(x, y, 520, text, 14);
		t.setFormat(Paths.font('vcr.ttf'), 14, 0xFFB8C0D0, LEFT);
		add(t);
		graphLabels.push(t);
	}

	/** Re-x's the FlxG.width-anchored right column (grade, FC, graphs, captions) after a window resize. */
	function onGameResized(w:Int, h:Int):Void {
		if (bg != null)
			CoolUtil.fillScreen(bg);
		var gx:Float = FlxG.width - 560;
		if (gradeTxt != null)
			gradeTxt.x = gx;
		if (fcTxt != null)
			fcTxt.x = gx;
		if (graph != null)
			graph.x = gx;
		if (urGraph != null)
			urGraph.x = gx;
		for (l in graphLabels)
			l.x = gx;
	}

	/**
	 * Renders the run's signed hit offsets over song time onto a scatter bitmap (osu!-style),
	 * coloured by how close each tap was to perfect.
	 * @param w the graph width
	 * @param h the graph height
	 * @return the finished sprite
	 */
	function buildOffsetGraph(w:Int, h:Int):FlxSprite {
		var bmp:BitmapData = new BitmapData(w, h, true, 0x88000000);
		var mid:Int = h >> 1;
		for (x in 0...w)
			bmp.setPixel32(x, mid, 0xFFFFFFFF);

		var n:Int = sampleTimes.length;
		var lastTime:Float = sampleTimes[n - 1];
		if (lastTime <= 0)
			lastTime = 1;
		var range:Float = 180.0;
		for (i in 0...n) {
			var x:Int = Std.int((sampleTimes[i] / lastTime) * (w - 3)) + 1;
			var off:Float = sampleOffsets[i];
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

	/**
	 * Renders a rolling unstable-rate line over song time: at each column the local UR of a sliding
	 * window of taps, scaled against the run's peak so the shape reads clearly.
	 * @param w the graph width
	 * @param h the graph height
	 * @return the finished sprite
	 */
	function buildURGraph(w:Int, h:Int):FlxSprite {
		var bmp:BitmapData = new BitmapData(w, h, true, 0x88000000);
		var n:Int = sampleTimes.length;

		// Per-column rolling UR over a window of samples centred on each column's song time.
		var half:Int = Std.int(Math.max(3, n / 24));
		var col:Array<Float> = [];
		var peak:Float = 1;
		var lastTime:Float = sampleTimes[n - 1];
		if (lastTime <= 0)
			lastTime = 1;
		for (x in 0...w) {
			// Sample index nearest this column's time.
			var centre:Int = Std.int((x / (w - 1)) * (n - 1));
			var lo:Int = centre - half;
			if (lo < 0)
				lo = 0;
			var hi:Int = centre + half;
			if (hi > n - 1)
				hi = n - 1;
			var win:Array<Float> = [];
			for (k in lo...hi + 1)
				win.push(sampleOffsets[k]);
			var ur:Float = computeUR(win);
			col.push(ur);
			if (ur > peak)
				peak = ur;
		}

		var prevY:Int = -1;
		for (x in 0...w) {
			var norm:Float = col[x] / peak;
			var y:Int = (h - 2) - Std.int(norm * (h - 4));
			if (y < 0)
				y = 0;
			else if (y >= h)
				y = h - 1;
			bmp.setPixel32(x, y, 0xFFFFD75E);
			if (y + 1 < h)
				bmp.setPixel32(x, y + 1, 0xFFFFD75E);
			// Join to the previous column so it reads as a continuous line, not dots.
			if (prevY >= 0) {
				var a:Int = prevY < y ? prevY : y;
				var b:Int = prevY < y ? y : prevY;
				for (yy in a...b + 1)
					bmp.setPixel32(x, yy, 0x88FFD75E);
			}
			prevY = y;
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
		FlxG.signals.gameResized.remove(onGameResized);
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
