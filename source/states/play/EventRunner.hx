package states.play;

import backend.EventTools;
import backend.StageData;
import backend.SongChart;
import backend.SongChart.StrumLineData;
import flixel.util.FlxSort;
import objects.Note.EventNote;
import objects.Character;
import objects.HealthIcon;
import scripting.ScriptHooks;
import states.stages.*;

/**
	The chart-event interpreter: everything between an event note coming off the chart and the thing
	it does happening.

	This is `PlayState`'s coldest large subsystem -- a song fires a handful of events, against a
	`switch` that was a third of the class it used to live in. `PlayState` keeps the per-frame poll
	(`checkEventNote`, whose early-out runs every frame and almost always does nothing) and hands off
	here only once an event is actually due.

	State stays on `PlayState`: scripts reach it by reflection (`getProperty`), so moving a field
	would break mods silently. This class reads and writes it through `game`, which `PlayState`
	permits via `@:allow(states.play)`.
**/
class EventRunner {
	final game:PlayState;

	public function new(game:PlayState) {
		this.game = game;
	}

	public function triggerEvent(eventName:String, value1:String, value2:String, strumTime:Float) {
		var flValue1:Null<Float> = Std.parseFloat(value1);
		var flValue2:Null<Float> = Std.parseFloat(value2);
		if (Math.isNaN(flValue1))
			flValue1 = null;
		if (Math.isNaN(flValue2))
			flValue2 = null;

		switch (eventName) {
			case 'Hey!':
				var value:Int = 2;
				switch (value1.toLowerCase().trim()) {
					case 'bf' | 'boyfriend' | '0':
						value = 0;
					case 'gf' | 'girlfriend' | '1':
						value = 1;
				}

				if (flValue2 == null || flValue2 <= 0)
					flValue2 = 0.6;

				if (value != 0) {
					if (game.dad.curCharacter.startsWith('gf')) { // Tutorial GF is actually Dad! The GF is an imposter!! ding ding ding ding ding ding ding, dindinding, end my suffering
						game.dad.playAnim('cheer', true);
						game.dad.specialAnim = true;
						game.dad.heyTimer = flValue2;
					} else if (game.gf != null) {
						game.gf.playAnim('cheer', true);
						game.gf.specialAnim = true;
						game.gf.heyTimer = flValue2;
					}
				}
				if (value != 1) {
					game.boyfriend.playAnim('hey', true);
					game.boyfriend.specialAnim = true;
					game.boyfriend.heyTimer = flValue2;
				}

			case 'Set GF Speed':
				if (flValue1 == null || flValue1 < 1)
					flValue1 = 1;
				game.gfSpeed = Math.round(flValue1);

			case 'Add Camera Zoom':
				if (ClientPrefs.data.camZooms && FlxG.camera.zoom < 1.35) {
					if (flValue1 == null)
						flValue1 = 0.015;
					if (flValue2 == null)
						flValue2 = 0.03;

					FlxG.camera.zoom += flValue1;
					game.camHUD.zoom += flValue2;
				}

			case 'Play Animation':
				// trace('Anim to play: ' + value1);
				var char:Character = game.dad;
				switch (value2.toLowerCase().trim()) {
					case 'bf' | 'boyfriend':
						char = game.boyfriend;
					case 'gf' | 'girlfriend':
						char = game.gf;
					default:
						if (flValue2 == null)
							flValue2 = 0;
						switch (Math.round(flValue2)) {
							case 1: char = game.boyfriend;
							case 2: char = game.gf;
						}
				}

				if (char != null) {
					char.playAnim(value1, true);
					char.specialAnim = true;
				}

			case 'Camera Follow Pos':
				if (game.camFollow != null) {
					game.isCameraOnForcedPos = false;
					if (flValue1 != null || flValue2 != null) {
						game.isCameraOnForcedPos = true;
						if (flValue1 == null)
							flValue1 = 0;
						if (flValue2 == null)
							flValue2 = 0;
						game.camFollow.x = flValue1;
						game.camFollow.y = flValue2;
					}
				}

			case 'Alt Idle Animation':
				var char:Character = game.dad;
				switch (value1.toLowerCase().trim()) {
					case 'gf' | 'girlfriend':
						char = game.gf;
					case 'boyfriend' | 'bf':
						char = game.boyfriend;
					default:
						var parsed:Null<Int> = Std.parseInt(value1);
						var val:Int = (parsed != null) ? parsed : 0;

						switch (val) {
							case 1: char = game.boyfriend;
							case 2: char = game.gf;
						}
				}

				if (char != null) {
					char.idleSuffix = value2;
					char.recalculateDanceIdle();
				}

			case 'Screen Shake':
				var valuesArray:Array<String> = [value1, value2];
				var targetsArray:Array<FlxCamera> = [game.camGame, game.camHUD];
				for (i in 0...targetsArray.length) {
					var split:Array<String> = valuesArray[i].split(',');
					var duration:Float = 0;
					var intensity:Float = 0;
					if (split[0] != null)
						duration = Std.parseFloat(split[0].trim());
					if (split[1] != null)
						intensity = Std.parseFloat(split[1].trim());
					if (Math.isNaN(duration))
						duration = 0;
					if (Math.isNaN(intensity))
						intensity = 0;

					if (duration > 0 && intensity != 0) {
						targetsArray[i].shake(intensity, duration);
					}
				}

			case 'Change Character':
				resolveCharTarget(value1);
				var type:Int = game.charTargetType;
				var targetLine:Int = game.charTargetLine;

				var characterName:String = 'boyfriend';
				var character:Character = game.boyfriend;
				var characterMap:Map<String, Character> = game.boyfriendMap;
				var icon:HealthIcon = game.iconP1;
				switch (type)
				{
					case 1:
						characterName = 'dad';
						character = game.dad;
						characterMap = game.dadMap;
						icon = game.iconP2;
					case 2:
						characterName = 'gf';
						character = game.gf;
						characterMap = game.gfMap;
						icon = null;
				}

				// A targeted strumline swaps the character IT is bound to (extra lines can share a slot).
				if (targetLine >= 0 && targetLine < game.strumLines.length) {
					var bound:Array<Character> = game.strumLines[targetLine].characters;
					if (bound.length > 0 && bound[0] != null)
						character = bound[0];
				}
				// The strumline owns the character in psych_v2, so keep the chart data (and the legacy
				// mirrors derived off it) truthful even when the line has no live character bound yet.
				// Skipped in charting mode: there the chart object IS the editor's, and a playtest must
				// never write an event's swap back into the file being edited.
				if (!PlayState.chartingMode && targetLine >= 0 && targetLine < PlayState.SONG.strumLines.length)
					PlayState.SONG.setLineCharacter(PlayState.SONG.strumLines[targetLine], value2);

				if (character != null)
				{
					if (character.curCharacter != value2)
					{
						if (!characterMap.exists(value2))
							game.addCharacterToList(value2, type);

						var newCharacter:Character = characterMap[value2];
						newCharacter.alpha = 1;
						game.bindStrumCharacter(value2, newCharacter);

						var lastAlpha:Float = character.alpha;
						character.alpha = .0001;

						var wasGf:Bool = character.curCharacter.startsWith('gf-') || character.curCharacter == 'gf';

						switch (type)
						{
							case 0:
								game.boyfriend = newCharacter;

							case 1:
								game.dad = newCharacter;
								if (!newCharacter.curCharacter.startsWith('gf-') && newCharacter.curCharacter != 'gf')
								{
									if (wasGf && game.gf != null)
										game.gf.visible = false;
								}
								else if (game.gf != null)
									game.gf.visible = false;

							case 2:
								game.gf = newCharacter; // character != null which would already be this.gf
						}

						// v2 note runtime sings through each strumline's cached Character list; repoint
						// any line that was singing the swapped-out character to the new one, otherwise
						// it keeps animating the old (now-hidden) instance and the new one sits idle.
						if (game.strumLines != null)
							for (line in game.strumLines)
								for (ci in 0...line.characters.length)
									if (line.characters[ci] == character)
										line.characters[ci] = newCharacter;

						// Notes are processed (updateFields) BEFORE events this frame, so a note on the same
						// step the swap happens already made the OLD character sing. Carry that live sing/special
						// state onto the new character so it doesn't sit idle on the swap step.
						var carryAnim:String = character.getAnimationName();
						if (carryAnim != null && (carryAnim.startsWith('sing') || character.specialAnim)) {
							newCharacter.playAnim(carryAnim, true);
							newCharacter.holdTimer = character.holdTimer;
							newCharacter.specialAnim = character.specialAnim;
						}

						icon?.changeIcon(newCharacter.healthIcon);
						game.reloadHealthBarColors();

						game.setOnScripts('${characterName}Name', newCharacter.curCharacter);

						// `onEvent` says a Change Character event fired; this says the swap FINISHED and
						// hands over both characters, so a script does not have to re-find the new one.
						game.callOnScripts(ScriptHooks.CHARACTER_CHANGE, [game.charTargetLine, character, newCharacter]);
					}
				}

			case 'Change Scroll Speed':
				if (game.songSpeedType != "constant") {
					if (flValue1 == null)
						flValue1 = 1;
					if (flValue2 == null)
						flValue2 = 0;

					var newValue:Float = PlayState.SONG.speed * ClientPrefs.getGameplaySetting('scrollspeed') * flValue1;
					if (flValue2 <= 0)
						game.songSpeed = newValue;
					else
						game.songSpeedTween = FlxTween.tween(this, {songSpeed: newValue}, flValue2 / game.playbackRate, {
							ease: FlxEase.linear,
							onComplete: function(twn:FlxTween) {
								game.songSpeedTween = null;
							}
						});
				}

			case 'Change Key Amount':
				if (flValue1 != null)
					game.changeKeyCount(Std.int(flValue1));

			case 'Set Property':
				try {
					var trueValue:Dynamic = value2.trim();
					if (trueValue == 'true' || trueValue == 'false')
						trueValue = trueValue == 'true';
					else if (flValue2 != null)
						trueValue = flValue2;
					else
						trueValue = value2;

					var split:Array<String> = value1.split('.');
					if (split.length > 1) {
						LuaUtils.setVarInArray(LuaUtils.getPropertyLoop(split), split[split.length - 1], trueValue);
					} else {
						LuaUtils.setVarInArray(this, value1, trueValue);
					}
				} catch (e:Dynamic) {
					// Not every throw is an exception object: a thrown String has no `message`, and
					// reading it made the error handler itself null-ref, turning a mistyped variable
					// name in a chart event into a crash instead of a red line in the debug overlay.
					var message:String = Std.string(Reflect.hasField(e, 'message') ? Reflect.field(e, 'message') : e);
					var len:Int = message.indexOf('\n') + 1;
					if (len <= 0)
						len = message.length;
					#if (LUA_ALLOWED || HSCRIPT_ALLOWED)
					game.addTextToDebug('ERROR ("Set Property" Event) - ' + message.substr(0, len), FlxColor.RED);
					#else
					FlxG.log.warn('ERROR ("Set Property" Event) - ' + message.substr(0, len));
					#end
				}

			case 'Play Sound':
				if (flValue2 == null)
					flValue2 = 1;
				FlxG.sound.play(Paths.sound(value1), flValue2);

			case 'Camera Flash':
				eventCameraFlash(value1, value2);

			case 'Video Player':
				eventVideoPlayer(value1, value2);

			case 'Tween':
				eventTween(value1, value2);

			case 'Change Stage':
				eventChangeStage(value1, value2);
		}

		// inline stagesFunc to avoid closure allocation in event hot path
		for (stage in game.stages)
			if (stage != null && stage.exists && stage.active)
				stage.eventCalled(eventName, value1, value2, flValue1, flValue2, strumTime);
		game.callOnScripts(ScriptHooks.EVENT, [eventName, value1, value2, strumTime]);
	}

	/**
		`Camera Flash`: flashes one camera with a colour.

		Value 1: `camera, forced` -- `forced` restarts a flash that is already running instead of
		being ignored.
		Value 2: `colour, duration`, where colour is hex (`FFFFFF`), an `r, g, b` triplet, or `random`.

		Does nothing at all when the player has Flashing Lights off, which is the whole reason this is
		an engine event rather than something a chart does with `Set Property`.
	**/

	function eventCameraFlash(value1:String, value2:String):Void {
		if (!ClientPrefs.data.flashing)
			return;

		var camParts:Array<String> = EventTools.fields(value1);
		var camera:FlxCamera = LuaUtils.cameraFromString(EventTools.str(camParts, 0, 'camGame'));
		var forced:Bool = EventTools.bool(camParts, 1, false);

		var flashParts:Array<String> = EventTools.fields(value2);
		var picked = EventTools.color(flashParts, 0, FlxColor.WHITE);
		var duration:Float = EventTools.num(flashParts, picked.used, 1);
		if (duration <= 0)
			duration = 1;

		camera.flash(picked.color, duration, null, forced);
	}

	/**
		`Video Player`: plays a video from `videos/`.

		Value 1: `filename, camera, layer` -- filename without its extension. `layer` is a position in
		the state's display list; leave it blank to keep the video on top.
		Value 2: `skip, midSong, loop, playOnLoad`.

		`midSong` is the important one: true plays the video over live gameplay, false treats it as a
		cutscene, which pauses the song and blocks pausing until it ends.
	**/

	function eventVideoPlayer(value1:String, value2:String):Void {
		#if VIDEOS_ALLOWED
		var v1:Array<String> = EventTools.fields(value1);
		var name:String = EventTools.str(v1, 0, '');
		if (name.length < 1)
			return;

		var v2:Array<String> = EventTools.fields(value2);
		game.startVideo(name, EventTools.bool(v2, 1, true), EventTools.bool(v2, 0, true), EventTools.bool(v2, 2, false), EventTools.bool(v2, 3, true));

		if (game.videoCutscene == null)
			return;

		game.videoCutscene.cameras = [LuaUtils.cameraFromString(EventTools.str(v1, 1, 'camOther'))];

		var layer:Int = Std.int(EventTools.num(v1, 2, -1));
		if (layer >= 0) {
			game.remove(game.videoCutscene, true);
			game.insert(layer > game.members.length ? game.members.length : layer, game.videoCutscene);
		}
		#end
	}

	/**
		`Tween`: tweens one property of one object, without a script.

		Value 1: `type, tag, object` -- type is `alpha`/`angle`/`x`/`y`/`color`/`zoom`/`scale` (with the
		spellings `opacity`, `fade`, `rotate`, `colour`, `tint` and `size` accepted too). `object` is a
		character name, a stage object, or anything a script has put in `variables`; for `zoom` it is a
		camera instead.
		Value 2: `value, duration, ease` -- ease defaults to linear. For `color` the value is a hex
		colour.

		The tag registers in the same place Lua's `doTween*` family uses, so `cancelTween(tag)` from a
		script cancels one of these, and `onTweenCompleted` fires with the tag when it lands.
	**/

	function eventTween(value1:String, value2:String):Void {
		var v1:Array<String> = EventTools.fields(value1);
		var kind:String = EventTools.str(v1, 0, '').toLowerCase();
		var tag:String = EventTools.str(v1, 1, '');
		var objectName:String = EventTools.str(v1, 2, '');
		if (kind.length < 1 || objectName.length < 1)
			return;

		var v2:Array<String> = EventTools.fields(value2);
		var duration:Float = EventTools.num(v2, 1, 1);
		if (duration <= 0)
			duration = 0.001;
		var ease:Dynamic = LuaUtils.getTweenEaseByString(EventTools.str(v2, 2, 'linear'));

		// Zoom is the odd one: it belongs to a camera, and a camera never lives in `variables` the way
		// the other targets do.
		var isZoom:Bool = (kind == 'zoom');
		var target:Dynamic = isZoom ? LuaUtils.cameraFromString(objectName) : LuaUtils.tagToObject(objectName);
		if (target == null) {
			FlxG.log.warn('Tween event: could not find "$objectName"');
			return;
		}

		var options:Dynamic = {ease: ease};
		if (tag.length > 0) {
			var key:String = LuaUtils.formatVariable('tween_$tag');
			var vars:Map<String, Dynamic> = MusicBeatState.getVariables();
			Reflect.setField(options, 'onComplete', function(twn:FlxTween):Void {
				vars.remove(key);
				game.callOnScripts(ScriptHooks.TWEEN_COMPLETED, [tag]);
			});
			var tween:FlxTween = startTween(kind, target, v2, duration, options);
			if (tween != null)
				vars.set(key, tween);
			return;
		}
		startTween(kind, target, v2, duration, options);
	}

	/** The `Tween` event's property mapping. Returns null for a type nobody recognises. **/

	function startTween(kind:String, target:Dynamic, v2:Array<String>, duration:Float, options:Dynamic):FlxTween {
		if (kind == 'color' || kind == 'colour' || kind == 'tint') {
			if (!Std.isOfType(target, FlxSprite))
				return null;
			var sprite:FlxSprite = cast target;
			return FlxTween.color(sprite, duration, sprite.color, EventTools.color(v2, 0, FlxColor.WHITE).color, options);
		}

		var value:Float = EventTools.num(v2, 0, 0);
		var props:Dynamic = switch (kind) {
			case 'alpha' | 'opacity' | 'fade': {alpha: value};
			case 'angle' | 'rotate': {angle: value};
			case 'x': {x: value};
			case 'y': {y: value};
			case 'zoom': {zoom: value};
			// Nested paths are resolved by FlxTween itself, so scale needs no per-frame helper.
			case 'scale' | 'size': {"scale.x": value, "scale.y": value};
			default: null;
		}
		if (props == null) {
			FlxG.log.warn('Tween event: unknown tween type "$kind"');
			return null;
		}
		return FlxTween.tween(target, props, duration, options);
	}

	/**
		`Change Stage`: swaps the stage mid-song.

		Value 1: the new stage's name, the same one a chart's `stage` field takes.
		Value 2: `moveCharacters` -- true (the default) drops the characters at the new stage's
		positions, false leaves them where they are for a stage that is only a backdrop swap.

		The judgement-UI skin is deliberately left alone: it is baked into popups that already exist,
		so changing it halfway through a song would leave a mix of two skins on screen.
	**/

	function eventChangeStage(value1:String, value2:String):Void {
		changeStage(value1 != null ? value1.trim() : '', EventTools.bool(EventTools.fields(value2), 0, true));
	}

	/**
		Tears the current stage out of the state and builds another in its place, then re-seats the
		characters and camera on it.

		@param newStage the stage name to switch to
		@param moveCharacters whether to move the characters onto the new stage's positions
	**/

	public function changeStage(newStage:String, moveCharacters:Bool = true):Void {
		if (newStage == null || newStage.length < 1 || newStage == PlayState.curStage)
			return;

		// The character groups come out first and go back in when the new stage rebuilds, which is what
		// keeps them layered between the new scenery rather than behind all of it. They are removed,
		// never destroyed -- the characters themselves survive the swap.
		game.remove(game.gfGroup, true);
		game.remove(game.dadGroup, true);
		game.remove(game.boyfriendGroup, true);

		for (stage in game.stages) {
			if (stage == null)
				continue;
			stage.removeOwned();
			stage.destroy();
		}
		game.stages = [];

		if (game.stageObjects != null) {
			for (key => spr in game.stageObjects) {
				if (StageData.reservedNames.contains(key) || spr == null)
					continue;
				game.remove(spr, true);
				spr.destroy();
				game.variables.remove(key);
			}
			game.stageObjects = null;
		}
		StageData.anchorGroups = new Map();

		PlayState.curStage = newStage;
		PlayState.SONG.stage = newStage;

		var stageData:StageFile = StageData.getStageFile(PlayState.curStage);
		game.defaultCamZoom = stageData.defaultZoom;

		game.BF_X = stageData.boyfriend[0];
		game.BF_Y = stageData.boyfriend[1];
		game.GF_X = stageData.girlfriend[0];
		game.GF_Y = stageData.girlfriend[1];
		game.DAD_X = stageData.opponent[0];
		game.DAD_Y = stageData.opponent[1];

		if (stageData.camera_speed != null)
			game.cameraSpeed = stageData.camera_speed;
		game.boyfriendCameraOffset = stageData.camera_boyfriend != null ? stageData.camera_boyfriend : [0, 0];
		game.opponentCameraOffset = stageData.camera_opponent != null ? stageData.camera_opponent : [0, 0];
		game.girlfriendCameraOffset = stageData.camera_girlfriend != null ? stageData.camera_girlfriend : [0, 0];

		if (moveCharacters) {
			game.boyfriendGroup.setPosition(game.BF_X, game.BF_Y);
			game.dadGroup.setPosition(game.DAD_X, game.DAD_Y);
			game.gfGroup.setPosition(game.GF_X, game.GF_Y);
		}

		switch (PlayState.curStage) {
			case 'stage':
				new StageWeek1();
			default:
				scripting.ScriptedStages.load(PlayState.curStage);
		}

		if (stageData.objects != null && stageData.objects.length > 0) {
			game.stageObjects = StageData.addObjectsToState(stageData.objects, !stageData.hide_girlfriend ? game.gfGroup : null, game.dadGroup, game.boyfriendGroup, this);
			for (key => spr in game.stageObjects)
				if (!StageData.reservedNames.contains(key))
					game.variables.set(key, spr);
		} else {
			game.add(game.gfGroup);
			game.add(game.dadGroup);
			game.add(game.boyfriendGroup);
		}

		if (game.gf != null)
			game.gf.visible = !stageData.hide_girlfriend;

		for (stage in game.stages)
			stage.createPost();

		// The follow point is derived from the old stage's geometry, so re-aim it or the camera keeps
		// looking at where the previous stage's character used to stand.
		game.moveCameraSection();
		FlxG.camera.snapToTarget();

		game.callOnScripts(ScriptHooks.STAGE_CHANGED, [PlayState.curStage]);
	}


	function eventPushed(event:EventNote) {
		eventPushedUnique(event);
		if (game.eventsPushed.contains(event.event)) {
			return;
		}

		switch (event.event) {
			case 'Video Player':
				#if VIDEOS_ALLOWED
				// Deliberately here rather than in eventPushedUnique, even though this event's asset
				// DOES vary with its values. Warming opens the file and decodes a frame, so warming
				// every Video Player event would hold one decoder open per event for the whole song to
				// save a hitch that only the first one avoids anyway. The first video starts warm; any
				// later one loads when it plays.
				var v1:Array<String> = EventTools.fields(event.value1);
				var name:String = EventTools.str(v1, 0, '');
				if (name.length > 0) {
					var v2:Array<String> = EventTools.fields(event.value2);
					game.precacheVideo(name, EventTools.bool(v2, 1, true), EventTools.bool(v2, 0, true), EventTools.bool(v2, 2, false));
				}
				#end
		}

		// stagesFunc is private to MusicBeatState, and PlayState already inlines this loop on the
		// event path rather than allocating a closure per event.
		for (stage in game.stages)
			if (stage != null && stage.exists && stage.active)
				stage.eventPushed(event);
		game.eventsPushed.push(event.event);

		// An event a script pushed after create() still needs its own script. Before the bootstrap has
		// run the create() loop below picks these up; after it, nothing else would.
		if (game.scriptedContentReady)
			loadEventScripts(event.event);
	}

	function eventPushedUnique(event:EventNote) {
		switch (event.event) {
			case "Change Character":
				resolveCharTarget(event.value1);
				game.addCharacterToList(event.value2, game.charTargetType);

			case 'Play Sound':
				Paths.sound(event.value1); // Precache sound
		}
		// stagesFunc is private to MusicBeatState, and PlayState already inlines this loop on the
		// event path rather than allocating a closure per event.
		for (stage in game.stages)
			if (stage != null && stage.exists && stage.active)
				stage.eventPushedUnique(event);
	}

	/**
		How many milliseconds early an event should fire, from whichever script claims it.

		The engine has no offsets of its own: an event that needs one belongs to whatever implements it,
		so it declares the offset from the same place (see the base-game pack's `custom_events/`).
	**/

	public function eventEarlyTrigger(event:EventNote):Float {
		var returnedValue:Null<Float> = game.callOnScripts(ScriptHooks.EVENT_EARLY_TRIGGER, [event.event, event.value1, event.value2, event.strumTime], true);
		if (returnedValue != null && returnedValue != 0) {
			return returnedValue;
		}
		return 0;
	}

	public function makeEvent(event:Array<Dynamic>, i:Int) {
		var subEvent:EventNote = {
			strumTime: event[0] + ClientPrefs.data.noteOffset,
			event: event[1][i][0],
			value1: event[1][i][1],
			value2: event[1][i][2]
		};
		game.eventNotes.push(subEvent);
		eventPushed(subEvent);
		game.callOnScripts(ScriptHooks.EVENT_PUSHED, [
			subEvent.event,
			subEvent.value1 != null ? subEvent.value1 : '',
			subEvent.value2 != null ? subEvent.value2 : '',
			subEvent.strumTime
		]);
	}

	/** Loads `custom_events/<name>` for both scripting languages. Idempotent per name by caller. **/
	public function loadEventScripts(name:String) {
		#if LUA_ALLOWED game.startLuasNamed('custom_events/$name.lua'); #end
		#if HSCRIPT_ALLOWED game.startHScriptsNamed('custom_events/$name.hx'); #end
	}

	function resolveCharTarget(value:String):Void {
		game.charTargetLine = -1;
		game.charTargetType = 0;
		if (value == null)
			return;

		var name:String = value.trim().toLowerCase();
		var explicit:Bool = false;
		if (name.startsWith('line:')) {
			name = name.substr(5).trim();
			explicit = true;
		} else if (name.startsWith('strum:')) {
			name = name.substr(6).trim();
			explicit = true;
		}

		if (name.length > 0) {
			for (sd in PlayState.SONG.strumLines)
				if (sd.id != null && sd.id.toLowerCase() == name) {
					game.charTargetLine = sd.index;
					game.charTargetType = charTypeOfLine(sd);
					return;
				}

			var num:Null<Int> = Std.parseInt(name);
			if (num != null) {
				if (explicit) { // `line:2` -- an absolute strumline index
					if (num >= 0 && num < PlayState.SONG.strumLines.length) {
						var sd:backend.SongChart.StrumLineData = PlayState.SONG.strumLines[num];
						game.charTargetLine = sd.index;
						game.charTargetType = charTypeOfLine(sd);
					}
					return;
				}
				game.charTargetType = (num == 1 || num == 2) ? num : 0; // legacy: the slot itself
			} else {
				game.charTargetType = switch (name) {
					case 'gf' | 'girlfriend': 2;
					case 'dad' | 'opponent': 1;
					default: 0;
				}
			}
		}

		var line:backend.SongChart.StrumLineData = lineForCharType(game.charTargetType);
		if (line != null)
			game.charTargetLine = line.index;
	}

	// called by every event with the same name

	inline function lineForCharType(type:Int):backend.SongChart.StrumLineData {
		return switch (type) {
			case 1: PlayState.SONG.opponentLine();
			case 2: PlayState.SONG.gfLine();
			default: PlayState.SONG.playerLine();
		}
	}

	/** The legacy character slot a strumline feeds (0 = bf, 1 = dad, 2 = gf). **/

	function charTypeOfLine(line:backend.SongChart.StrumLineData):Int {
		if (line == null)
			return 0;
		if (line.isPlayer)
			return 0;
		return (line == PlayState.SONG.gfLine()) ? 2 : 1;
	}

	/**
		Resolves a "Change Character" target into `charTargetLine` + `charTargetType`. psych_v2 ties characters
		to their strumline, so the value may name one -- any line id (`player`, `opponent`, `gf`, or a custom
		one) or `line:<index>`/`strum:<index>`. The legacy `bf`/`dad`/`gf` aliases and the plain numeric
		character slot still resolve exactly as they used to.
		@param value the event's value 1
	**/
}
