package states.freeplay;

import smidr.widgets.UIModal;
import smidr.widgets.UILabel;
import smidr.widgets.UIButton;
import smidr.widgets.UITextInput;
import smidr.widgets.UIScrollPane;
import smidr.widgets.UISeparator;
import backend.profiles.ProfileManager;
import backend.profiles.ProfileManager.ProfileData;

/**
 * The Freeplay profile window: a Smidr modal (dimmed backdrop, Escape/backdrop closes) holding one
 * scrollable pane with the active profile's total stats -- plays, keypresses, playtime, average
 * accuracy, recorded scores, grade tallies and the Etterna-style skill spread (always graded from
 * Wife3-at-J4 results) -- followed by profile switching, creation and renaming. Opened from the
 * top bar's profile chip; rebuilt fresh on every open (the modal disposes itself on close). Each
 * inactive profile row carries a delete button (the last remaining profile can't be deleted).
 */
class FreeplayProfilePanel {
	static inline final W:Float = 480;
	static inline final H:Float = 560;
	static inline final PAD:Float = 16;
	static inline final ROW_H:Float = 32;
	static final SKILL_NAMES:Array<String> = ['Overall', 'Stream', 'Jumpstream', 'Handstream', 'Stamina', 'JackSpeed', 'Chordjack', 'Technical'];

	var onChanged:Void->Void;
	var modal:UIModal = null;
	var pane:UIScrollPane = null;
	var nameInput:UITextInput = null;

	/**
	 * @param onChanged fired after the active profile switched or changed name
	 */
	public function new(onChanged:Void->Void) {
		this.onChanged = onChanged;
	}

	/** Whether the modal is currently open. */
	public var visible(get, never):Bool;

	function get_visible():Bool
		return modal != null;

	/** Opens the modal (or closes it when already open). */
	public function toggle():Void {
		if (modal != null)
			modal.close();
		else
			open();
	}

	/** Builds and opens the modal for the active profile. */
	public function open():Void {
		var p:ProfileData = ProfileManager.active();
		modal = new UIModal(p.name, W, H);
		modal.onClosed = () -> {
			modal = null;
			pane = null;
			nameInput = null;
		};

		pane = new UIScrollPane(W - PAD * 2, H - 48 - PAD);
		pane.x = PAD;
		pane.y = 4;
		modal.body.addChild(pane);

		fillPane(p);
		modal.open();
	}

	/** Rebuilds the scrollable content (called on open and after any profile change). */
	function refresh():Void {
		if (modal == null)
			return;
		var p:ProfileData = ProfileManager.active();
		modal.titleText = p.name;
		while (pane.content.numChildren > 0)
			pane.content.removeChildAt(0);
		fillPane(p);
	}

	/**
	 * Fills the scroll pane with the profile's stats and the profile-management controls.
	 * @param p the active profile
	 */
	function fillPane(p:ProfileData):Void {
		var innerW:Float = W - PAD * 2 - 14;
		var cy:Float = 4;

		cy = label('TOTAL STATS', 11, 2, cy) + 4;
		var hours:Int = Std.int(p.playtimeSec / 3600);
		var mins:Int = Std.int((p.playtimeSec - hours * 3600) / 60);
		var lines:Array<String> = [];
		lines.push(rpad('Plays', 16) + p.totalPlays);
		lines.push(rpad('Keypresses', 16) + p.totalKeypresses);
		lines.push(rpad('Playtime', 16) + hours + 'h ' + mins + 'm');
		lines.push(rpad('Avg Accuracy', 16) + fmt2(ProfileManager.averageAccuracy() * 100) + '%');
		lines.push(rpad('Scores', 16) + ProfileManager.scores().recordCount());
		lines.push(rpad('Created', 16) + DateTools.format(Date.fromTime(p.createdSec * 1000), '%Y-%m-%d'));
		cy = multiline(lines.join('\n'), 14, 1, cy, innerW) + 12;

		var grades:Array<String> = [];
		for (g in p.gradeCounts.keys())
			grades.push(rpad(g, 16) + p.gradeCounts.get(g));
		if (grades.length > 0) {
			cy = label('GRADES', 11, 2, cy) + 4;
			cy = multiline(grades.join('\n'), 14, 1, cy, innerW) + 12;
		}

		cy = label('SKILLS (Wife3 @ J4)', 11, 2, cy) + 4;
		var sk:Array<String> = [];
		for (i in 0...SKILL_NAMES.length) {
			var v:Float = (p.skills != null && i < p.skills.length) ? p.skills[i] : 0;
			sk.push(rpad(SKILL_NAMES[i], 16) + fmt2(v));
		}
		cy = multiline(sk.join('\n'), 14, 1, cy, innerW) + 12;

		var sep:UISeparator = new UISeparator(innerW);
		sep.x = 0;
		sep.y = cy;
		pane.content.addChild(sep);
		cy += 10;

		cy = label('PROFILES', 11, 2, cy) + 4;
		var multiple:Bool = ProfileManager.all().length > 1;
		var delW:Float = 34;
		for (prof in ProfileManager.all()) {
			var id:Int = prof.id;
			var isActive:Bool = prof.id == p.id;
			var caption:String = prof.name + (isActive ? '   (active)' : '');
			// The last remaining profile can't be deleted, so it keeps the full row width.
			var rowW:Float = multiple ? (innerW - delW - 6) : innerW;
			var b:UIButton = new UIButton(caption, rowW, ROW_H - 4, () -> {
				ProfileManager.setActive(id);
				refresh();
				if (onChanged != null)
					onChanged();
			}, isActive);
			b.x = 0;
			b.y = cy;
			pane.content.addChild(b);

			if (multiple) {
				var del:UIButton = new UIButton('X', delW, ROW_H - 4, () -> deleteProfile(id));
				del.x = rowW + 6;
				del.y = cy;
				pane.content.addChild(del);
			}
			cy += ROW_H;
		}
		cy += 6;

		nameInput = new UITextInput('', innerW - 200, '', null);
		nameInput.x = 0;
		nameInput.y = cy;
		pane.content.addChild(nameInput);
		var createBtn:UIButton = new UIButton('New', 92, 30, createProfile);
		createBtn.x = innerW - 92 * 2 - 8;
		createBtn.y = cy;
		pane.content.addChild(createBtn);
		var renameBtn:UIButton = new UIButton('Rename', 92, 30, renameProfile);
		renameBtn.x = innerW - 92;
		renameBtn.y = cy;
		pane.content.addChild(renameBtn);
		cy += 40;

		pane.refreshContent(cy);
	}

	/**
	 * Adds one single-line label to the pane content.
	 * @param text the text
	 * @param size the font size
	 * @param tone the theme tone
	 * @param cy the label's top
	 * @return the y below the label
	 */
	function label(text:String, size:Int, tone:Int, cy:Float):Float {
		var l:UILabel = new UILabel(text, size, tone);
		var h:Float = l.measure();
		l.x = 0;
		l.y = cy;
		pane.content.addChild(l);
		return cy + h;
	}

	/**
	 * Adds a wrapped multi-line label to the pane content.
	 * @param text the text
	 * @param size the font size
	 * @param tone the theme tone
	 * @param cy the label's top
	 * @param wrapW the wrap width
	 * @return the y below the measured label
	 */
	function multiline(text:String, size:Int, tone:Int, cy:Float, wrapW:Float):Float {
		var l:UILabel = new UILabel(text, size, tone);
		l.wrapWidth = wrapW;
		var h:Float = l.measure();
		l.x = 0;
		l.y = cy;
		pane.content.addChild(l);
		return cy + h;
	}

	/** Creates a profile from the name input and switches to it. */
	function createProfile():Void {
		var name:String = StringTools.trim(nameInput.text);
		if (name.length == 0)
			return;
		var p:ProfileData = ProfileManager.create(name);
		ProfileManager.setActive(p.id);
		refresh();
		if (onChanged != null)
			onChanged();
	}

	/**
	 * Deletes a profile (switching active if needed) and rebuilds the pane.
	 * @param id the profile id to delete
	 */
	function deleteProfile(id:Int):Void {
		if (!ProfileManager.delete(id))
			return;
		refresh();
		if (onChanged != null)
			onChanged();
	}

	/** Renames the active profile from the name input. */
	function renameProfile():Void {
		var name:String = StringTools.trim(nameInput.text);
		if (name.length == 0)
			return;
		ProfileManager.rename(ProfileManager.active().id, name);
		refresh();
		if (onChanged != null)
			onChanged();
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
}
