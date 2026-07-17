package states.freeplay;

import flixel.FlxG;
import smidr.UIRoot;
import smidr.widgets.UIPanel;
import smidr.widgets.UILabel;
import smidr.widgets.UITabs;
import smidr.widgets.UIButton;
import smidr.widgets.UIScrollPane;
import backend.Highscore;
import backend.freeplay.SongEntry;
import backend.difficulty.DifficultyRating.ChartRatings;
import backend.difficulty.RatingResult;
import backend.profiles.ProfileManager;
import backend.profiles.ScoreRecord;
import backend.scoring.ScoreSystems;

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
	var sRows:Array<UIButton> = [];
	var sAllBtn:UIButton;
	var sPane:UIScrollPane;
	var sRecords:Array<ScoreRecord> = [];
	var sExpanded:Bool = false;

	/** Fired when the user clicks a stored highscore; opens the results screen in view mode. */
	public var onScoreClick:ScoreRecord->Void = null;

	static inline final SCORE_ROW_H:Float = 30;
	static inline final SCORE_TOP_N:Int = 10;
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

		for (i in 0...SCORE_TOP_N) {
			var idx:Int = i;
			var b:UIButton = new UIButton('', 100, SCORE_ROW_H - 4, () -> rowClicked(idx));
			b.visible = false;
			root.content.addChild(b);
			sRows.push(b);
		}
		sAllBtn = new UIButton('Show all', 100, SCORE_ROW_H, toggleExpanded);
		sAllBtn.visible = false;
		root.content.addChild(sAllBtn);
		sPane = new UIScrollPane(100, 100);
		sPane.visible = false;
		root.content.addChild(sPane);

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
	 * Fills the Scores tab from the active profile's score database: the top rows as clickable
	 * buttons (opening the results screen in view mode), expandable to a scrollable full list.
	 * @param e the song
	 * @param diffDisplay the localized difficulty name
	 * @param pbScore the legacy personal-best score, shown when the DB has no records yet
	 * @param pbAcc the legacy personal-best accuracy in [0, 1]
	 */
	function fillScores(e:SongEntry, diffDisplay:String, pbScore:Int, pbAcc:Float):Void {
		sTitle.text = e.songName + '  -  ' + diffDisplay;
		sRecords = ProfileManager.scores().listFor(songKeyFor(e, lastDiffName));
		if (sRecords.length == 0) {
			sExpanded = false;
			if (pbScore > 0) {
				sList.text = 'Best (legacy): ' + commas(pbScore) + '    ' + fmt2(pbAcc * 100) + '%    ' + grade(pbAcc);
				sStub.text = 'Finish the song to record full scores here.';
			} else {
				sList.text = 'No scores yet.';
				sStub.text = 'Finish the song to record a score.';
			}
		} else {
			sList.text = '';
			sStub.text = sRecords.length + (sRecords.length == 1 ? ' score' : ' scores') + ' recorded.';
		}
	}

	/**
	 * The score-DB key for a song at a difficulty, matching how PlayState records plays.
	 * @param e the song
	 * @param diffName the raw difficulty name
	 * @return the songKey (path + difficulty suffix + keycount)
	 */
	function songKeyFor(e:SongEntry, diffName:String):String {
		var r:ChartRatings = e.ratingFor(diffName);
		var kc:Int = (r != null && r.keyCount > 0) ? r.keyCount : 4;
		return Highscore.formatSong(e.songName, diffIndexOf(diffName)) + '_' + kc + 'k';
	}

	/**
	 * One row's caption for a stored score.
	 * @param i the rank position (0-based)
	 * @param rec the record
	 * @return the row text
	 */
	function scoreRowLabel(i:Int, rec:ScoreRecord):String {
		var sys:Int = ScoreSystems.IDS.indexOf(rec.systemId);
		var tag:String = sys >= 0 ? ScoreSystems.LABELS[sys] : rec.systemId;
		var s:String = '${i + 1}.  ${commas(rec.score)}   ${fmt2(rec.accuracy * 100)}%   ${rec.grade}   $tag';
		if (rec.playbackRate != 1)
			s += '   ${rec.playbackRate}x';
		return s;
	}

	/**
	 * Opens the clicked score in the results screen.
	 * @param i the visible row index into the collapsed top list
	 */
	function rowClicked(i:Int):Void {
		if (onScoreClick != null && i < sRecords.length)
			onScoreClick(sRecords[i]);
	}

	/** Switches the Scores tab between the top rows and the full scrollable list. */
	function toggleExpanded():Void {
		sExpanded = !sExpanded;
		reflow();
	}

	/** Hides every score-row widget (used when leaving the Scores tab). */
	function hideScoreRows():Void {
		for (b in sRows)
			b.visible = false;
		sAllBtn.visible = false;
		sPane.visible = false;
	}

	/**
	 * Lays the score rows out below the stacked labels.
	 * @param topY the y below the last label
	 */
	function layoutScoreRows(topY:Float):Void {
		hideScoreRows();
		if (!visible || sRecords.length == 0)
			return;
		var innerW:Float = pw - PAD * 2;
		var bottom:Float = py + ph - PAD;

		if (!sExpanded) {
			var shown:Int = sRecords.length < SCORE_TOP_N ? sRecords.length : SCORE_TOP_N;
			var cy:Float = topY;
			for (i in 0...shown) {
				if (cy + SCORE_ROW_H > bottom - SCORE_ROW_H)
					break;
				var b:UIButton = sRows[i];
				b.label = (scoreRowLabel(i, sRecords[i]));
				b.resize(innerW, SCORE_ROW_H - 4);
				b.x = px + PAD;
				b.y = cy;
				b.visible = true;
				cy += SCORE_ROW_H;
			}
			if (sRecords.length > shown || sExpanded) {
				sAllBtn.label = ('Show all (${sRecords.length})');
				sAllBtn.resize(innerW, SCORE_ROW_H);
				sAllBtn.x = px + PAD;
				sAllBtn.y = cy + 4;
				sAllBtn.visible = true;
			}
		} else {
			sAllBtn.label = ('Show top ${SCORE_TOP_N}');
			sAllBtn.resize(innerW, SCORE_ROW_H);
			sAllBtn.x = px + PAD;
			sAllBtn.y = topY;
			sAllBtn.visible = true;

			var paneY:Float = topY + SCORE_ROW_H + 6;
			var paneH:Float = bottom - paneY;
			if (paneH < SCORE_ROW_H)
				return;
			sPane.x = px + PAD;
			sPane.y = paneY;
			sPane.resize(innerW, paneH);
			sPane.visible = true;

			while (sPane.content.numChildren > 0)
				sPane.content.removeChildAt(0);
			var cy:Float = 0;
			for (i in 0...sRecords.length) {
				var rec:ScoreRecord = sRecords[i];
				var b:UIButton = new UIButton(scoreRowLabel(i, rec), innerW - 14, SCORE_ROW_H - 4, () -> {
					if (onScoreClick != null)
						onScoreClick(rec);
				});
				b.x = 0;
				b.y = cy;
				sPane.content.addChild(b);
				cy += SCORE_ROW_H;
			}
			sPane.refreshContent(cy);
		}
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

	/**
	 * Stacks the active tab's non-empty labels below the tab strip and hides everything else;
	 * the Scores tab additionally lays its clickable rows out below the labels.
	 */
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

		if (curTab == TAB_SCORES && visible)
			layoutScoreRows(cy + 2);
		else
			hideScoreRows();
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
