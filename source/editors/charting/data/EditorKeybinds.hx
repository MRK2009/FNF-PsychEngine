package editors.charting.data;

import flixel.FlxG;
import flixel.input.keyboard.FlxKey;

/** One binding: a key (`FlxKey` code, or `MOUSE_LEFT`/`MOUSE_RIGHT`/`MOUSE_MIDDLE`) + exact modifiers. **/
typedef EditorBind = {
	var key:Int;
	var ctrl:Bool;
	var shift:Bool;
	var alt:Bool;
}

/** One rebindable editor action: identity, display label, group and up to two active binds. **/
final class EditorAction {
	/** Stable identifier used by `justPressed`/`bindLabel`. **/
	public final id:String;

	/** Human-readable name shown in the keybinds panel. **/
	public final label:String;

	/** Panel grouping ("Playback", "Navigation", ...). **/
	public final group:String;

	/** The factory-default binds (used by `resetAll`). **/
	public final defaults:Array<EditorBind>;

	/** The live binds (up to two slots). **/
	public var binds:Array<EditorBind>;

	/**
		@param id stable identifier
		@param label display name
		@param group panel grouping
		@param defaults the default binds (copied into `binds`)
	**/
	public function new(id:String, label:String, group:String, defaults:Array<EditorBind>) {
		this.id = id;
		this.label = label;
		this.group = group;
		this.defaults = defaults;
		this.binds = defaults.copy();
	}
}

/**
	The rebindable editor shortcut map. EVERY editor action is a named action here - menus,
	toolbar tooltips and the keybinds panel all read the live bind through `bindLabel` (single
	source of truth). Binds persist in `FlxG.save.data.chartEditorBinds`. Mouse buttons are
	bindable via the negative pseudo-keys.

	Modifier matching is EXACT: `S` won't fire while Ctrl is held, so `Ctrl+S` stays unambiguous.
**/
final class EditorKeybinds {
	/** Pseudo-key code for the left mouse button. **/
	public static inline var MOUSE_LEFT:Int = -1;

	/** Pseudo-key code for the right mouse button. **/
	public static inline var MOUSE_RIGHT:Int = -2;

	/** Pseudo-key code for the middle mouse button. **/
	public static inline var MOUSE_MIDDLE:Int = -3;

	/** Ordered for the keybinds panel. **/
	public static final actions:Array<EditorAction> = [];

	static final byId:Map<String, EditorAction> = new Map();
	static var initialized:Bool = false;

	static inline function mk(key:Int, ctrl:Bool = false, shift:Bool = false, alt:Bool = false):EditorBind {
		return {
			key: key,
			ctrl: ctrl,
			shift: shift,
			alt: alt
		};
	}

	static function action(id:String, label:String, group:String, defaults:Array<EditorBind>):Void {
		var a:EditorAction = new EditorAction(id, label, group, defaults);
		actions.push(a);
		byId.set(id, a);
	}

	/** Builds the action registry (idempotent) and loads saved binds. **/
	public static function init():Void {
		if (initialized)
			return;
		initialized = true;

		action('play_pause', 'Play / Pause', 'Playback', [mk(FlxKey.SPACE)]);
		action('playtest', 'Playtest', 'Playback', [mk(FlxKey.ENTER)]);
		action('preview', 'Preview', 'Playback', [mk(FlxKey.F12)]);
		action('reset_section', 'Reset to Section Start', 'Playback', [mk(FlxKey.R)]);
		action('rate_down', 'Playback Rate Down', 'Playback', [mk(FlxKey.LBRACKET)]);
		action('rate_up', 'Playback Rate Up', 'Playback', [mk(FlxKey.RBRACKET)]);

		action('section_prev', 'Previous Section', 'Navigation', [mk(FlxKey.A)]);
		action('section_next', 'Next Section', 'Navigation', [mk(FlxKey.D)]);
		action('step_up', 'Scroll Up', 'Navigation', [mk(FlxKey.W)]);
		action('step_down', 'Scroll Down', 'Navigation', [mk(FlxKey.S)]);
		action('snap_prev', 'Snap Coarser', 'Navigation', [mk(FlxKey.LEFT)]);
		action('snap_next', 'Snap Finer', 'Navigation', [mk(FlxKey.RIGHT)]);
		action('zoom_out', 'Zoom Out', 'Navigation', [mk(FlxKey.Z)]);
		action('zoom_in', 'Zoom In', 'Navigation', [mk(FlxKey.X)]);
		action('goto_start', 'Go to Start', 'Navigation', [mk(FlxKey.HOME)]);
		action('goto_end', 'Go to End', 'Navigation', [mk(FlxKey.END)]);
		action('go_to', 'Go to...', 'Navigation', [mk(FlxKey.G, true)]);

		action('undo', 'Undo', 'Editing', [mk(FlxKey.Z, true)]);
		action('redo', 'Redo', 'Editing', [mk(FlxKey.Y, true)]);
		action('cut', 'Cut', 'Editing', [mk(FlxKey.X, true)]);
		action('copy', 'Copy', 'Editing', [mk(FlxKey.C, true)]);
		action('paste', 'Paste', 'Editing', [mk(FlxKey.V, true)]);
		action('select_all', 'Select All', 'Editing', [mk(FlxKey.A, true)]);
		action('delete', 'Delete Selection', 'Editing', [mk(FlxKey.DELETE)]);
		action('sustain_shrink', 'Shrink Sustain', 'Editing', [mk(FlxKey.Q)]);
		action('sustain_grow', 'Grow Sustain', 'Editing', [mk(FlxKey.E)]);

		action('note_place', 'Place / Remove Note', 'Mouse', [mk(MOUSE_LEFT)]);
		action('note_context', 'Note Context Menu', 'Mouse', [mk(MOUSE_RIGHT)]);

		action('save', 'Save', 'File', [mk(FlxKey.S, true)]);
		action('save_as', 'Save As...', 'File', [mk(FlxKey.S, true, true)]);
		action('open', 'Open...', 'File', [mk(FlxKey.O, true)]);
		action('new_chart', 'New Chart', 'File', [mk(FlxKey.N, true)]);
		action('search', 'Search', 'File', [mk(FlxKey.K, true)]);
		action('help', 'Help', 'File', [mk(FlxKey.F1)]);

		var vk:Array<Int> = [
			FlxKey.ONE,
			FlxKey.TWO,
			FlxKey.THREE,
			FlxKey.FOUR,
			FlxKey.FIVE,
			FlxKey.SIX,
			FlxKey.SEVEN,
			FlxKey.EIGHT
		];
		var i:Int = 0;
		while (i < 8) {
			action('vortex_${i + 1}', 'Vortex Lane ${i + 1}', 'Vortex', [mk(vk[i])]);
			i++;
		}

		loadBinds();
	}

	/** `true` the frame any of the action's binds is pressed (exact modifier match). **/
	public static function justPressed(id:String):Bool {
		return check(id, true);
	}

	/** `true` while any of the action's binds is held. **/
	public static function pressed(id:String):Bool {
		return check(id, false);
	}

	/** Shared matcher: exact modifier state, keyboard status or mouse pseudo-keys. **/
	static function check(id:String, just:Bool):Bool {
		var a:EditorAction = byId.get(id);
		if (a == null)
			return false;
		var ctrl:Bool = FlxG.keys.pressed.CONTROL;
		var shift:Bool = FlxG.keys.pressed.SHIFT;
		var alt:Bool = FlxG.keys.pressed.ALT;
		var i:Int = 0;
		var n:Int = a.binds.length;
		while (i < n) {
			var b:EditorBind = a.binds[i];
			i++;
			if (b.key == 0 || b.ctrl != ctrl || b.shift != shift || b.alt != alt)
				continue;
			if (b.key < 0) {
				switch (b.key) {
					case MOUSE_LEFT:
						if (just ? FlxG.mouse.justPressed : FlxG.mouse.pressed)
							return true;
					case MOUSE_RIGHT:
						if (just ? FlxG.mouse.justPressedRight : FlxG.mouse.pressedRight)
							return true;
					case MOUSE_MIDDLE:
						if (just ? FlxG.mouse.justPressedMiddle : FlxG.mouse.pressedMiddle)
							return true;
				}
			} else if (FlxG.keys.checkStatus(b.key, just ? JUST_PRESSED : PRESSED))
				return true;
		}
		return false;
	}

	/**
		Human label of the action's primary bind.
		@param id the action identifier
		@return e.g. "Ctrl+S", "Space", "RMB"; "" when unbound
	**/
	public static function bindLabel(id:String):String {
		var a:EditorAction = byId.get(id);
		if (a == null || a.binds.length == 0)
			return "";
		return describeBind(a.binds[0]);
	}

	/**
		Human label for a single bind (modifiers + key/mouse name).
		@param b the bind
		@return the label, or "" for `null`/unbound
	**/
	public static function describeBind(b:EditorBind):String {
		if (b == null || b.key == 0)
			return "";
		var out:String = "";
		if (b.ctrl)
			out += "Ctrl+";
		if (b.shift)
			out += "Shift+";
		if (b.alt)
			out += "Alt+";
		return out + keyName(b.key);
	}

	/** Display name for a key code (mouse pseudo-keys included, names title-cased). **/
	static function keyName(key:Int):String {
		switch (key) {
			case MOUSE_LEFT:
				return "LMB";
			case MOUSE_RIGHT:
				return "RMB";
			case MOUSE_MIDDLE:
				return "MMB";
		}
		var name:String = FlxKey.toStringMap.get(key);
		if (name == null)
			return "?";
		if (name.length > 1)
			return name.charAt(0) + name.substr(1).toLowerCase();
		return name;
	}

	/** Replaces one bind slot and persists. `bind = null` clears the slot. **/
	public static function rebind(id:String, slot:Int, bind:EditorBind):Void {
		var a:EditorAction = byId.get(id);
		if (a == null)
			return;
		while (a.binds.length <= slot)
			a.binds.push(mk(0));
		a.binds[slot] = (bind != null) ? bind : mk(0);
		saveBinds();
	}

	/** Restores every action's default binds and persists. **/
	public static function resetAll():Void {
		for (a in actions)
			a.binds = a.defaults.copy();
		saveBinds();
	}

	/** Persists binds as `{id, b:[[key, modMask]]}` entries (mask: 1=ctrl 2=shift 4=alt). **/
	static function saveBinds():Void {
		var out:Array<Dynamic> = [];
		for (a in actions) {
			var packed:Array<Array<Int>> = [];
			for (b in a.binds)
				packed.push([b.key, (b.ctrl ? 1 : 0) | (b.shift ? 2 : 0) | (b.alt ? 4 : 0)]);
			out.push({id: a.id, b: packed});
		}
		FlxG.save.data.chartEditorBinds = out;
		FlxG.save.flush();
	}

	/** Restores persisted binds onto matching actions (unknown ids are ignored). **/
	static function loadBinds():Void {
		var saved:Array<Dynamic> = FlxG.save.data.chartEditorBinds;
		if (saved == null)
			return;
		for (entry in saved) {
			var a:EditorAction = byId.get(entry.id);
			if (a == null)
				continue;
			var packed:Array<Dynamic> = entry.b;
			if (packed == null)
				continue;
			var binds:Array<EditorBind> = [];
			for (p in packed) {
				var arr:Array<Dynamic> = p;
				var key:Int = Std.int(arr[0]);
				var mods:Int = (arr.length > 1) ? Std.int(arr[1]) : 0;
				binds.push({
					key: key,
					ctrl: (mods & 1) != 0,
					shift: (mods & 2) != 0,
					alt: (mods & 4) != 0
				});
			}
			if (binds.length > 0)
				a.binds = binds;
		}
	}
}
