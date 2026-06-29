package editors.charting;

import objects.Character;
import backend.Song.SwagSection;
import flixel.math.FlxPoint;
import flixel.util.FlxSpriteUtil;
import states.editors.content.Prompt;
import editors.ChartingState;

/**
	The chart editor's bottom-left character preview (Options > Characters).

	Loads the song's gf/dad/bf, lets each be dragged independently with the mouse, and drives them like
	PlayState: dance on the beat, sing as notes pass, hold through sustains, and react to `Play Animation`
	events. Owns all character/drag/visibility state; reaches the editor (cameras, save, sub-states,
	scene `add`/`remove`) through `editor`.
**/
@:access(editors.ChartingState)
class EditorCharacterPreview {
	var editor:ChartingState;

	var editorChars:Array<Character> = [];
	var editorCharBaseScale:Array<Float> = [];
	var charBF:Character;
	var charDad:Character;
	var charGF:Character;
	var draggingCharIndex:Int = -1;
	var dragCharOffX:Float = 0;
	var dragCharOffY:Float = 0;
	var dragFloorOffY:Float = 0;
	var charDragOutline:FlxSprite;
	var _outlineW:Int = -1;
	var _outlineH:Int = -1;

	/** While the playhead is inside a long note, the character keeps singing until this time. **/
	var editorCharHoldEnd:Map<Character, Float> = new Map();

	var editorCharHoldAnim:Map<Character, String> = new Map();

	public var showChars:Bool = false;
	public var showBF:Bool = true;
	public var showDad:Bool = true;
	public var showGF:Bool = true;
	public var charsScale:Float = 0.35;
	public var charsAnchorBottom:Bool = true;
	public var charsFloorY:Float = -1;

	/**
		@param editor the chart editor that owns this preview (for cameras, save, scene and sub-states)
	**/
	public function new(editor:ChartingState) {
		this.editor = editor;
		var save = editor.chartEditorSave;
		if (save.data.showChars != null)
			showChars = save.data.showChars;
		if (save.data.showBF != null)
			showBF = save.data.showBF;
		if (save.data.showDad != null)
			showDad = save.data.showDad;
		if (save.data.showGF != null)
			showGF = save.data.showGF;
		if (save.data.charsScale != null)
			charsScale = save.data.charsScale;
		if (save.data.charsAnchorBottom != null)
			charsAnchorBottom = save.data.charsAnchorBottom;
		if (save.data.charsFloorY != null)
			charsFloorY = save.data.charsFloorY;
	}

	/** Opens the small settings window for the preview (visibility toggles, scale, floor anchor). **/
	public function openPrompt():Void {
		ClientPrefs.toggleVolumeKeys(false);
		editor.openSubState(new BasePrompt(300, 250, 'Character Preview', function(state:BasePrompt) {
			editor.upperBox.isMinimized = true;
			editor.upperBox.bg.visible = false;

			var closeBtn:PsychUIButton = new PsychUIButton(state.bg.x + state.bg.width - 40, state.bg.y, 'X', state.close, 40);
			closeBtn.cameras = state.cameras;
			state.add(closeBtn);

			var sx:Float = state.bg.x + 40;
			var sy:Float = state.bg.y + 55;

			function addCheck(label:String, dy:Float, getVal:Void->Bool, setVal:Bool->Void):Void {
				var chk:PsychUICheckBox = new PsychUICheckBox(sx, sy + dy, label, 110);
				chk.checked = getVal();
				chk.onClick = function() {
					setVal(chk.checked);
					editor.chartEditorSave.flush();
					updateCharsVisibility();
				};
				chk.cameras = state.cameras;
				state.add(chk);
			}

			addCheck('Show Characters', 0, () -> showChars, function(v) {
				showChars = v;
				editor.chartEditorSave.data.showChars = v;
			});
			addCheck('Boyfriend', 32, () -> showBF, function(v) {
				showBF = v;
				editor.chartEditorSave.data.showBF = v;
			});
			addCheck('Opponent', 60, () -> showDad, function(v) {
				showDad = v;
				editor.chartEditorSave.data.showDad = v;
			});
			addCheck('Girlfriend', 88, () -> showGF, function(v) {
				showGF = v;
				editor.chartEditorSave.data.showGF = v;
			});

			var scaleLabel:FlxText = new FlxText(sx, sy + 124, 60, 'Scale:');
			scaleLabel.cameras = state.cameras;
			state.add(scaleLabel);
			var scaleStepper:PsychUINumericStepper = new PsychUINumericStepper(sx + 55, sy + 122, 0.05, charsScale, 0.1, 3, 2, 70);
			scaleStepper.onValueChange = function() {
				charsScale = scaleStepper.value;
				editor.chartEditorSave.data.charsScale = charsScale;
				editor.chartEditorSave.flush();
				applyCharScale();
			};
			scaleStepper.cameras = state.cameras;
			state.add(scaleStepper);

			addCheck('Anchor to Floor', 155, () -> charsAnchorBottom, function(v) {
				charsAnchorBottom = v;
				editor.chartEditorSave.data.charsAnchorBottom = v;
			});
		}));
	}

	/** Same name logic the character editor uses to guess a character's natural slot. **/
	inline function predictCharacterIsNotPlayer(name:String):Bool {
		return (name != 'bf' && !name.startsWith('bf-') && !name.endsWith('-player') && !name.endsWith('-playable') && !name.endsWith('-dead'))
			|| name.endsWith('-opponent')
			|| name.startsWith('gf-')
			|| name.endsWith('-gf')
			|| name == 'gf';
	}

	/**
		Loads a character in its natural orientation then flips it into the requested slot (mirroring the
		character editor's "Player" toggle) so its animation offsets line up. Preview-only stage/camera
		offsets are dropped.
		@param name the character id
		@param wantPlayer whether it should occupy the playable (boyfriend) side
		@return the spawned character, or null on failure
	**/
	function makeEditorChar(name:String, wantPlayer:Bool):Character {
		if (name == null || name.length < 1)
			return null;
		var c:Character = null;
		try {
			var naturalIsPlayer:Bool = !predictCharacterIsNotPlayer(name);
			c = new Character(0, 0, name, naturalIsPlayer);
			if (wantPlayer != naturalIsPlayer) {
				c.isPlayer = wantPlayer;
				c.flipX = !c.flipX;
			}
		} catch (e:Dynamic) {
			trace('Chart editor: failed to load character "$name": $e');
			return null;
		}
		c.positionArray = [0, 0];
		c.cameraPosition = [0, 0];
		c.scrollFactor.set();
		c.cameras = [editor.camChars];
		c.antialiasing = ClientPrefs.data.antialiasing;
		editorChars.push(c);
		editorCharBaseScale.push(c.scale.x);
		editor.add(c);
		return c;
	}

	/** Rebuilds the gf/dad/bf trio from the current song and places them. **/
	public function reloadEditorChars():Void {
		for (c in editorChars) {
			if (c == null)
				continue;
			editor.remove(c, true);
			c.destroy();
		}
		editorChars = [];
		editorCharBaseScale = [];
		editorCharHoldEnd.clear();
		editorCharHoldAnim.clear();
		charBF = charDad = charGF = null;
		draggingCharIndex = -1;
		if (charDragOutline != null)
			charDragOutline.visible = false;
		if (PlayState.SONG == null)
			return;

		charGF = makeEditorChar(PlayState.SONG.gfVersion, false);
		charDad = makeEditorChar(PlayState.SONG.player2, false);
		charBF = makeEditorChar(PlayState.SONG.player1, true);

		applyCharScale();
		for (c in editorChars)
			c.dance();
		placeEditorChars();
		updateCharsVisibility();
	}

	inline function charToggled(c:Character):Bool {
		return (c == charBF && showBF) || (c == charDad && showDad) || (c == charGF && showGF);
	}

	inline function charSlot(c:Character):String {
		return (c == charBF) ? 'BF' : (c == charDad) ? 'Dad' : 'GF';
	}

	/**
		Re-scales every character by its own json scale times the user scale, replaying the current
		animation to restore the scaled offset and keeping the visible bottom-left fixed so scaling never
		shoves a character off-screen.
	**/
	function applyCharScale():Void {
		for (i in 0...editorChars.length) {
			var c:Character = editorChars[i];
			if (c == null)
				continue;
			var b0 = charScreenBounds(c);
			var keepX:Float = b0.x;
			var keepBottom:Float = b0.y + b0.height;
			b0.put();

			var base:Float = (i < editorCharBaseScale.length) ? editorCharBaseScale[i] : 1;
			c.scale.set(base * charsScale, base * charsScale);
			c.updateHitbox();
			var anim:String = c.getAnimationName();
			if (anim != null)
				c.playAnim(anim, true);

			var b1 = charScreenBounds(c);
			c.x += keepX - b1.x;
			c.y += keepBottom - (b1.y + b1.height);
			b1.put();
		}
	}

	/**
		Spreads the characters along the bottom-left by their on-screen width, then applies any saved
		per-slot positions. Positions are frozen afterward (playback never repositions a character).
	**/
	function placeEditorChars():Void {
		var runX:Float = 20;
		for (i in 0...editorChars.length) {
			var c:Character = editorChars[i];
			if (c == null)
				continue;
			c.setPosition(0, 0);
			var b = charScreenBounds(c);
			c.x = runX - b.x;
			c.y = (FlxG.height - 10) - (b.y + b.height);
			runX += b.width + 12;
			b.put();

			var saved:Dynamic = Reflect.field(editor.chartEditorSave.data, 'charPos' + charSlot(c));
			if (saved != null && saved.length > 1) {
				c.x = saved[0];
				c.y = saved[1];
			}
		}
	}

	/** Reloads the trio on first show; otherwise just toggles each character's visibility/activity. **/
	public function updateCharsVisibility():Void {
		if (showChars && editorChars.length == 0 && PlayState.SONG != null) {
			reloadEditorChars();
			return;
		}
		for (c in editorChars) {
			var vis:Bool = showChars && charToggled(c);
			c.visible = vis;
			c.active = vis;
		}
		if ((!showChars || draggingCharIndex < 0) && charDragOutline != null)
			charDragOutline.visible = false;
	}

	/** Tracks the dragged character's visible bounds with an outline (regenerated only on size change). **/
	function updateCharDragOutline(c:Character):Void {
		if (charDragOutline == null) {
			charDragOutline = new FlxSprite();
			charDragOutline.scrollFactor.set();
			charDragOutline.cameras = [editor.camChars];
			editor.add(charDragOutline);
		}
		var b = charScreenBounds(c);
		var w:Int = Std.int(Math.max(b.width, 1));
		var h:Int = Std.int(Math.max(b.height, 1));
		if (w != _outlineW || h != _outlineH) {
			charDragOutline.makeGraphic(w, h, FlxColor.TRANSPARENT, true);
			FlxSpriteUtil.drawRect(charDragOutline, 0, 0, w - 1, h - 1, FlxColor.TRANSPARENT, {thickness: 3, color: 0xFFFFFF00});
			_outlineW = w;
			_outlineH = h;
		}
		charDragOutline.setPosition(b.x, b.y);
		charDragOutline.visible = true;
		b.put();
	}

	/**
		Visible on-screen bounds for hit-testing/outlining/anchoring. Atlas (FlxAnimate) characters render
		through a child `atlas` sprite whose frame box is empty, so their real art bounds are measured from
		the atlas timeline instead.
	**/
	inline function charScreenBounds(c:Character):flixel.math.FlxRect {
		#if flixel_animate
		if (c.isAnimateAtlas && c.atlas != null) {
			c.copyAtlasValues();
			var rect:flixel.math.FlxRect = c.atlas.getScreenBounds(null, editor.camChars);
			@:privateAccess
			{
				var bounds = c.atlas.timeline != null ? c.atlas.timeline._bounds : null;
				if (bounds != null && bounds.width > 0 && bounds.height > 0) {
					rect.set(bounds.x, bounds.y, bounds.width, bounds.height);
					animate.internal.Timeline.applyMatrixToRect(rect, c.atlas._matrix);
				}
			}
			return rect;
		}
		#end
		return c.getScreenBounds(null, editor.camChars);
	}

	/** True if the mouse (already in camChars space) is over the character's visible box. **/
	function mouseOverChar(c:Character, mp:FlxPoint):Bool {
		var b = charScreenBounds(c);
		var inside:Bool = (mp.x >= b.x && mp.x <= b.x + b.width && mp.y >= b.y && mp.y <= b.y + b.height);
		b.put();
		return inside;
	}

	/** Moves the character so its visible bottom sits on `charsFloorY` (keeps feet planted). **/
	function anchorCharBottom(c:Character):Void {
		var b = charScreenBounds(c);
		c.y += charsFloorY - (b.y + b.height);
		b.put();
	}

	/** Keeps the character's visible box inside the screen. **/
	function clampCharToScreen(c:Character):Void {
		var b = charScreenBounds(c);
		var tx:Float = FlxMath.bound(b.x, 0, Math.max(0, FlxG.width - b.width));
		var ty:Float = FlxMath.bound(b.y, 0, Math.max(0, FlxG.height - b.height));
		c.x += tx - b.x;
		c.y += ty - b.y;
		b.put();
	}

	/**
		Per-frame: return to idle after a sing (holding through sustains), drag a character with the mouse,
		then floor-anchor and screen-clamp everyone.
		@param elapsed frame delta
	**/
	public function updateEditorChars(elapsed:Float):Void {
		if (!showChars || editorChars.length == 0)
			return;

		if (charsFloorY < 0)
			charsFloorY = FlxG.height - 10;

		for (c in editorChars) {
			if (c == null)
				continue;
			var anim:String = c.getAnimationName();

			if (editorCharHoldEnd.exists(c)) {
				var holding:Bool = FlxG.sound.music != null && FlxG.sound.music.playing
					&& Conductor.songPosition < editorCharHoldEnd.get(c)
					&& anim != null && anim.startsWith('sing');
				if (holding) {
					c.holdTimer = 0;
					var holdAnim:String = editorCharHoldAnim.get(c) + '-hold';
					if (c.hasAnimation(holdAnim) && anim != holdAnim && anim != holdAnim + '-loop')
						c.playAnim(holdAnim, true);
					continue;
				}
				editorCharHoldEnd.remove(c);
				editorCharHoldAnim.remove(c);
			}

			if (anim != null && anim.startsWith('sing') && c.holdTimer >= Conductor.stepCrochet * 0.0011 * c.singDuration) {
				c.dance();
				c.holdTimer = 0;
			}
		}

		var mp:FlxPoint = FlxG.mouse.getScreenPosition(editor.camChars);
		if (draggingCharIndex < 0) {
			var overUI:Bool = FlxG.mouse.overlaps(editor.mainBox.bg, editor.camUI)
				|| FlxG.mouse.overlaps(editor.infoBox.bg, editor.camUI)
				|| FlxG.mouse.overlaps(editor.upperBox.bg, editor.camUI);
			if (FlxG.mouse.justPressed && !overUI) {
				var i:Int = editorChars.length;
				while (--i >= 0) {
					var c:Character = editorChars[i];
					if (c != null && c.visible && mouseOverChar(c, mp)) {
						draggingCharIndex = i;
						dragCharOffX = c.x - mp.x;
						dragCharOffY = c.y - mp.y;
						dragFloorOffY = charsFloorY - mp.y;
						editor.ignoreClickForThisFrame = true;
						updateCharDragOutline(c);
						break;
					}
				}
			}
		} else {
			var c:Character = editorChars[draggingCharIndex];
			if (c != null && FlxG.mouse.pressed) {
				c.x = mp.x + dragCharOffX;
				if (charsAnchorBottom)
					charsFloorY = mp.y + dragFloorOffY;
				else
					c.y = mp.y + dragCharOffY;
			} else {
				if (c != null) {
					Reflect.setField(editor.chartEditorSave.data, 'charPos' + charSlot(c), [c.x, c.y]);
					editor.chartEditorSave.data.charsFloorY = charsFloorY;
					editor.chartEditorSave.flush();
				}
				draggingCharIndex = -1;
				if (charDragOutline != null)
					charDragOutline.visible = false;
			}
		}
		mp.put();

		for (c in editorChars) {
			if (c == null || !c.visible)
				continue;
			if (charsAnchorBottom)
				anchorCharBottom(c);
			clampCharToScreen(c);
		}

		if (draggingCharIndex >= 0 && editorChars[draggingCharIndex] != null)
			updateCharDragOutline(editorChars[draggingCharIndex]);
	}

	/** Dances every non-singing character on a beat change (call once per beat). **/
	public function danceOnBeat():Void {
		if (!showChars || editorChars.length == 0)
			return;
		for (c in editorChars) {
			if (c == null)
				continue;
			var anim:String = c.getAnimationName();
			if (anim == null || !anim.startsWith('sing'))
				c.dance();
		}
	}

	/**
		Routes a passing note to the correct character and plays its sing animation (with alt suffix),
		remembering the sustain so the pose is held for the whole note.
	**/
	public function editorCharSing(note:MetaNote):Void {
		if (!showChars || editorChars.length == 0 || note == null || note.isEvent || note.songData == null || note.songData.length < 2)
			return;

		var noteType:String = (note.songData[3] != null && Std.isOfType(note.songData[3], String)) ? note.songData[3] : '';
		if (noteType == 'No Animation')
			return;

		var dir:Int = Std.int(note.songData[1]) % ChartingState.GRID_COLUMNS_PER_PLAYER;
		var singAnims:Array<String> = Mania.singAnims(ChartingState.GRID_COLUMNS_PER_PLAYER);
		if (dir < 0 || dir >= singAnims.length)
			return;

		var char:Character = note.mustPress ? charBF : charDad;
		if (noteType == 'GF Sing')
			char = charGF;
		if (char == null)
			return;

		var suffix:String = (noteType == 'Alt Animation') ? '-alt' : '';
		var sec:SwagSection = editor.editorSectionAtTime(note.strumTime);
		if (suffix.length < 1 && sec != null && sec.altAnim)
			suffix = '-alt';

		char.playAnim(singAnims[dir] + suffix, true);
		char.holdTimer = 0;

		if (note.sustainLength > 0) {
			editorCharHoldEnd.set(char, note.strumTime + note.sustainLength);
			editorCharHoldAnim.set(char, singAnims[dir] + suffix);
		} else {
			editorCharHoldEnd.remove(char);
			editorCharHoldAnim.remove(char);
		}
	}

	/** Routes a passing `Play Animation` event to its character (mirrors PlayState). **/
	public function editorEventAnim(event:MetaNote):Void {
		if (!showChars || editorChars.length == 0 || event == null || event.events == null)
			return;
		for (sub in event.events) {
			if (sub == null || sub.length < 1 || sub[0] != 'Play Animation')
				continue;
			var char:Character = charDad;
			switch ((sub[2] != null ? sub[2] : '').toLowerCase().trim()) {
				case 'bf' | 'boyfriend' | '1':
					char = charBF;
				case 'gf' | 'girlfriend' | '2':
					char = charGF;
				default:
					char = charDad;
			}
			if (char != null && sub[1] != null)
				char.playAnim(sub[1], true);
		}
	}
}
