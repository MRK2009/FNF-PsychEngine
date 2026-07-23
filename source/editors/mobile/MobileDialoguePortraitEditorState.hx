package editors.mobile;

import flixel.FlxG;
import flixel.FlxSprite;
import flixel.group.FlxSpriteGroup;
import flixel.util.FlxColor;
import cutscenes.DialogueBoxPsych;
import cutscenes.DialogueCharacter;
import cutscenes.DialogueCharacter.DialogueAnimArray;
import smidr.UILocale;
import smidr.UIFonts;
import smidr.widgets.UIButton;
import smidr.widgets.UICheckbox;
import smidr.widgets.UIDropdown;
import smidr.widgets.UILabel;
import smidr.widgets.UIScrollPane;
import smidr.widgets.UISlider;
import smidr.widgets.UIStepper;
import smidr.widgets.UITextInput;
import smidr.overlays.UIToast;

/**
 * Touch-native Dialogue Portrait editor (the desktop `DialogueCharacterEditorState`): the portrait with
 * red (loop) + blue (idle) offset ghosts and the speech bubble on the canvas, its config + animation list
 * in rail pages, and the two per-animation offsets edited by dragging (current mode) or the nudge action
 * bar. Saves `<name>.json` with the desktop JSON shape.
 */
class MobileDialoguePortraitEditorState extends MobileEditorBase {
	var character:DialogueCharacter;
	var ghostLoop:DialogueCharacter;
	var ghostIdle:DialogueCharacter;
	var box:FlxSprite;
	var mainGroup:FlxSpriteGroup;

	var characterName:String = DialogueCharacter.DEFAULT_CHARACTER;
	var curSelectedAnim:String = null;
	var offsetMode:Int = 0;

	// Reference ghosts, off by default (the desktop editor also starts with them hidden): the LIVE
	// portrait is what the current mode's offsets move, the ghosts are the other pose to line up against.
	var showLoopGhost:Bool = false;
	var showIdleGhost:Bool = false;
	var ghostAlpha:Float = 0.6;

	var modeBtn:UIButton;
	var ghostBtn:UIButton;

	override function create():Void {
		initPsychCamera();
		FlxG.camera.bgColor = 0xFF12141F;

		UILocale.translate = function(k:String, f:String):String return Language.getPhrase(k, f);
		UIFonts.register('assets/fonts/vcr.ttf');

		mainGroup = new FlxSpriteGroup();
		add(mainGroup);

		character = new DialogueCharacter();
		mainGroup.add(character);

		ghostLoop = new DialogueCharacter();
		ghostLoop.alpha = ghostAlpha;
		ghostLoop.color = FlxColor.RED;
		ghostLoop.isGhost = true;
		ghostLoop.visible = false;
		mainGroup.add(ghostLoop);

		ghostIdle = new DialogueCharacter();
		ghostIdle.alpha = ghostAlpha;
		ghostIdle.color = FlxColor.BLUE;
		ghostIdle.isGhost = true;
		ghostIdle.visible = false;
		mainGroup.add(ghostIdle);

		box = new FlxSprite(70, 370);
		box.antialiasing = ClientPrefs.data.antialiasing;
		box.frames = Paths.getSparrowAtlas('speech_bubble');
		box.scrollFactor.set();
		box.animation.addByPrefix('normal', 'speech bubble normal', 24);
		box.animation.addByPrefix('center', 'speech bubble middle', 24);
		box.animation.play('normal', true);
		box.setGraphicSize(Std.int(box.width * 0.9));
		box.updateHitbox();
		add(box);

		// Chrome FIRST: loading a portrait walks all the way down to updateStatus, which needs the shell
		// (it null-referenced and killed the editor on entry).
		buildChrome();
		loadPortrait(characterName);

		setupCanvas();
		// A canvas press is always an offset drag here (there is nothing to pan): without claiming it in
		// onDragStart the gesture layer routes it to onPan and onDragMove never fires at all.
		gestures.onDragStart = function(_x:Float, _y:Float):Bool return true;
		// onDragMove hands over (dx, dy, x, y): the first two are the frame delta. Offsets are subtracted
		// when drawn, so they move against the finger for the ghost to follow it.
		gestures.onDragMove = function(dx:Float, dy:Float, _x:Float, _y:Float):Void {
			var a:DialogueAnimArray = currentAnim();
			if (a == null)
				return;

			var arr:Array<Int> = (offsetMode == 0) ? a.loop_offsets : a.idle_offsets;
			arr[0] -= Std.int(dx);
			arr[1] -= Std.int(dy);
			markDirty();
			applyOffsets();
		};

		super.create();
	}

	function buildChrome():Void {
		shell = new MobileEditorShell();
		shell.addLeft('< EXIT', exitEditor);
		shell.railGap(true);
		shell.addLeft('OPEN', openPortrait);
		shell.addLeft('SAVE', saveCharacter, true);

		shell.addRight('PORTRAIT', openPortraitPage);
		shell.addRight('ANIMS', openAnimPage);
		modeBtn = shell.addRight('OFF: LOOP', toggleMode);
		ghostBtn = shell.addRight('GHOSTS: OFF', openGhostPage);
		shell.railGap(false);
		shell.addRight('? GUIDE', function() shell.showGuide([
			'PORTRAIT  load a portrait json, image, scale, dialogue side',
			'ANIMS     add / update / remove animations, pick one',
			'OFF: MODE  toggle which offset you edit: loop or idle',
			'GHOSTS    overlay the loop (red) / idle (blue) pose to line up against',
			'DRAG      move the current-mode offset',
			'ACTION BAR  nudge the offset',
			'SAVE      writes <name>.json'
		]));

		// Signs match the desktop editor's arrow keys: offsets are subtracted when drawn, so moving the
		// portrait left means a LARGER offset.
		shell.setActionBar([
			{label: '< ', cb: function() nudge(1, 0)},
			{label: ' >', cb: function() nudge(-1, 0)},
			{label: '^', cb: function() nudge(0, 1)},
			{label: 'v', cb: function() nudge(0, -1)}
		]);
		shell.showActionBar(true);
	}

	/** Switches which offset the portrait (and the nudge/drag) edits: the loop pose or the idle pose. **/
	function toggleMode():Void {
		offsetMode = 1 - offsetMode;
		modeBtn.label = 'OFF: ${offsetMode == 0 ? 'LOOP' : 'IDLE'}';
		// The live portrait plays the pose being edited, so its offsets are what you see moving.
		if (curSelectedAnim != null)
			character.playAnim(curSelectedAnim, offsetMode == 1);
		applyOffsets();
	}

	/** Ghost overlay controls, mirroring the character editor's GHOST page. **/
	function openGhostPage():Void {
		shell.openPage('GHOSTS', function(pane:UIScrollPane):Float {
			var w:Float = shell.pageWidth();
			var y:Float = 6;

			var loopBox:UICheckbox = new UICheckbox('Show loop ghost (red)', w, showLoopGhost, function(c:Bool) {
				showLoopGhost = c;
				applyGhosts();
			});
			loopBox.y = y;
			pane.content.addChild(loopBox);
			y += 52;

			var idleBox:UICheckbox = new UICheckbox('Show idle ghost (blue)', w, showIdleGhost, function(c:Bool) {
				showIdleGhost = c;
				applyGhosts();
			});
			idleBox.y = y;
			pane.content.addChild(idleBox);
			y += 58;

			var opacity:UISlider = new UISlider('Opacity:', w, 0.1, 1, ghostAlpha, function(v:Float) {
				ghostAlpha = v;
				applyGhosts();
			});
			opacity.y = y;
			pane.content.addChild(opacity);
			y += 60;

			var clear:UIButton = new UIButton('Hide both', w, 44, function() {
				showLoopGhost = false;
				showIdleGhost = false;
				applyGhosts();
				openGhostPage();
			});
			clear.danger = true;
			clear.y = y;
			pane.content.addChild(clear);
			y += 54;

			var hint:UILabel = new UILabel('The portrait itself shows the offset you are editing; the ghosts are the other pose, held still to line it up against.',
				13, 2);
			hint.wrapWidth = w;
			hint.y = y;
			pane.content.addChild(hint);
			return y + hint.measure() + 8;
		});
	}

	/** Pushes the ghost toggles + opacity onto the two overlay sprites and the rail button. **/
	function applyGhosts():Void {
		ghostLoop.visible = showLoopGhost;
		ghostIdle.visible = showIdleGhost;
		ghostLoop.alpha = ghostAlpha;
		ghostIdle.alpha = ghostAlpha;
		if (ghostBtn != null)
			ghostBtn.label = 'GHOSTS: ' + (showLoopGhost || showIdleGhost ? 'ON' : 'OFF');
	}

	function nudge(dx:Int, dy:Int):Void {
		var a:DialogueAnimArray = currentAnim();
		if (a == null)
			return;

		var arr:Array<Int> = (offsetMode == 0) ? a.loop_offsets : a.idle_offsets;
		arr[0] += dx * 5;
		arr[1] += dy * 5;
		markDirty();
		applyOffsets();
	}

	function openPortraitPage():Void {
		shell.openPage('PORTRAIT', function(pane:UIScrollPane):Float {
			var w:Float = shell.pageWidth();
			var y:Float = 6;

			var name:UITextInput = new UITextInput('Portrait json:', w, characterName, function(v:String) {
				characterName = v.trim();
				markDirty();
				loadPortrait(characterName);
			});
			name.y = y;
			pane.content.addChild(name);
			y += 56;

			var img:UITextInput = new UITextInput('Image (dialogue/...):', w, character.jsonFile.image, function(v:String) {
				character.jsonFile.image = v.trim();
				markDirty();
				reloadCharacter();
			});
			img.y = y;
			pane.content.addChild(img);
			y += 56;

			var sc:UIStepper = new UIStepper('Scale:', w, character.jsonFile.scale, 0.05, function(v:Float) {
				character.jsonFile.scale = v;
				markDirty();
				reloadCharacter();
			});
			sc.min = 0.1;
			sc.max = 10;
			sc.decimals = 2;
			sc.y = y;
			pane.content.addChild(sc);
			y += 56;

			var pos:UIDropdown = new UIDropdown('Dialogue side:', w, function(_:Int, v:String) {
				character.jsonFile.dialogue_pos = v;
				markDirty();
				reloadCharacter();
			});
			pos.setItems(['left', 'center', 'right']);
			pos.select(['left', 'center', 'right'].indexOf(character.jsonFile.dialogue_pos));
			pos.y = y;
			pane.content.addChild(pos);
			y += 48;
			return y;
		});
	}

	function openAnimPage():Void {
		shell.openPage('ANIMATIONS', function(pane:UIScrollPane):Float {
			var w:Float = shell.pageWidth();
			var y:Float = 6;

			var nameIn:UITextInput = new UITextInput('Anim name:', w, curSelectedAnim != null ? curSelectedAnim : '', null);
			nameIn.y = y;
			pane.content.addChild(nameIn);
			y += 56;

			var cur:DialogueAnimArray = currentAnim();

			var loopIn:UITextInput = new UITextInput('Loop name (.XML):', w, cur != null ? cur.loop_name : '', null);
			loopIn.y = y;
			pane.content.addChild(loopIn);
			y += 56;

			var idleIn:UITextInput = new UITextInput('Idle name (.XML):', w, cur != null ? cur.idle_name : '', null);
			idleIn.y = y;
			pane.content.addChild(idleIn);
			y += 56;

			var addBtn:UIButton = new UIButton('Add / Update', w, 40, function() {
				addOrUpdateAnim(nameIn.text.trim(), loopIn.text, idleIn.text);
				openAnimPage();
			}, true);
			addBtn.y = y;
			pane.content.addChild(addBtn);
			y += 48;

			var remBtn:UIButton = new UIButton('Remove Selected', w, 40, function() {
				removeAnim(nameIn.text.trim());
				openAnimPage();
			});
			remBtn.danger = true;
			remBtn.y = y;
			pane.content.addChild(remBtn);
			y += 52;

			var hdr:UILabel = new UILabel('ANIMATIONS', 12, 2);
			hdr.y = y;
			pane.content.addChild(hdr);
			y += 24;

			for (a in character.jsonFile.animations) {
				var an:String = a.anim;
				var row:UIButton = new UIButton(an, w, 40, function() selectAnim(an));
				row.y = y;
				pane.content.addChild(row);
				y += 46;
			}
			return y;
		});
	}

	inline function currentAnim():DialogueAnimArray
		return (curSelectedAnim != null
			&& character.dialogueAnimations.exists(curSelectedAnim)) ? character.dialogueAnimations.get(curSelectedAnim) : null;

	function loadPortrait(name:String):Void {
		character.reloadCharacterJson(name);
		reloadCharacter();
	}

	function selectAnim(anim:String):Void {
		curSelectedAnim = anim;
		var a:DialogueAnimArray = currentAnim();
		if (a != null) {
			ghostLoop.playAnim(a.anim);
			ghostIdle.playAnim(a.anim, true);
			character.playAnim(a.anim, offsetMode == 1);
		}
		applyOffsets();
	}

	function addOrUpdateAnim(name:String, loopName:String, idleName:String):Void {
		if (name.length < 1)
			return;
		var existing:DialogueAnimArray = null;
		for (a in character.jsonFile.animations)
			if (a.anim.trim() == name)
				existing = a;
		if (existing != null) {
			existing.loop_name = loopName;
			existing.idle_name = idleName;
		} else {
			character.jsonFile.animations.push({
				anim: name,
				loop_name: loopName,
				loop_offsets: [0, 0],
				idle_name: idleName,
				idle_offsets: [0, 0]
			});
		}
		markDirty();
		character.reloadAnimations();
		ghostLoop.reloadAnimations();
		ghostIdle.reloadAnimations();
		selectAnim(name);
	}

	function removeAnim(name:String):Void {
		for (a in character.jsonFile.animations.copy())
			if (a.anim.trim() == name)
				character.jsonFile.animations.remove(a);
		markDirty();
		character.reloadAnimations();
		ghostLoop.reloadAnimations();
		ghostIdle.reloadAnimations();
		if (curSelectedAnim == name)
			curSelectedAnim = character.jsonFile.animations.length > 0 ? character.jsonFile.animations[0].anim : null;
		if (curSelectedAnim != null)
			selectAnim(curSelectedAnim);
	}

	function reloadCharacter():Void {
		for (c in [character, ghostLoop, ghostIdle]) {
			c.frames = Paths.getSparrowAtlas('dialogue/' + character.jsonFile.image);
			c.jsonFile = character.jsonFile;
			c.reloadAnimations();
			c.setGraphicSize(Std.int(c.width * DialogueCharacter.DEFAULT_SCALE * character.jsonFile.scale));
			c.updateHitbox();
		}
		character.x = DialogueBoxPsych.LEFT_CHAR_X;
		character.y = DialogueBoxPsych.DEFAULT_CHAR_Y;
		switch (character.jsonFile.dialogue_pos) {
			case 'right':
				character.x = FlxG.width - character.width + DialogueBoxPsych.RIGHT_CHAR_X;
			case 'center':
				character.x = FlxG.width / 2 - character.width / 2;
		}
		character.x += character.jsonFile.position[0];
		character.y += character.jsonFile.position[1];
		ghostLoop.setPosition(character.x, character.y);
		ghostIdle.setPosition(character.x, character.y);

		if (character.jsonFile.animations.length > 0) {
			curSelectedAnim = character.jsonFile.animations[0].anim;
			selectAnim(curSelectedAnim);
		}
		updateStatus();
	}

	function applyOffsets():Void {
		var a:DialogueAnimArray = currentAnim();
		if (a == null)
			return;
		ghostLoop.offset.set(a.loop_offsets[0], a.loop_offsets[1]);
		ghostIdle.offset.set(a.idle_offsets[0], a.idle_offsets[1]);
		// The portrait carries the offsets of the pose being edited, so nudging/dragging moves IT and not
		// just a ghost -- the ghosts are optional references.
		var live:Array<Int> = (offsetMode == 0) ? a.loop_offsets : a.idle_offsets;
		character.offset.set(live[0], live[1]);
		updateStatus();
	}

	function updateStatus():Void {
		if (shell == null)
			return;
		var a:DialogueAnimArray = currentAnim();
		var off:String = (a != null) ? (offsetMode == 0 ? 'loop ${a.loop_offsets}' : 'idle ${a.idle_offsets}') : '-';
		shell.setStatus('PORTRAIT EDITOR    $characterName    anim: ${curSelectedAnim != null ? curSelectedAnim : '-'}    mode: ${offsetMode == 0 ? 'LOOP' : 'IDLE'} $off');
	}

	function saveCharacter():Void {
		saveFile('$characterName.json', haxe.Json.stringify(character.jsonFile, '\t'));
	}

	// The unsaved-changes exit prompt (MobileEditorBase) saves through this hook.
	override function saveDocument(?onSaved:Void->Void):Void {
		saveFile('$characterName.json', haxe.Json.stringify(character.jsonFile, '	'), onSaved);
	}

	function openPortrait():Void {
		openFile('$characterName.json', 'Open a portrait json', function(data:String, path:String):Void {
			try {
				character.jsonFile = cast haxe.Json.parse(data);
				characterName = baseName(path);
				unsavedProgress = false;
				reloadCharacter();
			} catch (e:Dynamic) {
				UIToast.show('Load failed: ${Std.string(e)}');
			}
		});
	}

	static function baseName(path:String):String {
		if (path == null)
			return 'bf';
		var b:String = path;
		var slash:Int = Std.int(Math.max(b.lastIndexOf('/'), b.lastIndexOf('\\')));
		if (slash >= 0)
			b = b.substr(slash + 1);
		if (StringTools.endsWith(b, '.json'))
			b = b.substr(0, b.length - 5);
		return b.length > 0 ? b : 'bf';
	}
}
