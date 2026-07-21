package editors.mobile;

import flixel.FlxG;
import flixel.math.FlxMath;
import flixel.util.FlxColor;
import objects.Character;
import objects.Character.AnimArray;
import objects.HealthIcon;
import editors.content.PsychJsonPrinter;
import smidr.UILocale;
import smidr.UIFonts;
import smidr.widgets.UIButton;
import smidr.widgets.UICheckbox;
import smidr.widgets.UIDropdown;
import smidr.widgets.UILabel;
import smidr.widgets.UIScrollPane;
import smidr.widgets.UIStepper;
import smidr.widgets.UITextInput;
import smidr.overlays.UIToast;

/**
 * Touch-native Character editor: the desktop `CharacterEditorState`'s full character config on the mobile
 * shell. The character sits on a gesture-driven canvas (pan/zoom to inspect); dragging it sets the current
 * animation's offset (plus a nudge action bar). Rail pages hold CHARACTER / ANIMATION / SETTINGS. Saves the
 * character JSON (`<name>.json`) with the same serialization + key order as the desktop editor, so files
 * interop.
 */
class MobileCharacterEditorState extends MobileEditorBase {
	var character:Character;
	var healthIcon:HealthIcon;
	var charName:String = 'bf';
	var isPlayer:Bool = false;
	var curAnim:Int = 0;

	var animBtn:UIButton;

	override function create():Void {
		initPsychCamera();
		FlxG.camera.bgColor = 0xFF1A1A2E;

		UILocale.translate = function(k:String, f:String):String return Language.getPhrase(k, f);
		UIFonts.register('assets/fonts/vcr.ttf');

		buildChrome();
		loadChar(charName);

		setupCanvas();
		gestures.onDragMove = function(_x:Float, _y:Float, dx:Float, dy:Float):Void {
			character.offset.x += dx;
			character.offset.y += dy;
			commitOffset();
		};

		super.create();
	}

	function loadChar(name:String):Void {
		if (character != null)
			remove(character);
		if (healthIcon != null)
			remove(healthIcon);

		charName = name;
		character = new Character(0, 0, name, isPlayer);
		character.screenCenter();
		add(character);

		healthIcon = new HealthIcon(character.healthIcon, false, false);
		healthIcon.x = 20;
		healthIcon.y = FlxG.height - 170;
		add(healthIcon);

		curAnim = 0;
		playCurrent();
		updateStatus();
	}

	inline function anims():Array<AnimArray>
		return (character != null && character.animationsArray != null) ? character.animationsArray : [];

	function playCurrent():Void {
		if (character == null)
			return;
		if (anims().length > 0) {
			curAnim = FlxMath.wrap(curAnim, 0, anims().length - 1);
			character.playAnim(anims()[curAnim].anim, true);
		}
	}

	function commitOffset():Void {
		if (character == null || anims().length < 1)
			return;
		var a:AnimArray = anims()[curAnim];
		var authored:Array<Float> = character.getAuthoredOffset();
		a.offsets[0] = Std.int(authored[0]);
		a.offsets[1] = Std.int(authored[1]);
		character.addOffset(a.anim, authored[0], authored[1]);
		updateStatus();
	}

	function buildChrome():Void {
		shell = new MobileEditorShell();
		shell.addLeft('< EXIT', exitEditor);
		shell.railGap(true);
		shell.addLeft('OPEN', openCharacterFile);
		shell.addLeft('SAVE', saveCharacter, true);

		shell.addRight('CHARACTER', openCharacterPage);
		shell.addRight('ANIMS', openAnimPage);
		shell.addRight('SETTINGS', openSettingsPage);
		animBtn = shell.addRight('ANIM: -', function() changeAnim(1));
		shell.railGap(false);
		shell.addRight('? GUIDE', function() shell.showGuide([
			'CHARACTER  load a character, image, scale, playable, flip, AA',
			'ANIMS      add / update / remove / pick animations',
			'SETTINGS   sing length, icon + colors, position, camera, vocals',
			'DRAG       move the current animation\'s offset',
			'ACTION BAR nudge the offset, prev/next animation, play',
			'SAVE       writes <name>.json'
		]));

		shell.setActionBar([
			{label: '< ', cb: function() nudge(-1, 0)},
			{label: ' >', cb: function() nudge(1, 0)},
			{label: '^', cb: function() nudge(0, -1)},
			{label: 'v', cb: function() nudge(0, 1)},
			{label: 'PLAY', cb: playCurrent}
		]);
		shell.showActionBar(true);
	}

	function changeAnim(delta:Int):Void {
		if (character == null || anims().length < 1)
			return;
		curAnim = FlxMath.wrap(curAnim + delta, 0, anims().length - 1);
		playCurrent();
		if (animBtn != null)
			animBtn.label = 'ANIM: ${anims()[curAnim].anim}';
		updateStatus();
	}

	function nudge(dx:Int, dy:Int):Void {
		if (character == null)
			return;
		character.offset.x += dx * 5;
		character.offset.y += dy * 5;
		commitOffset();
	}

	function openCharacterPage():Void {
		shell.openPage('CHARACTER', function(pane:UIScrollPane):Float {
			var w:Float = shell.pageWidth();
			var y:Float = 6;

			var nameIn:UITextInput = new UITextInput('Character:', w, charName, null);
			nameIn.y = y;
			pane.content.addChild(nameIn);
			y += 56;

			var loadBtn:UIButton = new UIButton('Load Character', w, 40, function() loadChar(nameIn.text.trim()), true);
			loadBtn.y = y;
			pane.content.addChild(loadBtn);
			y += 48;

			var img:UITextInput = new UITextInput('Image file name:', w, character.imageFile, function(v:String) {
				character.imageFile = v;
			});
			img.y = y;
			pane.content.addChild(img);
			y += 56;

			var reImg:UIButton = new UIButton('Reload Image', w, 36, function() reloadImage());
			reImg.y = y;
			pane.content.addChild(reImg);
			y += 44;

			var sc:UIStepper = new UIStepper('Scale:', w, character.jsonScale, 0.1, function(v:Float) {
				character.jsonScale = v;
				character.scale.set(v, v);
				character.updateHitbox();
			});
			sc.min = 0.05;
			sc.max = 30;
			sc.decimals = 2;
			sc.y = y;
			pane.content.addChild(sc);
			y += 56;

			var player:UICheckbox = new UICheckbox('Playable Character', w, isPlayer, function(v:Bool) {
				isPlayer = v;
				loadChar(charName);
			});
			player.y = y;
			pane.content.addChild(player);
			y += 44;

			var flip:UICheckbox = new UICheckbox('Flip X', w, character.originalFlipX, function(v:Bool) {
				character.originalFlipX = v;
				character.flipX = v;
			});
			flip.y = y;
			pane.content.addChild(flip);
			y += 44;

			var aa:UICheckbox = new UICheckbox('No antialiasing', w, character.noAntialiasing, function(v:Bool) {
				character.noAntialiasing = v;
				character.antialiasing = !v && ClientPrefs.data.antialiasing;
			});
			aa.y = y;
			pane.content.addChild(aa);
			return y + 44;
		});
	}

	function openAnimPage():Void {
		shell.openPage('ANIMATIONS', function(pane:UIScrollPane):Float {
			var w:Float = shell.pageWidth();
			var y:Float = 6;

			var cur:AnimArray = (anims().length > 0) ? anims()[curAnim] : null;

			var animIn:UITextInput = new UITextInput('Animation name:', w, cur != null ? cur.anim : '', null);
			animIn.y = y;
			pane.content.addChild(animIn);
			y += 56;

			var symbolIn:UITextInput = new UITextInput('Symbol/Prefix:', w, cur != null ? cur.name : '', null);
			symbolIn.y = y;
			pane.content.addChild(symbolIn);
			y += 56;

			var fps:UIStepper = new UIStepper('Framerate:', w, cur != null ? cur.fps : 24, 1, null);
			fps.min = 0;
			fps.max = 240;
			fps.decimals = 0;
			fps.y = y;
			pane.content.addChild(fps);
			y += 56;

			var indicesIn:UITextInput = new UITextInput('Indices (comma):', w, cur != null ? cur.indices.join(',') : '', null);
			indicesIn.y = y;
			pane.content.addChild(indicesIn);
			y += 56;

			var loop:UICheckbox = new UICheckbox('Looped', w, cur != null && cur.loop, null);
			loop.y = y;
			pane.content.addChild(loop);
			y += 44;

			var addBtn:UIButton = new UIButton('Add / Update', w, 40, function() {
				addOrUpdate(animIn.text.trim(), symbolIn.text.trim(), Std.int(fps.value), loop.checked, parseIndices(indicesIn.text));
				openAnimPage();
			}, true);
			addBtn.y = y;
			pane.content.addChild(addBtn);
			y += 48;

			var remBtn:UIButton = new UIButton('Remove Selected', w, 40, function() {
				removeAnim(animIn.text.trim());
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
			for (i in 0...anims().length) {
				var idx:Int = i;
				var a:AnimArray = anims()[i];
				var row:UIButton = new UIButton(a.anim, w, 40, function() {
					curAnim = idx;
					playCurrent();
					animBtn.label = 'ANIM: ${a.anim}';
					updateStatus();
				}, i == curAnim);
				row.y = y;
				pane.content.addChild(row);
				y += 46;
			}
			return y;
		});
	}

	function openSettingsPage():Void {
		shell.openPage('SETTINGS', function(pane:UIScrollPane):Float {
			var w:Float = shell.pageWidth();
			var y:Float = 6;

			var sing:UIStepper = new UIStepper('Sing Anim length:', w, character.singDuration, 0.1, function(v:Float) character.singDuration = v);
			sing.min = 0;
			sing.max = 999;
			sing.decimals = 1;
			sing.y = y;
			pane.content.addChild(sing);
			y += 56;

			var icon:UITextInput = new UITextInput('Health icon:', w, character.healthIcon, function(v:String) {
				character.healthIcon = v;
				if (healthIcon != null)
					healthIcon.changeIcon(v);
			});
			icon.y = y;
			pane.content.addChild(icon);
			y += 56;

			var labels:Array<String> = ['Health R:', 'Health G:', 'Health B:'];
			for (i in 0...3) {
				var ch:Int = i;
				var st:UIStepper = new UIStepper(labels[i], w, character.healthColorArray[i], 1, function(v:Float) character.healthColorArray[ch] = Std.int(v));
				st.min = 0;
				st.max = 255;
				st.decimals = 0;
				st.y = y;
				pane.content.addChild(st);
				y += 52;
			}

			var px:UIStepper = new UIStepper('Char X:', w, character.positionArray[0], 5, function(v:Float) character.positionArray[0] = v);
			px.decimals = 0;
			px.y = y;
			pane.content.addChild(px);
			y += 52;

			var py:UIStepper = new UIStepper('Char Y:', w, character.positionArray[1], 5, function(v:Float) character.positionArray[1] = v);
			py.decimals = 0;
			py.y = y;
			pane.content.addChild(py);
			y += 52;

			var cx:UIStepper = new UIStepper('Camera X:', w, character.cameraPosition[0], 5, function(v:Float) character.cameraPosition[0] = v);
			cx.decimals = 0;
			cx.y = y;
			pane.content.addChild(cx);
			y += 52;

			var cy:UIStepper = new UIStepper('Camera Y:', w, character.cameraPosition[1], 5, function(v:Float) character.cameraPosition[1] = v);
			cy.decimals = 0;
			cy.y = y;
			pane.content.addChild(cy);
			y += 52;

			var vocals:UITextInput = new UITextInput('Vocals file:', w, character.vocalsFile, function(v:String) character.vocalsFile = v);
			vocals.y = y;
			pane.content.addChild(vocals);
			y += 56;

			var loopHold:UICheckbox = new UICheckbox('Loop sing on hold', w, character.loopSingOnHold, function(v:Bool) character.loopSingOnHold = v);
			loopHold.y = y;
			pane.content.addChild(loopHold);
			return y + 44;
		});
	}

	function parseIndices(s:String):Array<Int> {
		var out:Array<Int> = [];
		for (p in s.split(',')) {
			var t:String = p.trim();
			if (t.length > 0) {
				var n:Null<Int> = Std.parseInt(t);
				if (n != null)
					out.push(n);
			}
		}
		return out;
	}

	function addOrUpdate(name:String, symbol:String, fps:Int, loop:Bool, indices:Array<Int>):Void {
		if (name.length < 1)
			return;

		var existing:AnimArray = null;
		for (a in anims())
			if (a.anim == name)
				existing = a;

		var offsets:Array<Int> = (existing != null) ? existing.offsets : [0, 0];
		if (existing != null)
			anims().remove(existing);

		var na:AnimArray = {
			anim: name,
			name: symbol,
			fps: fps,
			loop: loop,
			indices: indices,
			offsets: offsets
		};
		anims().push(na);

		if (indices != null && indices.length > 0)
			character.animation.addByIndices(name, symbol, indices, '', fps, loop);
		else
			character.animation.addByPrefix(name, symbol, fps, loop);
		character.addOffset(name, offsets[0], offsets[1]);

		curAnim = anims().indexOf(na);
		playCurrent();
		if (animBtn != null)
			animBtn.label = 'ANIM: $name';
	}

	function removeAnim(name:String):Void {
		if (character == null)
			return;
		for (a in anims().copy())
			if (a.anim == name)
				anims().remove(a);
		if (character != null && character.animOffsets != null)
			character.animOffsets.remove(name);

		if (curAnim >= anims().length)
			curAnim = anims().length - 1;
		playCurrent();
	}

	function reloadImage():Void {
		if (character == null)
			return;
		var lastAnim:String = (anims().length > 0) ? anims()[curAnim].anim : '';
		character.frames = Paths.getSparrowAtlas(character.imageFile);

		for (a in anims()) {
			if (a.indices != null && a.indices.length > 0)
				character.animation.addByIndices(a.anim, a.name, a.indices, '', a.fps, a.loop);
			else
				character.animation.addByPrefix(a.anim, a.name, a.fps, a.loop);
			character.addOffset(a.anim, a.offsets[0], a.offsets[1]);
		}

		character.scale.set(character.jsonScale, character.jsonScale);
		character.updateHitbox();

		if (lastAnim.length > 0)
			character.playAnim(lastAnim, true);
	}

	function updateStatus():Void {
		if (shell == null)
			return;
		var a:AnimArray = (anims().length > 0) ? anims()[curAnim] : null;
		shell.setStatus('CHAR EDITOR    $charName    anim: ${a != null ? a.anim : '-'}    offset: ${a != null ? a.offsets : []}');
	}

	function saveCharacter():Void {
		var json:Dynamic = {
			"animations": character.animationsArray,
			"image": character.imageFile,
			"scale": character.jsonScale,
			"sing_duration": character.singDuration,
			"healthicon": character.healthIcon,
			"position": character.positionArray,
			"camera_position": character.cameraPosition,
			"flip_x": character.originalFlipX,
			"no_antialiasing": character.noAntialiasing,
			"loop_sing_on_hold": character.loopSingOnHold,
			"swfMode": character.swfMode,
			"healthbar_colors": character.healthColorArray,
			"vocals_file": character.vocalsFile,
			"_editor_isPlayer": character.isPlayer
		};
		var data:String = PsychJsonPrinter.print(json, ['offsets', 'position', 'healthbar_colors', 'camera_position', 'indices']);
		saveFile('$charName.json', data);
	}

	function openCharacterFile():Void {
		openFile('$charName.json', 'Open a character json', function(data:String, path:String):Void {
			try {
				var cf:Dynamic = haxe.Json.parse(data);
				charName = baseName(path);
				character.imageFile = cf.image;
				character.jsonScale = (cf.scale != null) ? cf.scale : 1;
				character.singDuration = (cf.sing_duration != null) ? cf.sing_duration : 4;
				character.healthIcon = (cf.healthicon != null) ? cf.healthicon : 'face';
				character.positionArray = (cf.position != null) ? cf.position : [0, 0];
				character.cameraPosition = (cf.camera_position != null) ? cf.camera_position : [0, 0];
				character.originalFlipX = cf.flip_x == true;
				character.flipX = character.originalFlipX;
				character.noAntialiasing = cf.no_antialiasing == true;
				character.healthColorArray = (cf.healthbar_colors != null) ? cf.healthbar_colors : [255, 0, 0];
				character.vocalsFile = (cf.vocals_file != null) ? cf.vocals_file : '';
				character.loopSingOnHold = cf.loop_sing_on_hold == true;
				character.animationsArray = (cf.animations != null) ? cf.animations : [];
				character.animOffsets = new Map();
				if (healthIcon != null)
					healthIcon.changeIcon(character.healthIcon);
				curAnim = 0;
				reloadImage();
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
