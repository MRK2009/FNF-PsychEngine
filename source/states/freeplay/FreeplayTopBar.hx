package states.freeplay;

import smidr.UIRoot;
import smidr.widgets.UIPanel;
import smidr.widgets.UILabel;
import smidr.widgets.UITextInput;
import smidr.widgets.UIDropdown;
import backend.freeplay.SongLibrary;
import backend.freeplay.SongEntry;
import backend.difficulty.DifficultyRating.ChartRatings;

/**
 * The Freeplay top bar, built with **Smidr** and anchored flush across the very top of the screen
 * (frosted, 50% transparent). Replaces the old classic Flixel `SORT / GROUP / SEARCH` header: a search
 * field plus clickable Sort and Group dropdowns, and a live library-MSD readout on the right. The
 * control cluster is centred (clamped clear of the top-left FPS overlay). The classic keyboard
 * shortcuts (T / Q / E / TAB) still drive the same state and call back here to keep the captions in
 * sync.
 */
class FreeplayTopBar {
	static inline final PAD:Float = 14;
	static inline final SEARCH_W:Float = 260;
	static inline final SORT_W:Float = 150;
	static inline final GROUP_W:Float = 180;
	static inline final CTRL_H:Float = 32;
	static inline final CAP_GAP:Float = 6;
	static inline final SECTION_GAP:Float = 18;
	static inline final FPS_CLEARANCE:Float = 380; // keep the cluster right of the FPS/memory overlay

	var root:UIRoot;
	var library:SongLibrary;

	var panel:UIPanel;
	public var searchInput:UITextInput;
	var sortCap:UILabel;
	var sortDrop:UIDropdown;
	var groupCap:UILabel;
	var groupDrop:UIDropdown;
	var msdLbl:UILabel;

	var onGroup:Int->Void;

	var bx:Float = 0;
	var by:Float = 0;
	var bw:Float = 1000;
	var bh:Float = 42;

	/**
	 * Builds the bar's widgets into the Smidr root.
	 * @param root the Smidr UI root to parent into
	 * @param library the song library driving the readouts and options
	 * @param onSearch fired with the query text on every search keystroke
	 * @param onSort fired with the picked sort index
	 * @param onGroup fired with the picked group-option index
	 */
	public function new(root:UIRoot, library:SongLibrary, onSearch:String->Void, onSort:Int->Void, onGroup:Int->Void) {
		this.root = root;
		this.library = library;
		this.onGroup = onGroup;

		panel = new UIPanel(bw, bh);
		panel.alpha = 0.5;
		root.content.addChild(panel);

		searchInput = new UITextInput('', SEARCH_W, '', onSearch);
		searchInput.fontSize = 14;
		root.content.addChild(searchInput);

		sortCap = new UILabel('SORT', 12, 2);
		root.content.addChild(sortCap);
		sortDrop = new UIDropdown('', SORT_W, (i, _) -> onSort(i));
		sortDrop.setItems(SongLibrary.SORTS);
		root.content.addChild(sortDrop);

		groupCap = new UILabel('GROUP', 12, 2);
		root.content.addChild(groupCap);
		groupDrop = new UIDropdown('', GROUP_W, (i, _) -> onGroup(i));
		root.content.addChild(groupDrop);

		msdLbl = new UILabel('', 13, 1);
		root.content.addChild(msdLbl);

		rebuildGroups();
	}

	/**
	 * Sets the bar's rect (screen == UI coords) and lays the centred control cluster out in one row.
	 * @param x the rect's left edge
	 * @param y the rect's top edge
	 * @param w the rect's width
	 * @param h the rect's height
	 */
	public function setArea(x:Float, y:Float, w:Float, h:Float):Void {
		bx = x;
		by = y;
		bw = w;
		bh = h;
		panel.x = x;
		panel.y = y;
		panel.resize(w, h);

		sortCap.measure();
		groupCap.measure();

		var clusterW:Float = SEARCH_W + SECTION_GAP + sortCap.w + CAP_GAP + SORT_W + SECTION_GAP + groupCap.w + CAP_GAP + GROUP_W;
		var startX:Float = Math.max(x + FPS_CLEARANCE, x + (w - clusterW) * 0.5);
		var ctrlY:Float = y + (h - CTRL_H) * 0.5;

		searchInput.x = startX;
		searchInput.y = ctrlY;

		var cx:Float = startX + SEARCH_W + SECTION_GAP;
		sortCap.x = cx;
		sortCap.y = y + (h - sortCap.h) * 0.5;
		cx += sortCap.w + CAP_GAP;
		sortDrop.x = cx;
		sortDrop.y = ctrlY;
		cx += SORT_W + SECTION_GAP;

		groupCap.x = cx;
		groupCap.y = y + (h - groupCap.h) * 0.5;
		cx += groupCap.w + CAP_GAP;
		groupDrop.x = cx;
		groupDrop.y = ctrlY;

		msdLbl.y = y + (h - 18) * 0.5;
		refreshMsd();
	}

	/** (Re)fills the group dropdown from the library's current group options. */
	public function rebuildGroups():Void {
		var labels:Array<String> = [];
		for (g in library.groupOptions)
			labels.push(groupLabel(g));
		groupDrop.setItems(labels);
		groupDrop.select(library.curGroupIdx);
	}

	/**
	 * Keeps the sort dropdown's caption in sync with a keyboard-driven change; fires no callback.
	 * @param idx the sort index to show
	 */
	public function setSort(idx:Int):Void
		sortDrop.select(idx);

	/**
	 * Keeps the group dropdown's caption in sync with a keyboard-driven change; fires no callback.
	 * @param idx the group-option index to show
	 */
	public function setGroup(idx:Int):Void
		groupDrop.select(idx);

	/** Library average MSD over the songs rated so far (updates as the scan streams in). */
	public function refreshMsd():Void {
		var sum:Float = 0;
		var n:Int = 0;
		for (e in library.entries) {
			var r:ChartRatings = e.ratingFor(library.representativeDiff(e));
			if (r == null)
				continue;
			var msd = r.results.get('etterna_msd');
			if (msd != null) {
				sum += msd.overall;
				n++;
			}
		}
		var avg:String = (n > 0) ? fmt2(sum / n) : '—';
		msdLbl.text = library.entries.length + ' songs      Avg MSD ' + avg;
		msdLbl.measure();
		msdLbl.x = bx + bw - PAD - msdLbl.w;
	}

	/**
	 * Display label for a group option.
	 * @param g the group value: -1 all, -2 favorites, otherwise a week index
	 * @return the human-readable label
	 */
	function groupLabel(g:Int):String {
		return switch (g) {
			case -1: 'All';
			case -2: '♥ Favorites';
			default: (g >= 0 && g < library.weekNames.length && library.weekNames[g] != null) ? library.weekNames[g] : 'Week ' + (g + 1);
		}
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
}
