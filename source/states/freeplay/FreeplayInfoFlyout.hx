package states.freeplay;

import flixel.FlxG;
import flixel.FlxSprite;
import flixel.text.FlxText;
import flixel.math.FlxRect;
import flixel.util.FlxColor;
import flixel.group.FlxSpriteGroup;
import flixel.tweens.FlxTween;
import flixel.tweens.FlxEase;
import backend.SongMeta.SongMetaInfo;
import backend.difficulty.DifficultyRating;
import backend.difficulty.DifficultyRating.ChartRatings;
import states.FreeplayState.SongMetadata;

/**
 * Right-edge metadata + difficulty-rating flyout for FreeplayState.
 *
 * Lives *inside* FreeplayState as an `add()`-ed member (like MusicPlayer) rather than
 * a substate, so it can be a focused sub-mode: while open it captures navigation
 * (FreeplayState pauses song scrolling), and closing returns control. Visual idiom
 * (bordered dark panel, vcr.ttf, clamped scroll + "n-m of t" hint) follows
 * substates.ModSecuritySubstate.
 *
 * Content is a list of collapsible sections (Song / Difficulty / Chart / Extra, and
 * later an MSD skillsets section). Each row is an FlxText positioned in the group's
 * local space and clipped to the scroll viewport via `clipRect`.
 */
class FreeplayInfoFlyout extends FlxSpriteGroup {
	static inline final PANEL_W:Int = 460;
	static inline final BORDER:Int = 3;
	static inline final HEADER_H:Int = 56;
	static inline final PAD:Int = 16;
	static inline final HEADER_ROW_H:Int = 30;
	static inline final LINE_H:Int = 24;
	static inline final BIG_H:Int = 40;
	static inline final SECTION_GAP:Int = 14;
	static inline final SCROLL_STEP:Float = 48;
	static inline final LINK_COLOR:FlxColor = 0xFF59B0FF;
	static inline final LINK_HOVER_COLOR:FlxColor = 0xFFAEE0FF;

	public var open:Bool = false;

	// Invoked when the user presses LEFT/RIGHT inside the flyout to switch difficulty.
	// FreeplayState updates curDifficulty and calls setSong() again with the new diff.
	public var onChangeDiff:Int->Void = null;

	var closedX:Float;
	var openX:Float;
	var viewTop:Float;
	var viewBottom:Float;

	var bg:FlxSprite;
	var border:FlxSprite;
	var headerBar:FlxSprite;
	var titleTxt:FlxText;
	var scrollHint:FlxText;

	// Section model.
	var sectionTitles:Array<String> = [];
	var sectionLines:Array<Array<Line>> = [];
	var collapsed:Map<String, Bool> = new Map();
	var selIndex:Int = 0;
	var scrollOffset:Float = 0;

	// Live row sprites (rebuilt on any content/selection change).
	var rows:Array<FlxText> = [];
	var rowLayoutY:Array<Float> = [];
	var rowIndentPx:Array<Float> = [];
	var rowLink:Array<String> = []; // parallel to rows; URL for clickable rows, else null

	// Currently shown song/difficulty + its computed ratings.
	var curMeta:SongMetadata = null;
	var curDiff:Int = 0;
	var lastKey:String = null;
	var ratings:ChartRatings = null;

	var slideTween:FlxTween = null;

	public function new() {
		super();

		closedX = FlxG.width + 10;
		openX = FlxG.width - PANEL_W;
		viewTop = HEADER_H + 10;
		viewBottom = FlxG.height - 40;

		x = closedX; // place the (empty) group off-screen so chrome lands at closed pos
		y = 0;

		border = mk(0xFF8A7BFF, PANEL_W + BORDER * 2, FlxG.height, -BORDER, 0);
		bg = mk(0xFF14161E, PANEL_W, FlxG.height, 0, 0);
		bg.alpha = 0.97;
		headerBar = mk(0xFF1F2230, PANEL_W, HEADER_H, 0, 0);

		titleTxt = new FlxText(PAD, 14, PANEL_W - PAD * 2, "SONG INFO", 24);
		titleTxt.setFormat(Paths.font("vcr.ttf"), 24, FlxColor.WHITE, LEFT, OUTLINE, FlxColor.BLACK);
		titleTxt.borderSize = 1.5;
		titleTxt.scrollFactor.set();
		add(titleTxt);

		scrollHint = new FlxText(PAD, FlxG.height - 34, PANEL_W - PAD * 2, "", 13);
		scrollHint.setFormat(Paths.font("vcr.ttf"), 13, 0xFF9090A0, RIGHT, OUTLINE, FlxColor.BLACK);
		scrollHint.borderSize = 1;
		scrollHint.scrollFactor.set();
		add(scrollHint);
	}

	inline function mk(color:FlxColor, w:Int, h:Int, lx:Float, ly:Float):FlxSprite {
		var s:FlxSprite = new FlxSprite(lx, ly).makeGraphic(1, 1, FlxColor.WHITE);
		s.scale.set(w, h);
		s.updateHitbox();
		s.color = color;
		s.scrollFactor.set();
		add(s);
		return s;
	}

	/** Sets the song + difficulty to display. Recomputes only when actually open (cheap, but no point while hidden). */
	public function setSong(meta:SongMetadata, diff:Int):Void {
		curMeta = meta;
		curDiff = diff;
		if (open)
			refresh();
	}

	public function toggle():Void {
		if (open)
			close();
		else
			openFlyout();
	}

	var prevMouseVisible:Bool = false;

	public function openFlyout():Void {
		if (open)
			return;
		open = true;
		lastKey = null; // force refresh
		selIndex = 0;
		scrollOffset = 0;
		// Show the cursor so links are clickable; restored on close.
		prevMouseVisible = FlxG.mouse.visible;
		FlxG.mouse.visible = true;
		refresh();
		slide(openX);
	}

	public function close():Void {
		if (!open)
			return;
		open = false;
		FlxG.mouse.visible = prevMouseVisible;
		slide(closedX);
	}

	function slide(toX:Float):Void {
		if (slideTween != null)
			slideTween.cancel();
		slideTween = FlxTween.tween(this, {x: toX}, 0.28, {ease: FlxEase.quartOut});
	}

	/** Rebuilds the section model + rows for the current song/difficulty (cache-first ratings). */
	function refresh():Void {
		if (curMeta == null)
			return;
		var key:String = curMeta.songName + '|' + curDiff;
		if (key == lastKey)
			return;
		lastKey = key;

		ratings = DifficultyRating.ratingsFor(curMeta.songName, curDiff);
		buildSections();
		if (selIndex >= sectionTitles.length)
			selIndex = Std.int(Math.max(0, sectionTitles.length - 1));
		rebuild();
	}

	function buildSections():Void {
		sectionTitles = [];
		sectionLines = [];

		// -- Song (per-song metadata.json) --
		var song:Array<Line> = [];
		song.push(line(curMeta.songName, true, FlxColor.WHITE));
		if (has(curMeta.artist))
			song.push(line('Artist: ' + curMeta.artist));
		if (has(curMeta.charter))
			song.push(line('Charter: ' + curMeta.charter));
		if (has(curMeta.source))
			song.push(line('Source/Mod: ' + curMeta.source));
		if (curMeta.tags != null && curMeta.tags.length > 0)
			song.push(line('Tags: ' + curMeta.tags.join(', ')));
		addSection('SONG', song);

		// -- Difficulty --
		var diff:Array<Line> = [];
		var diffName:String = Difficulty.getString(curDiff);
		diff.push(line(diffName.toUpperCase(), false, 0xFFB0B0C0));
		if (ratings != null) {
			if (ClientPrefs.data.showOsuRating) {
				var osu = ratings.results.get('osu_mania_star');
				diff.push(line(osu != null ? osu.label : 'osu! n/a', true, 0xFFFF66AA));
			}
			if (ClientPrefs.data.showMsdRating) {
				var msd = ratings.results.get('etterna_msd');
				if (msd != null)
					diff.push(line('MSD ' + fmt2(msd.overall), true, 0xFF66CCFF));
			}
		} else {
			diff.push(line('Rating unavailable (chart not found)', false, 0xFFCC6666));
		}
		addSection('DIFFICULTY', diff);

		// -- MSD skillsets (Phase B; only when present) --
		if (ratings != null && ClientPrefs.data.showMsdRating) {
			var msd = ratings.results.get('etterna_msd');
			if (msd != null && msd.components.length > 0) {
				var skills:Array<Line> = [];
				for (c in msd.components)
					skills.push(line(rpad(c.name, 12) + fmt2(c.value)));
				addSection('MSD SKILLSETS', skills);
			}
		}

		// -- Chart (derived from the chart, with optional metadata overrides) --
		if (ratings != null) {
			var stats:Array<Line> = [];

			// BPM: a range when the chart changes BPM. An override replaces it (noting the
			// chart's real range in parentheses when they differ).
			var chartBpm:String = bpmRangeText(ratings);
			if (curMeta.displayBpm > 0) {
				var ov:String = trimNum(curMeta.displayBpm);
				stats.push(line('BPM: ' + ov + (ov != chartBpm ? ' (chart ' + chartBpm + ')' : '')));
			} else
				stats.push(line('BPM: ' + chartBpm));

			// Time signature: an override, else every distinct signature the chart uses.
			if (curMeta.displayTimeSignature != null && curMeta.displayTimeSignature.length >= 2)
				stats.push(line('Time Signature: ' + curMeta.displayTimeSignature[0] + '/' + curMeta.displayTimeSignature[1]));
			else
				stats.push(line('Time Signature: ' + sigListText(ratings.timeSignatures)));

			stats.push(line('Keys: ' + ratings.keyCount + 'K'));
			stats.push(line('Notes: ' + ratings.playerNotes + ' player / ' + ratings.opponentNotes + ' opponent'));
			stats.push(line('Length: ' + timeStr(ratings.lengthMs)));

			// Per-difficulty charter override (when this difficulty has its own charter).
			var diffCharter:String = diffCharterFor(curDiff);
			if (has(diffCharter))
				stats.push(line('Charter: ' + diffCharter));

			// Beatmap ID is only meaningful for osu! converts -- clickable to the listing.
			if (curMeta.beatmapId > 0)
				stats.push(line('Beatmap ID: ' + curMeta.beatmapId + '  [open ↗]', false, LINK_COLOR,
					'https://osu.ppy.sh/beatmapsets/' + curMeta.beatmapId));

			addSection('CHART', stats);
		}

		// -- Extra (user-defined metadata.json info[] rows) --
		if (curMeta.info != null && curMeta.info.length > 0) {
			var extra:Array<Line> = [];
			for (row in curMeta.info)
				if (row != null && has(row.label))
					extra.push(line(row.label + ': ' + (row.value != null ? row.value : '')));
			if (extra.length > 0)
				addSection('MORE', extra);
		}
	}

	inline function addSection(title:String, lines:Array<Line>):Void {
		sectionTitles.push(title);
		sectionLines.push(lines);
		if (!collapsed.exists(title))
			collapsed.set(title, false);
	}

	inline function isCollapsed(title:String):Bool
		return collapsed.exists(title) && collapsed.get(title);

	/** Destroys + recreates row FlxTexts from the section model, then positions them. */
	function rebuild():Void {
		for (r in rows) {
			remove(r, true);
			r.destroy();
		}
		rows = [];
		rowLayoutY = [];
		rowIndentPx = [];
		rowLink = [];

		var ly:Float = 0;
		for (si in 0...sectionTitles.length) {
			var title:String = sectionTitles[si];
			var marker:String = isCollapsed(title) ? '▶ ' : '▼ ';
			var selected:Bool = (si == selIndex);
			var header:FlxText = makeRow(marker + title, 22, selected ? 0xFFFFE08A : 0xFFE8E8F0);
			header.borderSize = 1.25;
			pushRow(header, ly, 0, null);
			ly += HEADER_ROW_H;

			if (!isCollapsed(title)) {
				for (l in sectionLines[si]) {
					var h:Int = l.big ? BIG_H : LINE_H;
					var size:Int = l.big ? 30 : 17;
					var t:FlxText = makeRow(l.text, size, l.color);
					pushRow(t, ly, PAD, l.link); // indent content under its header
					ly += h;
				}
			}
			ly += SECTION_GAP;
		}

		reposition();
	}

	inline function pushRow(t:FlxText, layoutY:Float, indent:Float, link:String):Void {
		rows.push(t);
		rowLayoutY.push(layoutY);
		rowIndentPx.push(indent);
		rowLink.push(link);
	}

	inline function makeRow(text:String, size:Int, color:FlxColor):FlxText {
		var t:FlxText = new FlxText(0, 0, PANEL_W - PAD * 2, text, size);
		t.setFormat(Paths.font("vcr.ttf"), size, color, LEFT, OUTLINE, FlxColor.BLACK);
		t.borderSize = 1;
		t.scrollFactor.set();
		add(t);
		return t;
	}

	/** Clamps scroll, then positions every row absolutely and clips it to the viewport. */
	function reposition():Void {
		var totalH:Float = rows.length > 0 ? (rowLayoutY[rowLayoutY.length - 1] + lastRowHeight()) : 0;
		var viewH:Float = viewBottom - viewTop;
		var maxScroll:Float = Math.max(0, totalH - viewH);
		if (scrollOffset < 0)
			scrollOffset = 0;
		else if (scrollOffset > maxScroll)
			scrollOffset = maxScroll;

		for (i in 0...rows.length) {
			var t:FlxText = rows[i];
			var localY:Float = viewTop + rowLayoutY[i] - scrollOffset;
			var h:Float = t.height;
			var visTop:Float = Math.max(localY, viewTop);
			var visBot:Float = Math.min(localY + h, viewBottom);
			if (visBot <= visTop) {
				t.visible = false;
				continue;
			}
			t.visible = true;
			// Absolute position (group stores children in world space; x slides via set_x).
			t.x = this.x + PAD + rowIndentPx[i];
			t.y = this.y + localY;
			t.clipRect = FlxRect.get(0, visTop - localY, t.width, visBot - visTop);
		}

		// Scroll hint mirrors ModSecuritySubstate's footer.
		if (maxScroll > 0)
			scrollHint.text = 'UP/DOWN select  ←/→ diff  ENTER collapse  WHEEL scroll';
		else
			scrollHint.text = 'UP/DOWN select  ←/→ diff  ENTER collapse';
	}

	inline function lastRowHeight():Float
		return rows.length > 0 ? rows[rows.length - 1].height : 0;

	/** Called by FreeplayState every frame while the flyout is the focused sub-mode. */
	public function updateInput(elapsed:Float):Void {
		if (!open)
			return;

		handleLinks();

		var moved:Bool = false;
		if (FlxG.keys.justPressed.UP) {
			selIndex = (selIndex - 1 + sectionTitles.length) % Std.int(Math.max(1, sectionTitles.length));
			ensureSelVisible();
			moved = true;
		} else if (FlxG.keys.justPressed.DOWN) {
			selIndex = (selIndex + 1) % Std.int(Math.max(1, sectionTitles.length));
			ensureSelVisible();
			moved = true;
		}

		if (FlxG.keys.justPressed.ENTER || FlxG.keys.justPressed.SPACE) {
			var title:String = sectionTitles[selIndex];
			collapsed.set(title, !isCollapsed(title));
			FlxG.sound.play(Paths.sound('scrollMenu'), 0.5);
			rebuild();
		}

		if ((FlxG.keys.justPressed.LEFT || FlxG.keys.justPressed.RIGHT) && onChangeDiff != null) {
			onChangeDiff(FlxG.keys.justPressed.LEFT ? -1 : 1);
			// onChangeDiff updates curDifficulty and calls setSong(); force a refresh.
			lastKey = null;
			refresh();
			FlxG.sound.play(Paths.sound('scrollMenu'), 0.4);
		}

		if (FlxG.mouse.wheel != 0) {
			scrollOffset -= FlxG.mouse.wheel * SCROLL_STEP;
			reposition();
		}
		if (FlxG.keys.justPressed.PAGEUP) {
			scrollOffset -= (viewBottom - viewTop);
			reposition();
		} else if (FlxG.keys.justPressed.PAGEDOWN) {
			scrollOffset += (viewBottom - viewTop);
			reposition();
		}

		if (moved) {
			FlxG.sound.play(Paths.sound('scrollMenu'), 0.4);
			rebuild(); // selection highlight changed
		}
	}

	/** Hover-highlights and click-opens any link rows (e.g. the osu! Beatmap ID). */
	function handleLinks():Void {
		var mx:Float = FlxG.mouse.x;
		var my:Float = FlxG.mouse.y;
		var clicked:Bool = FlxG.mouse.justPressed;
		for (i in 0...rows.length) {
			var url:String = rowLink[i];
			if (url == null)
				continue;
			var t:FlxText = rows[i];
			if (!t.visible || t.clipRect == null)
				continue;
			// Clickable region = the row's currently-visible (clipped) slice, in screen space.
			var rx:Float = t.x;
			var ry:Float = t.y + t.clipRect.y;
			var hover:Bool = mx >= rx && mx <= rx + t.width && my >= ry && my <= ry + t.clipRect.height;
			t.color = hover ? LINK_HOVER_COLOR : LINK_COLOR;
			if (hover && clicked) {
				FlxG.sound.play(Paths.sound('confirmMenu'), 0.6);
				CoolUtil.browserLoad(url);
			}
		}
	}

	/** Scrolls so the selected section header sits inside the viewport. */
	function ensureSelVisible():Void {
		// Find the row index of the selected header.
		var headerLayoutY:Float = 0;
		var ly:Float = 0;
		for (si in 0...sectionTitles.length) {
			if (si == selIndex) {
				headerLayoutY = ly;
				break;
			}
			ly += HEADER_ROW_H;
			if (!isCollapsed(sectionTitles[si]))
				for (l in sectionLines[si])
					ly += l.big ? BIG_H : LINE_H;
			ly += SECTION_GAP;
		}
		var viewH:Float = viewBottom - viewTop;
		if (headerLayoutY < scrollOffset)
			scrollOffset = headerLayoutY;
		else if (headerLayoutY + HEADER_ROW_H > scrollOffset + viewH)
			scrollOffset = headerLayoutY + HEADER_ROW_H - viewH;
	}

	/* -- small helpers -- */
	inline function line(text:String, big:Bool = false, color:FlxColor = FlxColor.WHITE, ?link:String):Line
		return {text: text, big: big, color: color, link: link};

	inline function has(s:String):Bool
		return s != null && s.length > 0;

	/** Per-difficulty charter override from metadata.json `charters` (keyed by difficulty name), or null. */
	function diffCharterFor(diff:Int):String {
		if (curMeta.charters == null)
			return null;
		var raw:String = Difficulty.getString(diff, false);
		if (raw != null && curMeta.charters.exists(raw))
			return curMeta.charters.get(raw);
		var disp:String = Difficulty.getString(diff);
		if (disp != null && curMeta.charters.exists(disp))
			return curMeta.charters.get(disp);
		return null;
	}

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

	static function trimNum(v:Float):String {
		if (v == Std.int(v))
			return Std.string(Std.int(v));
		return fmt2(v);
	}

	/** "150" when constant, "150-180" when the chart changes BPM. */
	static function bpmRangeText(r:ChartRatings):String {
		if (Math.abs(r.bpmMax - r.bpmMin) < 0.01)
			return trimNum(r.bpmMin);
		return trimNum(r.bpmMin) + '-' + trimNum(r.bpmMax);
	}

	/** "4/4" for a single signature, else every distinct one joined: "4/4, 7/8". */
	static function sigListText(sigs:Array<Array<Int>>):String {
		if (sigs == null || sigs.length < 1)
			return '4/4';
		var parts:Array<String> = [];
		for (s in sigs)
			parts.push(s[0] + '/' + s[1]);
		return parts.join(', ');
	}

	static function rpad(s:String, n:Int):String {
		while (s.length < n)
			s += ' ';
		return s;
	}

	static function timeStr(ms:Float):String {
		var total:Int = Std.int(ms / 1000);
		var m:Int = Std.int(total / 60);
		var sec:Int = total % 60;
		return m + ':' + (sec < 10 ? '0' + sec : '' + sec);
	}
}

private typedef Line = {
	var text:String;
	var big:Bool;
	var color:FlxColor;
	@:optional var link:String; // when set, the row is a clickable URL
}
