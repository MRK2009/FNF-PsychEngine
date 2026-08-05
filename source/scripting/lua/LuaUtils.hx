package scripting.lua;

import hxluajit.Lua;
import flixel.FlxBasic;
import flixel.group.FlxGroup.FlxTypedGroup;
import flixel.group.FlxSpriteGroup;
import backend.WeekData;
import objects.Character;
import backend.StageData;
import openfl.display.BlendMode;
import Type.ValueType;
import substates.GameOverSubstate;

typedef LuaTweenOptions = {
	type:FlxTweenType,
	startDelay:Float,
	onUpdate:Null<String>,
	onStart:Null<String>,
	onComplete:Null<String>,
	loopDelay:Float,
	ease:EaseFunction
}

class LuaUtils {
	public static final Function_Stop:String = "##PSYCHLUA_FUNCTIONSTOP";
	public static final Function_Continue:String = "##PSYCHLUA_FUNCTIONCONTINUE";
	public static final Function_StopLua:String = "##PSYCHLUA_FUNCTIONSTOPLUA";
	public static final Function_StopHScript:String = "##PSYCHLUA_FUNCTIONSTOPHSCRIPT";
	public static final Function_StopAll:String = "##PSYCHLUA_FUNCTIONSTOPALL";

	/** An ordinary return value. **/
	public static inline var CONTROL_NONE:Int = 0;

	/** `Function_Continue`: nothing to say. Never becomes a hook's result. **/
	public static inline var CONTROL_CONTINUE:Int = 1;

	/**
		`Function_Stop`: cancel the engine's default action, and skip the OTHER language's pass.

		Deliberately not the same as `CONTROL_STOP_ALL`: the remaining scripts in the language that
		returned it still get the hook. `return Function_Stop` is the standard way to cancel a note
		hit, and a mod that cancels one must not stop a sibling script from counting it.
	**/
	public static inline var CONTROL_STOP:Int = 2;

	/** `Function_StopLua`: stop the Lua pass. The HScript pass still runs. **/
	public static inline var CONTROL_STOP_LUA:Int = 3;

	/** `Function_StopHScript`: stop the HScript pass. The Lua pass still runs. **/
	public static inline var CONTROL_STOP_HSCRIPT:Int = 4;

	/** `Function_StopAll`: stop both passes. **/
	public static inline var CONTROL_STOP_ALL:Int = 5;

	/**
		Classifies a hook's return value, so dispatch compares Ints instead of running the five
		string comparisons per script per hook -- `onUpdate` and `onUpdatePost` alone do that for
		every script sixty times a second.

		The script-facing constants stay STRINGS deliberately. Making them numbers would put a
		`Dynamic` Int-vs-Float comparison on the Lua return boundary, a coercion this codebase has
		already been bitten by on hxcpp, and the saving is entirely internal to the dispatcher.

		@param value Whatever the script handed back.
		@return One of the `CONTROL_*` codes; `CONTROL_NONE` for an ordinary value.
	**/
	public static function controlOf(value:Dynamic):Int {
		if (value == null || !(value is String))
			return CONTROL_NONE;

		var text:String = cast value;
		if (text.length < 2 || text.charCodeAt(0) != 35)
			return CONTROL_NONE;

		if (text == Function_Continue)
			return CONTROL_CONTINUE;
		if (text == Function_Stop)
			return CONTROL_STOP;
		if (text == Function_StopLua)
			return CONTROL_STOP_LUA;
		if (text == Function_StopHScript)
			return CONTROL_STOP_HSCRIPT;
		if (text == Function_StopAll)
			return CONTROL_STOP_ALL;

		return CONTROL_NONE;
	}

	/**
		Coerces a script-supplied colour into an `FlxColor`. Accepts an int/`FlxColor` (returned as-is),
		or a string -- a hex like `"FF0000"`/`"#FF0000"` or a named colour (`"red"`), via `FlxColor.fromString`.
		@param value the raw colour from Lua/HScript
		@return the resolved `FlxColor` (`FlxColor.WHITE` when a string can't be parsed)
	**/
	public static function getColor(value:Dynamic):FlxColor {
		if (value == null)
			return FlxColor.WHITE;
		if (Std.isOfType(value, String)) {
			var str:String = cast value;
			// Bare hex (e.g. "FF0000"/"FF0000FF") needs a '#' before FlxColor.fromString will read it;
			// prefixed hex ("#..."/"0x...") and named colours ("red") are passed through untouched.
			if (str.length > 0 && str.charAt(0) != '#' && str.substr(0, 2) != '0x'
				&& ~/^[A-Fa-f0-9]{6}([A-Fa-f0-9]{2})?$/.match(str))
				str = '#' + str;
			var parsed:Null<FlxColor> = FlxColor.fromString(str);
			return (parsed != null) ? parsed : FlxColor.WHITE;
		}
		return Std.int(value);
	}

	public static function getLuaTween(options:Dynamic) {
		return (options != null) ? {
			type: getTweenTypeByString(options.type),
			startDelay: options.startDelay,
			onUpdate: options.onUpdate,
			onStart: options.onStart,
			onComplete: options.onComplete,
			loopDelay: options.loopDelay,
			ease: getTweenEaseByString(options.ease)
		} : null;
	}

	/**
		Writes one member of `instance`, which may carry `[...]` indexes.

		`allowMaps` no longer gates map access -- `PropertyPath` treats map content as the fallback
		for a key that is not a real field, the same rule the direct proxy uses. It stays in the
		signature so no script or call site changes.
	**/
	public static inline function setVarInArray(instance:Dynamic, variable:String, value:Dynamic, allowMaps:Bool = false):Any
		return PropertyPath.set(instance, variable, value, allowMaps);

	/** Reads one member of `instance`, which may carry `[...]` indexes. See `setVarInArray`. **/
	public static inline function getVarInArray(instance:Dynamic, variable:String, allowMaps:Bool = false):Any
		return PropertyPath.get(instance, variable, allowMaps);

	public static function getModSetting(saveTag:String, ?modName:String = null) {
		#if MODS_ALLOWED
		if (FlxG.save.data.modSettings == null)
			FlxG.save.data.modSettings = new Map<String, Dynamic>();

		var settings:Map<String, Dynamic> = FlxG.save.data.modSettings.get(modName);
		var path:String = Paths.mods('$modName/data/settings.json');
		if (FileSystem.exists(path)) {
			if (settings == null || !settings.exists(saveTag)) {
				if (settings == null)
					settings = new Map<String, Dynamic>();
				var data:String = File.getContent(path);
				try {
					// FunkinLua.luaTrace('getModSetting: Trying to find default value for "$saveTag" in Mod: "$modName"');
					var parsedJson:Dynamic = CoolUtil.parseJson(data);
					if (!Std.isOfType(parsedJson, Array)) {
						// settings.json must be a JSON array of option entries;
						// the previous code blindly read .length and looped,
						// which silently no-op'd (or crashed on hxcpp) for the
						// `{...}`-rooted case.
						throw 'mods/$modName/data/settings.json root is not a JSON array';
					}
					var arr:Array<Dynamic> = cast parsedJson;
					for (i in 0...arr.length) {
						var sub:Dynamic = arr[i];
						if (sub != null && sub.save != null && !settings.exists(sub.save)) {
							if (sub.type != 'keybind' && sub.type != 'key') {
								if (sub.value != null) {
									// FunkinLua.luaTrace('getModSetting: Found unsaved value "${sub.save}" in Mod: "$modName"');
									settings.set(sub.save, sub.value);
								}
							} else {
								// FunkinLua.luaTrace('getModSetting: Found unsaved keybind "${sub.save}" in Mod: "$modName"');
								settings.set(sub.save,
									{keyboard: (sub.keyboard != null ? sub.keyboard : 'NONE'), gamepad: (sub.gamepad != null ? sub.gamepad : 'NONE')});
							}
						}
					}
					FlxG.save.data.modSettings.set(modName, settings);
				} catch (e:Dynamic) {
					var errorTitle = 'Mod name: ' + Mods.currentModDirectory;
					var errorMsg = 'An error occurred: $e';
					#if windows
					lime.app.Application.current.window.alert(errorMsg, errorTitle);
					#end
					trace('$errorTitle - $errorMsg');
				}
			}
		} else {
			FlxG.save.data.modSettings.remove(modName);
			#if (LUA_ALLOWED || HSCRIPT_ALLOWED)
			PlayState.instance.addTextToDebug('getModSetting: $path could not be found!', FlxColor.RED);
			#else
			FlxG.log.warn('getModSetting: $path could not be found!');
			#end
			return null;
		}

		if (settings.exists(saveTag))
			return settings.get(saveTag);
		#if (LUA_ALLOWED || HSCRIPT_ALLOWED)
		PlayState.instance.addTextToDebug('getModSetting: "$saveTag" could not be found inside $modName\'s settings!', FlxColor.RED);
		#else
		FlxG.log.warn('getModSetting: "$saveTag" could not be found inside $modName\'s settings!');
		#end
		#end
		return null;
	}

	public static function isMap(variable:Dynamic) {
		/*switch(Type.typeof(variable)){
			case ValueType.TClass(haxe.ds.StringMap) | ValueType.TClass(haxe.ds.ObjectMap) | ValueType.TClass(haxe.ds.IntMap) | ValueType.TClass(haxe.ds.EnumValueMap):
				return true;
			default:
				return false;
		}*/

		// trace(variable);
		if (variable == null) return false;
		if (variable.exists != null && variable.keyValueIterator != null)
			return true;
		return false;
	}

	/**
		Writes a path on one member of a group.

		Lenient: old/compat scripts often poke note/strum properties that were renamed or removed
		(e.g. `noteSplashHue`). A failed set must not throw and abort the rest of the caller's loop,
		so the remaining items still get processed.
	**/
	public static function setGroupStuff(leArray:Dynamic, variable:String, value:Dynamic, ?allowMaps:Bool = false) {
		try {
			PropertyPath.set(leArray, variable, value, allowMaps);
		} catch (e:Dynamic) {}
		return value;
	}

	/** Reads a path on one member of a group. **/
	public static inline function getGroupStuff(leArray:Dynamic, variable:String, ?allowMaps:Bool = false)
		return PropertyPath.get(leArray, variable, allowMaps);

	/**
		Resolves a script group path to a live `NoteField` (`game.playerField`, `opponentField`,
		or either with a `.notes`/`.active` suffix), so note-group Lua calls can target the
		field's spawned notes natively. Returns `null` for non-field paths.
	**/
	public static function resolveNoteField(group:String):objects.notes.NoteField {
		var split:Array<String> = group.split('.');
		var last:String = split[split.length - 1];
		if (split.length > 1 && (last == 'notes' || last == 'active'))
			split.pop();
		var resolved:Dynamic = (split.length > 1) ? getPropertyLoop(split, false) : getObjectDirectly(split[0]);
		return (resolved is objects.notes.NoteField) ? cast resolved : null;
	}

	/** Resolves a whole `a.b.c` path from a script-visible root. **/
	public static inline function getObjectLoop(objectName:String, ?allowMaps:Bool = false):Dynamic
		return tagToObject(objectName, allowMaps);

	/**
		Walks `split` from its root, stopping one short when `getProperty` is set so the caller can
		read or write the final segment itself.
	**/
	public static function getPropertyLoop(split:Array<String>, ?getProperty:Bool = true, ?allowMaps:Bool = false):Dynamic {
		var obj:Dynamic = PropertyPath.root(split[0], allowMaps);
		var end:Int = getProperty ? split.length - 1 : split.length;

		for (i in 1...end)
			obj = PropertyPath.get(obj, split[i], allowMaps);
		return obj;
	}

	/**
		The container a `group`-taking callback means.
	
		These callbacks used to resolve their group with `Reflect.getProperty(getTargetInstance(),
		name)`, which only ever sees a FIELD of the state. `dadGroup` is a field so it worked, but a
		stage-declared anchor group is registered as a script VARIABLE like every other stage
		object, so it resolved to null -- even though `getProperty("rooftop.x")` finds it, because
		object paths go through `PropertyPath.root`, which checks variables first. Group arguments
		now resolve the same way, so custom stage anchors work wherever `dadGroup` does.
	
		@param name The group name a script passed.
		@return The group, or null when nothing of that name exists.
	**/
	/**
		The container that actually holds `obj`: `host` itself, or the group inside it that does.
	
		Flixel members carry no parent backpointer, so this is a one-level search of the state and
		its immediate groups -- which is where the engine puts characters (`dadGroup`, and the
		stage anchor groups). Deeper nesting is not covered; pass the group explicitly for that.
	
		@param obj The object to locate.
		@param host The state or substate to search.
		@return The container holding it, or null when nothing does.
	**/
	public static function containerOf(obj:FlxBasic, host:Dynamic):Dynamic {
		if (obj == null || host == null)
			return null;

		var members:Array<FlxBasic> = cast Reflect.getProperty(host, 'members');
		if (members == null)
			return null;
		if (members.indexOf(obj) >= 0)
			return host;

		for (member in members) {
			var group:FlxTypedGroup<FlxBasic> = Std.downcast(member, FlxTypedGroup);
			if (group != null && group.members.indexOf(obj) >= 0)
				return group;

			var sprites:FlxSpriteGroup = Std.downcast(member, FlxSpriteGroup);
			if (sprites != null && sprites.members.indexOf(cast obj) >= 0)
				return sprites;
		}

		return null;
	}

	public static function groupOf(name:Dynamic, ?allowMaps:Bool = false):Dynamic {
		// Lua is untyped, so a `?group:String` slot can arrive holding anything -- a mod copying the
		// `addLuaSprite(tag, front)` shape writes `setObjectOrder(tag, pos, false)`, and the Bool
		// lands here and stringifies as "false". Anything that is not a name means "no group".
		if (name == null || !Std.isOfType(name, String))
			return null;

		return tagToObject(cast name, allowMaps);
	}

	/** The object a path starts from: `this`/`game`, a script variable, or a field of the state. **/
	public static inline function getObjectDirectly(objectName:String, ?allowMaps:Bool = false):Dynamic
		return PropertyPath.root(objectName, allowMaps);

	/**
		Resolves a Lua tag like `myObj` or `myObj.subProp.target`, without allocating a split array
		for the dotless common case.
	**/
	public static inline function tagToObject(tag:String, ?allowMaps:Bool = false):Dynamic {
		if (tag.indexOf('.') < 0)
			return PropertyPath.root(tag, allowMaps);
		var dot:Int = tag.indexOf('.');
		return PropertyPath.get(PropertyPath.root(tag.substr(0, dot), allowMaps), tag.substr(dot + 1), allowMaps);
	}

	public static function isOfTypes(value:Any, types:Array<Dynamic>) {
		for (type in types) {
			if (Std.isOfType(value, type))
				return true;
		}
		return false;
	}

	public static function isLuaSupported(value:Any):Bool {
		return (value == null || isOfTypes(value, [Bool, Int, Float, String, Array]) || Type.typeof(value) == ValueType.TObject);
	}

	public static function getTargetInstance() {
		if (PlayState.instance != null)
			return PlayState.instance.isDead ? GameOverSubstate.instance : PlayState.instance;
		return MusicBeatState.getState();
	}

	public static inline function getLowestCharacterGroup():FlxSpriteGroup {
		var stageData:StageFile = StageData.getStageFile(PlayState.SONG.stage);
		var group:FlxSpriteGroup = (stageData.hide_girlfriend ? PlayState.instance.boyfriendGroup : PlayState.instance.gfGroup);

		var pos:Int = PlayState.instance.members.indexOf(group);

		var newPos:Int = PlayState.instance.members.indexOf(PlayState.instance.boyfriendGroup);
		if (newPos < pos) {
			group = PlayState.instance.boyfriendGroup;
			pos = newPos;
		}

		newPos = PlayState.instance.members.indexOf(PlayState.instance.dadGroup);
		if (newPos < pos) {
			group = PlayState.instance.dadGroup;
			pos = newPos;
		}
		return group;
	}

	public static function addAnimByIndices(obj:String, name:String, prefix:String, indices:Any = null, framerate:Float = 24, loop:Bool = false) {
		var obj:FlxSprite = cast LuaUtils.getObjectDirectly(obj);
		if (obj != null && obj.animation != null) {
			if (indices == null)
				indices = [0];
			else if (Std.isOfType(indices, String)) {
				var strIndices:Array<String> = cast(indices, String).trim().split(',');
				var myIndices:Array<Int> = [];
				for (i in 0...strIndices.length) {
					var parsed:Null<Int> = Std.parseInt(strIndices[i]);
					if (parsed != null) myIndices.push(parsed);
				}
				indices = myIndices;
			}

			if (prefix != null)
				obj.animation.addByIndices(name, prefix, indices, '', framerate, loop);
			else
				obj.animation.add(name, indices, framerate, loop);

			if (obj.animation.curAnim == null) {
				var dyn:Dynamic = cast obj;
				if (dyn.playAnim != null)
					dyn.playAnim(name, true);
				else
					dyn.animation.play(name, true);
			}
			return true;
		}
		return false;
	}

	public static function loadFrames(spr:FlxSprite, image:String, spriteType:String) {
		switch (spriteType.toLowerCase().replace(' ', '')) {
			// case "texture" | "textureatlas" | "tex":
			// spr.frames = AtlasFrameMaker.construct(image);

			// case "texture_noaa" | "textureatlas_noaa" | "tex_noaa":
			// spr.frames = AtlasFrameMaker.construct(image, null, true);

			case 'aseprite', 'ase', 'json', 'jsoni8':
				spr.frames = Paths.getAsepriteAtlas(image);

			case "packer", 'packeratlas', 'pac':
				spr.frames = Paths.getPackerAtlas(image);

			case 'sparrow', 'sparrowatlas', 'sparrowv2':
				spr.frames = Paths.getSparrowAtlas(image);

			default:
				spr.frames = Paths.getAtlas(image);
		}
	}

	public static function destroyObject(tag:String) {
		var variables = MusicBeatState.getVariables();
		var obj:FlxSprite = variables.get(tag);
		if (obj == null || obj.destroy == null)
			return;

		LuaUtils.getTargetInstance().remove(obj, true);
		obj.destroy();
		variables.remove(tag);
	}

	public static function cancelTween(tag:String) {
		if (!tag.startsWith('tween_'))
			tag = 'tween_' + LuaUtils.formatVariable(tag);
		var variables = MusicBeatState.getVariables();
		var twn:FlxTween = variables.get(tag);
		if (twn != null) {
			twn.cancel();
			twn.destroy();
			variables.remove(tag);
		}
	}

	public static function cancelTimer(tag:String) {
		if (!tag.startsWith('timer_'))
			tag = 'timer_' + LuaUtils.formatVariable(tag);
		var variables = MusicBeatState.getVariables();
		var tmr:FlxTimer = variables.get(tag);
		if (tmr != null) {
			tmr.cancel();
			tmr.destroy();
			variables.remove(tag);
		}
	}

	public static function formatVariable(tag:String)
		return tag.trim().replace(' ', '_').replace('.', '');

	public static function tweenPrepare(tag:String, vars:String) {
		if (tag != null)
			cancelTween(tag);
		return getObjectLoop(vars);
	}

	public static function getBuildTarget():String {
		#if windows
		return 'windows';
		#elseif linux
		return 'linux';
		#elseif mac
		return 'mac';
		#elseif hl
		return 'hashlink';
		#elseif (html5 || emscripten || nodejs || winjs || electron)
		return 'browser';
		#elseif android
		return 'android';
		#elseif webos
		return 'webos';
		#elseif tvos
		return 'tvos';
		#elseif watchos
		return 'watchos';
		#elseif air
		return 'air';
		#elseif flash
		return 'flash';
		#elseif (ios || iphonesim)
		return 'ios';
		#elseif neko
		return 'neko';
		#elseif switch
		return 'switch';
		#else
		return 'unknown';
		#end
	}

	// buncho string stuffs
	public static function getTweenTypeByString(?type:String = '') {
		switch (type.toLowerCase().trim()) {
			case 'backward':
				return FlxTweenType.BACKWARD;
			case 'looping' | 'loop':
				return FlxTweenType.LOOPING;
			case 'persist':
				return FlxTweenType.PERSIST;
			case 'pingpong':
				return FlxTweenType.PINGPONG;
		}
		return FlxTweenType.ONESHOT;
	}

	public static function getTweenEaseByString(?ease:String = '') {
		switch (ease.toLowerCase().trim()) {
			case 'backin':
				return FlxEase.backIn;
			case 'backinout':
				return FlxEase.backInOut;
			case 'backout':
				return FlxEase.backOut;
			case 'bouncein':
				return FlxEase.bounceIn;
			case 'bounceinout':
				return FlxEase.bounceInOut;
			case 'bounceout':
				return FlxEase.bounceOut;
			case 'circin':
				return FlxEase.circIn;
			case 'circinout':
				return FlxEase.circInOut;
			case 'circout':
				return FlxEase.circOut;
			case 'cubein':
				return FlxEase.cubeIn;
			case 'cubeinout':
				return FlxEase.cubeInOut;
			case 'cubeout':
				return FlxEase.cubeOut;
			case 'elasticin':
				return FlxEase.elasticIn;
			case 'elasticinout':
				return FlxEase.elasticInOut;
			case 'elasticout':
				return FlxEase.elasticOut;
			case 'expoin':
				return FlxEase.expoIn;
			case 'expoinout':
				return FlxEase.expoInOut;
			case 'expoout':
				return FlxEase.expoOut;
			case 'quadin':
				return FlxEase.quadIn;
			case 'quadinout':
				return FlxEase.quadInOut;
			case 'quadout':
				return FlxEase.quadOut;
			case 'quartin':
				return FlxEase.quartIn;
			case 'quartinout':
				return FlxEase.quartInOut;
			case 'quartout':
				return FlxEase.quartOut;
			case 'quintin':
				return FlxEase.quintIn;
			case 'quintinout':
				return FlxEase.quintInOut;
			case 'quintout':
				return FlxEase.quintOut;
			case 'sinein':
				return FlxEase.sineIn;
			case 'sineinout':
				return FlxEase.sineInOut;
			case 'sineout':
				return FlxEase.sineOut;
			case 'smoothstepin':
				return FlxEase.smoothStepIn;
			case 'smoothstepinout':
				return FlxEase.smoothStepInOut;
			case 'smoothstepout':
				return FlxEase.smoothStepOut;
			case 'smootherstepin':
				return FlxEase.smootherStepIn;
			case 'smootherstepinout':
				return FlxEase.smootherStepInOut;
			case 'smootherstepout':
				return FlxEase.smootherStepOut;
		}
		return FlxEase.linear;
	}

	public static function blendModeFromString(blend:String):BlendMode {
		switch (blend.toLowerCase().trim()) {
			case 'add':
				return ADD;
			case 'alpha':
				return ALPHA;
			case 'darken':
				return DARKEN;
			case 'difference':
				return DIFFERENCE;
			case 'erase':
				return ERASE;
			case 'hardlight':
				return HARDLIGHT;
			case 'invert':
				return INVERT;
			case 'layer':
				return LAYER;
			case 'lighten':
				return LIGHTEN;
			case 'multiply':
				return MULTIPLY;
			case 'overlay':
				return OVERLAY;
			case 'screen':
				return SCREEN;
			case 'shader':
				return SHADER;
			case 'subtract':
				return SUBTRACT;
		}
		return NORMAL;
	}

	public static function typeToString(type:Int):String {
		#if LUA_ALLOWED
		if (type == Lua.TBOOLEAN) return "boolean";
		if (type == Lua.TNUMBER) return "number";
		if (type == Lua.TSTRING) return "string";
		if (type == Lua.TTABLE) return "table";
		if (type == Lua.TFUNCTION) return "function";
		if (type <= Lua.TNIL) return "nil";
		#end
		return "unknown";
	}

	public static function cameraFromString(cam:String):FlxCamera {
		switch (cam.toLowerCase()) {
			case 'camgame' | 'game':
				return PlayState.instance.camGame;
			case 'camhud' | 'hud':
				return PlayState.instance.camHUD;
			case 'camother' | 'other':
				return PlayState.instance.camOther;
		}
		var camera:FlxCamera = MusicBeatState.getVariables().get(cam);
		if (camera == null || !Std.isOfType(camera, FlxCamera))
			camera = PlayState.instance.camGame;
		return camera;
	}
}
