package states.freeplay;

import flixel.FlxG;
import flixel.FlxSprite;
import flixel.group.FlxGroup;
import flixel.math.FlxMath;
import objects.Alphabet;
import objects.HealthIcon;
import backend.freeplay.SongLibrary;
import backend.freeplay.SongEntry;

/**
 * The classic FNF Freeplay song list, rendered on the **Flixel layer** on the left of the screen
 * (kept exactly as the original looked — big `Alphabet` titles, `HealthIcon` faces, favorite stars,
 * selected item bright + enlarged, the rest dimmed and shrunk). The Smidr top bar + info panel are
 * overlaid separately; this stays clear on the left.
 *
 * The redesign's headline fix: the old list built one Alphabet + one icon *per song up front*. Here a
 * small fixed **pool** of rows binds only to the entries around the selection, and scrolling rebinds a
 * single row at a time (slot = index % pool size). Construction is O(pool), not O(library) — smooth at
 * 1000+ songs — and a search that reshapes the list just re-points the pool instead of rebuilding
 * every sprite.
 */
class FreeplayListView extends FlxGroup {
	public static inline final DRAW:Int = 7;
	public static inline final POOL:Int = DRAW * 2 + 3;

	public static inline final ROW_STEP:Float = 82;
	public static inline final ICON:Int = 56;
	public static inline final STAR:Int = 46;
	public static inline final TITLE_SCALE:Float = 0.68;
	public static inline final SEL_TITLE_SCALE:Float = 0.9;

	public var library(default, null):SongLibrary;
	public var curSelected:Int = 0;

	var rows:Array<Row> = [];
	var lerpSelected:Float = 0;

	var areaX:Float = 60;
	var areaY:Float = 0;
	var areaW:Float = 700;
	var areaH:Float = 600;

	public function new(library:SongLibrary) {
		super();
		this.library = library;
		for (i in 0...POOL)
			rows.push(new Row(this, library));
	}

	/** Left-column rect the list occupies (set by FreeplayState). */
	public function setArea(x:Float, y:Float, w:Float, h:Float):Void {
		areaX = x;
		areaY = y;
		areaW = w;
		areaH = h;
	}

	/** Called after the library's `view` changes (search/sort/group): forces every pooled row to rebind. */
	public function refreshView():Void {
		if (curSelected >= library.view.length)
			curSelected = Std.int(Math.max(0, library.view.length - 1));
		for (r in rows)
			r.boundIndex = -1;
		lerpSelected = curSelected;
	}

	public function select(index:Int):Void {
		var n:Int = library.view.length;
		if (n < 1)
			return;
		curSelected = FlxMath.wrap(index, 0, n - 1);
	}

	public inline function selectedEntry():Null<SongEntry>
		return (curSelected >= 0 && curSelected < library.view.length) ? library.view[curSelected] : null;

	/** Entry index under a screen point, or -1 (for click-to-select). */
	public function indexAtScreen(mx:Float, my:Float):Int {
		for (r in rows)
			if (r.boundIndex >= 0 && r.shown && r.contains(mx, my))
				return r.boundIndex;
		return -1;
	}

	override function update(elapsed:Float):Void {
		lerpSelected = FlxMath.lerp(curSelected, lerpSelected, Math.exp(-elapsed * 12));
		if (Math.abs(lerpSelected - curSelected) < 0.001)
			lerpSelected = curSelected;

		var n:Int = library.view.length;
		var min:Int = Std.int(Math.max(0, Math.floor(lerpSelected) - DRAW));
		var max:Int = Std.int(Math.min(n, Math.ceil(lerpSelected) + DRAW + 1));

		for (r in rows)
			if (r.boundIndex < min || r.boundIndex >= max)
				r.hide();

		var centerY:Float = areaY + areaH * 0.5;
		for (i in min...max) {
			var slot:Int = i % POOL;
			if (slot < 0)
				slot += POOL;
			var r:Row = rows[slot];
			if (r.boundIndex != i)
				r.bind(library.view[i], i);
			r.layout(areaX, centerY + (i - lerpSelected) * ROW_STEP, areaW, i == curSelected);
		}

		super.update(elapsed);
	}
}

/**
 * One pooled row: an `Alphabet` title, its `HealthIcon`, and a favorite marker. Rebound to a different
 * `SongEntry` only when the scroll window moves it, so the Alphabet letter rebuild happens at most a
 * couple of times per frame.
 */
private class Row {
	public var boundIndex:Int = -1;
	public var shown:Bool = false;

	var owner:FreeplayListView;
	var library:SongLibrary;
	var entry:SongEntry;

	var title:Alphabet;
	var icon:HealthIcon;
	var star:FlxSprite; // favorite marker

	var rowX:Float = 0;
	var rowY:Float = 0;
	var rowW:Float = 0;
	var rowH:Float = 0;

	public function new(owner:FreeplayListView, library:SongLibrary) {
		this.owner = owner;
		this.library = library;

		title = new Alphabet(0, 0, '', true);
		title.visible = title.active = false;
		owner.add(title);

		icon = new HealthIcon('face');
		icon.autoAdjustOffset = false;
		icon.setGraphicSize(FreeplayListView.ICON, FreeplayListView.ICON);
		icon.updateHitbox();
		icon.visible = icon.active = false;
		owner.add(icon);

		star = new FlxSprite();
		if (!ClientPrefs.data.lowQuality) {
			star.frames = Paths.getSparrowAtlas('starMarkerAnimated');
			star.animation.addByPrefix('active', 'active', 24, false);
			star.animation.play('active');
			star.animation.finish();
		} else
			star.loadGraphic(Paths.image('starMarker'));
		star.antialiasing = ClientPrefs.data.antialiasing;
		star.setGraphicSize(FreeplayListView.STAR, FreeplayListView.STAR);
		star.updateHitbox();
		star.visible = star.active = false;
		owner.add(star);
	}

	public function bind(e:SongEntry, index:Int):Void {
		boundIndex = index;
		entry = e;
		title.text = e.songName;
		Mods.currentModDirectory = e.folder;
		icon.changeIcon(e.icon);
		icon.setGraphicSize(FreeplayListView.ICON, FreeplayListView.ICON);
		icon.updateHitbox();
	}

	public function layout(x:Float, y:Float, maxW:Float, selected:Bool):Void {
		shown = true;

		var scale:Float = selected ? FreeplayListView.SEL_TITLE_SCALE : FreeplayListView.TITLE_SCALE;
		title.setScale(scale);
		var maxTitleW:Float = maxW * 0.72;
		if (title.width > maxTitleW)
			title.setScale(scale * maxTitleW / title.width);
		var alpha:Float = selected ? 1 : 0.55;

		title.visible = title.active = true;
		title.alpha = alpha;
		title.x = x;
		title.y = y - title.height * 0.5;

		icon.visible = icon.active = true;
		icon.alpha = alpha;
		icon.x = title.x + title.width + 14;
		icon.y = y - icon.height * 0.5;

		var fav:Bool = library.isFavorite(entry);
		star.visible = star.active = fav;
		if (fav) {
			star.alpha = alpha;
			star.x = title.x - star.width * 0.55;
			star.y = title.y - star.height * 0.30;
		}

		rowX = x;
		rowY = y - FreeplayListView.ROW_STEP * 0.5;
		rowW = maxW;
		rowH = FreeplayListView.ROW_STEP;
	}

	public inline function contains(mx:Float, my:Float):Bool
		return mx >= rowX && mx <= rowX + rowW && my >= rowY && my <= rowY + rowH;

	public function hide():Void {
		if (!shown)
			return;
		shown = false;
		title.visible = title.active = false;
		icon.visible = icon.active = false;
		star.visible = star.active = false;
	}
}
