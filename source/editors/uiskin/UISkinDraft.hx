package editors.uiskin;

import backend.UISkinConfig;
import backend.UISkinConfig.UISkinData;
import backend.UISkinConfig.UIJudgement;
import backend.config.UiTcfgWriter;

using StringTools;

/**
	The UI skin being edited: the config, where it came from, and whether it has unsaved changes.

	Mirrors `editors.noteskin.NoteSkinDraft`. Keeping this off the editor state is what makes the
	dirty marker, the unsaved-changes prompt, Duplicate and Reload possible -- the previous editor
	mutated `UISkinConfig`'s cached data in place, so there was nothing to be dirty ABOUT.

	The engine's own writer (`backend.config.UiTcfgWriter`) does the serialising, so what the editor
	saves is what the loader reads back.
**/
class UISkinDraft {
	/** Full skin name, e.g. `uiSkins/MySkin`. **/
	public var name:String;

	/** The edited config. **/
	public var config:UISkinData;

	/** Unsaved changes since the last load/save. **/
	public var dirty:Bool = false;

	/** The on-disk folder this skin came from, or where it would be written. **/
	public var dir:String = null;

	/** `true` when it lives in the shipped assets, which the editor must not write over. **/
	public var fromBase:Bool = false;

	public function new() {}

	/** The last path segment (`uiSkins/MySkin` -> `MySkin`). **/
	public inline function shortName():String
		return name == null ? '' : name.substr(name.lastIndexOf('/') + 1);

	public inline function touch():Void
		dirty = true;

	/**
		Binds this draft to an existing skin on disk.
		@param skinName the full skin name (`uiSkins/X`)
	**/
	public function load(skinName:String):Void {
		name = skinName;
		var loaded:UISkinData = UISkinConfig.get(skinName);
		// No config on disk means this is not a skin yet; show the defaults so every field has
		// something in it and saving writes the skin.tcfg that makes it one.
		config = (loaded != null) ? loaded : defaultConfig();
		dirty = false;
		resolveDir();
	}

	/** Locates the on-disk directory this skin came from, and whether it is a read-only base skin. **/
	function resolveDir():Void {
		fromBase = false;
		dir = null;
		#if sys
		var basePath:String = 'assets/shared/images/$name';
		if (skinFileExists(basePath) || sys.FileSystem.exists(basePath)) {
			dir = basePath;
			fromBase = true;
		}
		#if MODS_ALLOWED
		if (dir == null) {
			for (root in modRoots()) {
				var p:String = (root.length > 0) ? 'mods/$root/images/$name' : 'mods/images/$name';
				if (skinFileExists(p) || sys.FileSystem.exists(p)) {
					dir = p;
					break;
				}
			}
		}
		#end
		if (dir == null)
			dir = targetDir(shortName());
		#end
	}

	/**
		Where a skin named `short` should be written: the current mod when one is selected, else the
		bare `mods/` root (which is always scanned).
		@param short the skin's folder name
	**/
	public static function targetDir(short:String):String {
		#if MODS_ALLOWED
		var mod:String = Mods.currentModDirectory;
		if (mod != null && mod.length > 0)
			return 'mods/$mod/images/uiSkins/$short';
		#end
		return 'mods/images/uiSkins/$short';
	}

	#if (sys && MODS_ALLOWED)
	static function modRoots():Array<String> {
		var roots:Array<String> = [];
		if (Mods.currentModDirectory != null && Mods.currentModDirectory.length > 0)
			roots.push(Mods.currentModDirectory);
		roots.push('');
		for (m in Mods.parseList().enabled)
			if (!roots.contains(m))
				roots.push(m);
		return roots;
	}
	#end

	public static inline function skinFileExists(dir:String):Bool {
		#if sys
		return sys.FileSystem.exists('$dir/skin.tcfg') || sys.FileSystem.exists('$dir/skin.json');
		#else
		return false;
		#end
	}

	/**
		A skin name that isn't taken yet, by suffixing a counter onto `base`. Prefilling the New Skin
		dialog with a FREE name stops the dead-end where the default name already exists and Create
		silently refuses.
		@param base the preferred name
		@return `base`, or `base2` / `base3` / ... for the first free one
	**/
	public static function suggestName(base:String):String {
		if (!nameTaken(base))
			return base;
		var i:Int = 2;
		while (i < 1000) {
			if (!nameTaken(base + i))
				return base + i;
			i++;
		}
		return base + Std.random(100000);
	}

	/** Whether a skin folder name is already taken anywhere the engine would find it. **/
	public static function nameTaken(short:String):Bool {
		#if sys
		if (sys.FileSystem.exists(targetDir(short)))
			return true;
		return UISkinConfig.list().contains('uiSkins/$short');
		#else
		return false;
		#end
	}

	public static function ensureDir(path:String):Void {
		#if sys
		var cur:String = '';
		for (p in path.split('/')) {
			if (p.length < 1)
				continue;
			cur += (cur.length > 0 ? '/' : '') + p;
			if (!sys.FileSystem.exists(cur))
				sys.FileSystem.createDirectory(cur);
		}
		#end
	}

	/** A blank config for a new skin: the vanilla element names, so a fresh skin renders immediately. **/
	public static function defaultConfig():UISkinData {
		return {
			combo: 'combo',
			num: 'num',
			ready: 'ready',
			set: 'set',
			go: 'go',
			antialiasing: true,
			ratings: {sick: 'sick', good: 'good', bad: 'bad', shit: 'shit'},
			tween: {duration: 0.2, ease: 'linear'},
			judgements: {}
		};
	}

	/** The `judgements` map as a list, for the editor's tier table. **/
	public function judgementList():Array<UIJudgement> {
		var out:Array<UIJudgement> = [];
		if (config == null || config.judgements == null)
			return out;
		for (key in Reflect.fields(config.judgements)) {
			var node:Dynamic = Reflect.field(config.judgements, key);
			if (node == null)
				continue;
			out.push({
				name: key,
				image: (Reflect.hasField(node, 'image')) ? Std.string(Reflect.field(node, 'image')) : key,
				window: (Reflect.hasField(node, 'window')) ? Std.parseFloat(Std.string(Reflect.field(node, 'window'))) : 0,
				sound: (Reflect.hasField(node, 'sound')) ? Std.string(Reflect.field(node, 'sound')) : null,
				splash: (Reflect.hasField(node, 'splash')) ? Reflect.field(node, 'splash') == true : null,
				antialias: (Reflect.hasField(node, 'antialias')) ? Reflect.field(node, 'antialias') == true : null,
				scale: (Reflect.hasField(node, 'scale')) ? Std.parseFloat(Std.string(Reflect.field(node, 'scale'))) : null
			});
		}
		out.sort(function(a, b) return a.window < b.window ? -1 : (a.window > b.window ? 1 : 0));
		return out;
	}

	/**
		Writes the draft to disk.
		@return an error message, or null on success
	**/
	public function save():String {
		#if sys
		if (fromBase)
			return 'This is a base-game skin -- use Duplicate first';
		if (dir == null)
			dir = targetDir(shortName());
		try {
			ensureDir(dir);
			sys.io.File.saveContent('$dir/skin.tcfg', UiTcfgWriter.write(config));
			dirty = false;
			return null;
		} catch (e:Dynamic)
			return Std.string(e);
		#else
		return 'Saving needs a desktop build';
		#end
	}

	/**
		Copies this skin's whole folder to a new name (in the current mod) and rebinds the draft to it.
		This is how a read-only base skin becomes editable.
		@param short the new folder name
		@return an error message, or null on success
	**/
	public function duplicate(short:String):String {
		#if sys
		var dest:String = targetDir(short);
		try {
			ensureDir(dest);
			if (dir != null && sys.FileSystem.exists(dir) && sys.FileSystem.isDirectory(dir))
				copyDir(dir, dest);
			sys.io.File.saveContent('$dest/skin.tcfg', UiTcfgWriter.write(config));
			name = 'uiSkins/$short';
			dir = dest;
			fromBase = false;
			dirty = false;
			return null;
		} catch (e:Dynamic)
			return Std.string(e);
		#else
		return 'Saving needs a desktop build';
		#end
	}

	#if sys
	static function copyDir(from:String, to:String):Void {
		ensureDir(to);
		for (entry in sys.FileSystem.readDirectory(from)) {
			var src:String = '$from/$entry';
			var dst:String = '$to/$entry';
			if (sys.FileSystem.isDirectory(src))
				copyDir(src, dst);
			else
				sys.io.File.copy(src, dst);
		}
	}
	#end
}
