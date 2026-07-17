package states.freeplay;

import flixel.FlxG;
import smidr.UIRoot;
import smidr.widgets.UIPanel;
import smidr.widgets.UILabel;
import smidr.widgets.UITabs;
import backend.Highscore;
import backend.freeplay.SongEntry;
import backend.difficulty.DifficultyRating.ChartRatings;
import backend.difficulty.RatingResult;

/**
 * The right-edge Freeplay info panel — Smidr, frosted 50%, overlaid on top of the classic Flixel song
 * list (which stays clear on the left). Three tabs, and the last-used tab is remembered across songs
 * and sessions (`FlxG.save.data.freeplayInfoTab`):
 *
 *  - **General**  — cover/title, metadata, the difficulty, the headline star + MSD numbers (no skillset
 *                   spread), and the top score.
 *  - **Scores**   — the score list. Phase 1 shows the single best; the full multi-score history + the
 *                   osu!-style result screen land with score recording (Phase 2).
 *  - **Insights** — the full Etterna MSD skillset spread + note-pattern / chart stats.
 *
 * Content is a set of (single- or multi-line) `UILabel`s laid out top-down; only the active tab's
 * labels are shown, and `show()` reflows them for the current song/difficulty.
 */
class FreeplayInfoPanel {
	static inline final PAD:Float = 16;
	static inline final GAP:Float = 7;
	static inline final TABS_H:Float = 40;
	static inline final GOLD:Int = 0xFFFFC234; // osu! star
	static inline final HOT:Int = 0xFFFF5D6C; // MSD
	static inline final MSD_BLUE:Int = 0xFF66CCFF;

	public static inline final TAB_GENERAL:Int = 0;
	public static inline final TAB_SCORES:Int = 1;
	public static inline final TAB_INSIGHTS:Int = 2;

	var root:UIRoot;
	var panel:UIPanel;
	var tabs:UITabs;
	var curTab:Int = 0;

	// General
	var gTitle:UILabel;
	var gSub:UILabel;
	var gDiff:UILabel;
	var gMsd:UILabel;
	var gOsu:UILabel;
	var gMeta:UILabel;
	var gScoreHdr:UILabel;
	var gScore:UILabel;
	var gScoreMeta:UILabel;
	// Scores
	var sTitle:UILabel;
	var sList:UILabel;
	var sStub:UILabel;
	// Insights
	var iTitle:UILabel;
	var iMsd:UILabel;
	var iSkillHdr:UILabel;
	var iSkills:UILabel;
	var iStatHdr:UILabel;
	var iStats:UILabel;

	var byTab:Array<Array<UILabel>>;

	var px:Float = 0;
	var py:Float = 0;
	var pw:Float = 400;
	var ph:Float = 600;

	// last shown song/diff (so a streamed rating or a tab switch can re-render without re-plumbing)
	var lastEntry:SongEntry = null;
	var lastDiffName:String = null;
	var lastDiffDisp:String = null;
	var lastDiffCount:Int = 0;

	/**
	 * Builds the panel, the tab strip and every label, and restores the last-used tab.
	 * @param root the Smidr UI root to parent into
	 */
	public function new(root:UIRoot) {
		this.root = root;

		panel = new UIPanel(pw, ph);
		panel.alpha = 0.5;
		root.content.addChild(panel);

		curTab = 0;
		try {
			if (FlxG.save.data.freeplayInfoTab != null)
				curTab = Std.int(FlxG.save.data.freeplayInfoTab);
		} catch (e:Dynamic) {}
		if (curTab < 0 || curTab > 2)
			curTab = 0;

		tabs = new UITabs(pw, [{label: 'General'}, {label: 'Scores'}, {label: 'Insights'}], onTab);
		root.content.addChild(tabs);

		gTitle = mk(24, 0);
		gSub = mk(13, 1);
		gDiff = mk(16, 0);
		gMsd = mk(19, 0);
		gMsd.colorOverride = HOT;
		gOsu = mk(19, 0);
		gOsu.colorOverride = GOLD;
		gMeta = mk(14, 1);
		gScoreHdr = mk(11, 2);
		gScore = mk(28, 0);
		gScoreMeta = mk(14, 1);

		sTitle = mk(17, 0);
		sList = mk(15, 0);
		sStub = mk(12, 2);
		sStub.colorOverride = 0xFF8A8299;

		iTitle = mk(17, 0);
		iMsd = mk(18, 0);
		iMsd.colorOverride = HOT;
		iSkillHdr = mk(11, 2);
		iSkills = mk(14, 1);
		iStatHdr = mk(11, 2);
		iStats = mk(14, 1);

		byTab = [
			[gTitle, gSub, gDiff, gMsd, gOsu, gMeta, gScoreHdr, gScore, gScoreMeta],
			[sTitle, sList, sStub],
			[iTitle, iMsd, iSkillHdr, iSkills, iStatHdr, iStats]
		];

		tabs.select(curTab);
	}

	/**
	 * Creates an empty label parented into the UI root.
	 * @param size the font size
	 * @param tone the theme tone index
	 * @return the new label
	 */
	inline function mk(size:Int, tone:Int):UILabel {
		var l:UILabel = new UILabel('', size, tone);
		root.content.addChild(l);
		return l;
	}

	/**
	 * Tab-strip callback: persists the choice and re-renders the current song.
	 * @param i the newly selected tab index
	 */
	function onTab(i:Int):Void {
		curTab = i;
		try {
			FlxG.save.data.freeplayInfoTab = i;
			FlxG.save.flush();
		} catch (e:Dynamic) {}
		if (lastEntry != null)
			show(lastEntry, lastDiffName, lastDiffDisp, lastDiffCount);
		else
			reflow();
	}

	/**
	 * Sets the panel's rect (screen == UI coords) and reflows the content.
	 * @param x the rect's left edge
	 * @param y the rect's top edge
	 * @param w the rect's width
	 * @param h the rect's height
	 */
	public function setArea(x:Float, y:Float, w:Float, h:Float):Void {
		px = x;
		py = y;
		pw = w;
		ph = h;
		panel.x = x;
		panel.y = y;
		panel.resize(w, h);
		tabs.x = x;
		tabs.y = y;
		tabs.resize(w, TABS_H);
		reflow();
	}

	/** Shows or hides the whole panel, tabs and labels included. */
	public var visible(default, set):Bool = true;

	function set_visible(v:Bool):Bool {
		visible = v;
		panel.visible = v;
		tabs.visible = v;
		reflow();
		return v;
	}

	/**
	 * Fills the active tab for a song at a difficulty and reflows. Remembers the arguments so a
	 * streamed rating or a tab switch can re-render without re-plumbing.
	 * @param e the song to show, or null to blank the panel
	 * @param diffName the raw difficulty name, used for the rating lookup
	 * @param diffDisplay the localized difficulty name shown to the player
	 * @param diffCount how many difficulties the song has
	 */
	public function show(e:SongEntry, diffName:String, diffDisplay:String, diffCount:Int):Void {
		lastEntry = e;
		lastDiffName = diffName;
		lastDiffDisp = diffDisplay;
		lastDiffCount = diffCount;

		if (e == null) {
			for (row in byTab)
				for (l in row)
					l.text = '';
			reflow();
			return;
		}

		var ratings:ChartRatings = e.ratingFor(diffName);
		var pbScore:Int = Highscore.getScore(e.songName, diffIndexOf(diffName));
		var pbAcc:Float = Highscore.getRating(e.songName, diffIndexOf(diffName));

		switch (curTab) {
			case TAB_SCORES: fillScores(e, diffDisplay, pbScore, pbAcc);
			case TAB_INSIGHTS: fillInsights(e, diffDisplay, ratings);
			default: fillGeneral(e, diffDisplay, diffCount, ratings, pbScore, pbAcc);
		}
		reflow();
	}

	/**
	 * Fills the General tab: title, metadata, headline star + MSD, top score.
	 * @param e the song
	 * @param diffDisplay the localized difficulty name
	 * @param diffCount how many difficulties the song has, for the ‹ › arrows
	 * @param r the difficulty's ratings, or null while still computing
	 * @param pbScore the personal-best score
	 * @param pbAcc the personal-best accuracy in [0, 1]
	 */
	function fillGeneral(e:SongEntry, diffDisplay:String, diffCount:Int, r:ChartRatings, pbScore:Int, pbAcc:Float):Void {
		gTitle.text = e.songName;
		gSub.text = subtitle(e);
		gDiff.text = (diffCount > 1 ? '‹ ' : '') + diffDisplay.toUpperCase() + (diffCount > 1 ? ' ›' : '');

		if (r != null) {
			var osu = r.results.get('osu_mania_star');
			var msd = r.results.get('etterna_msd');
			gMsd.text = 'Etterna MSD    ' + (msd != null ? msd.label : '—');
			gOsu.text = 'osu! star    ' + (osu != null ? osu.label : '—');
		} else {
			gMsd.text = 'Etterna MSD    computing…';
			gOsu.text = '';
		}

		var meta:Array<String> = [];
		if (has(e.artist)) meta.push('Artist: ' + e.artist);
		if (has(e.charter)) meta.push('Charter: ' + e.charter);
		if (has(e.source)) meta.push('Source: ' + e.source);
		if (has(e.weekName)) meta.push('Group: ' + e.weekName);
		if (r != null) meta.push('BPM: ' + bpmText(r) + '    Length: ' + timeStr(r.lengthMs));
		gMeta.text = meta.join('\n');

		gScoreHdr.text = 'TOP SCORE';
		gScore.text = pbScore > 0 ? commas(pbScore) : 'No score yet';
		gScoreMeta.text = pbScore > 0 ? (fmt2(pbAcc * 100) + '%    ·    ' + grade(pbAcc)) : '';
	}

	/**
	 * Fills the Scores tab. Phase 1 shows the single best; the multi-score history lands in Phase 2.
	 * @param e the song
	 * @param diffDisplay the localized difficulty name
	 * @param pbScore the personal-best score
	 * @param pbAcc the personal-best accuracy in [0, 1]
	 */
	function fillScores(e:SongEntry, diffDisplay:String, pbScore:Int, pbAcc:Float):Void {
		sTitle.text = e.songName + '  —  ' + diffDisplay;
		if (pbScore > 0)
			sList.text = '1.   ' + commas(pbScore) + '    ·    ' + fmt2(pbAcc * 100) + '%    ' + grade(pbAcc);
		else
			sList.text = 'No scores yet — play it!';
		sStub.text = 'Multiple scores and the result screen arrive with score recording (Phase 2). This shows your single best for now.';
	}

	/**
	 * Fills the Insights tab: the full MSD skillset spread plus pattern and chart stats.
	 * @param e the song
	 * @param diffDisplay the localized difficulty name
	 * @param r the difficulty's ratings, or null while still computing
	 */
	function fillInsights(e:SongEntry, diffDisplay:String, r:ChartRatings):Void {
		iTitle.text = e.songName + '  —  ' + diffDisplay + (r != null ? '  ·  ' + r.keyCount + 'K' : '');
		if (r == null) {
			iMsd.text = 'Computing difficulty…';
			iSkillHdr.text = '';
			iSkills.text = '';
			iStatHdr.text = '';
			iStats.text = '';
			return;
		}

		var msd = r.results.get('etterna_msd');
		iMsd.text = 'MSD  ' + (msd != null ? msd.label : '—');
		iSkillHdr.text = 'SKILLSETS';
		if (msd != null && msd.components.length > 0) {
			var lines:Array<String> = [];
			for (c in msd.components)
				lines.push(rpad(c.name, 12) + fmt2(c.value));
			iSkills.text = lines.join('\n');
		} else
			iSkills.text = '—';

		iStatHdr.text = 'PATTERN & CHART';
		var s:Array<String> = [];
		s.push('Notes: ' + r.playerNotes + '  (opp ' + r.opponentNotes + ')');
		if (r.patterns != null) {
			s.push('Jumps: ' + r.patterns.jumps + '    Hands: ' + r.patterns.hands);
			s.push('Holds: ' + r.patterns.holds + '    Avg NPS: ' + fmt2(r.patterns.avgNps));
		}
		s.push('BPM: ' + bpmText(r) + '    Keys: ' + r.keyCount + 'K');
		s.push('Time Sig: ' + sigList(r.timeSignatures) + '    Length: ' + timeStr(r.lengthMs));
		iStats.text = s.join('\n');
	}

	/** Stacks the active tab's non-empty labels below the tab strip; hides everything else. */
	function reflow():Void {
		for (t in 0...byTab.length)
			if (t != curTab)
				for (l in byTab[t])
					l.visible = false;

		var innerW:Float = pw - PAD * 2;
		var cy:Float = py + TABS_H + PAD;
		for (l in byTab[curTab]) {
			if (!visible || l.text.length == 0) {
				l.visible = false;
				continue;
			}
			l.wrapWidth = innerW;
			var h:Float = l.measure();
			l.x = px + PAD;
			l.y = cy;
			l.visible = true;
			cy += h + gapFor(l);
		}
	}

	/**
	 * Vertical spacing after a label; section-ending labels get a double gap.
	 * @param l the label just laid out
	 * @return the gap in pixels
	 */
	inline function gapFor(l:UILabel):Float {
		return (l == gSub || l == gMeta || l == gScoreMeta || l == iStats || l == sStub) ? GAP * 2 : GAP;
	}

	/**
	 * @param s the string to test
	 * @return true when non-null and non-empty
	 */
	inline function has(s:String):Bool
		return s != null && s.length > 0;

	/**
	 * The General tab's subtitle line: artist, icon character and group, dot-separated.
	 * @param e the song
	 * @return the joined subtitle, possibly empty
	 */
	function subtitle(e:SongEntry):String {
		var parts:Array<String> = [];
		if (has(e.artist)) parts.push(e.artist);
		if (has(e.icon)) parts.push(cap(e.icon));
		if (has(e.weekName)) parts.push(e.weekName);
		return parts.join('  ·  ');
	}

	/**
	 * Maps a raw difficulty name back to its index in the current global `Difficulty.list`, for Highscore.
	 * @param diffName the raw difficulty name
	 * @return the list index, or 0 when not found
	 */
	function diffIndexOf(diffName:String):Int {
		var idx:Int = Difficulty.list.indexOf(diffName);
		return idx >= 0 ? idx : 0;
	}

	/**
	 * Letter grade for an accuracy.
	 * @param acc the accuracy in [0, 1]
	 * @return S/A/B/C/D, or a dash placeholder when zero
	 */
	static function grade(acc:Float):String {
		if (acc <= 0) return '—';
		if (acc >= 0.99) return 'S';
		if (acc >= 0.95) return 'A';
		if (acc >= 0.90) return 'B';
		if (acc >= 0.80) return 'C';
		return 'D';
	}

	/**
	 * Formats the chart's BPM, collapsing to a single number when it never changes.
	 * @param r the chart's ratings
	 * @return "120" or "120-180"
	 */
	static function bpmText(r:ChartRatings):String {
		if (Math.abs(r.bpmMax - r.bpmMin) < 0.01)
			return trimNum(r.bpmMin);
		return trimNum(r.bpmMin) + '-' + trimNum(r.bpmMax);
	}

	/**
	 * Formats the chart's time signatures as a comma-separated list.
	 * @param sigs the distinct [num, den] pairs
	 * @return the joined list, "4/4" when null or empty
	 */
	static function sigList(sigs:Array<Array<Int>>):String {
		if (sigs == null || sigs.length < 1)
			return '4/4';
		var parts:Array<String> = [];
		for (s in sigs)
			parts.push(s[0] + '/' + s[1]);
		return parts.join(', ');
	}

	/**
	 * Uppercases the first character.
	 * @param s the string
	 * @return the capitalized string; null/empty passes through
	 */
	static function cap(s:String):String
		return (s == null || s.length == 0) ? s : s.charAt(0).toUpperCase() + s.substr(1);

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
	 * Formats a number without trailing decimals when it is whole.
	 * @param v the value
	 * @return "120" for whole values, otherwise two decimals
	 */
	static function trimNum(v:Float):String {
		if (v == Std.int(v))
			return Std.string(Std.int(v));
		return fmt2(v);
	}

	/**
	 * Right-pads a string with spaces, for the aligned skillset columns.
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
	 * Formats a duration as m:ss.
	 * @param ms the duration in milliseconds
	 * @return the clock string
	 */
	static function timeStr(ms:Float):String {
		var total:Int = Std.int(ms / 1000);
		var m:Int = Std.int(total / 60);
		var sec:Int = total % 60;
		return m + ':' + (sec < 10 ? '0' + sec : '' + sec);
	}
}
