package editors.mobile;

import flixel.FlxCamera;
import flixel.FlxG;
import flixel.FlxSprite;
import flixel.math.FlxMath;
import flixel.math.FlxPoint;
import flixel.math.FlxRect;
import flixel.util.FlxColor;
import flixel.util.FlxDestroyUtil;
import objects.Character;
import objects.Character.AnimArray;
import objects.Character.CharacterFile;
import objects.Bar;
import objects.HealthIcon;
import editors.content.PsychJsonPrinter;
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
 * Touch-native Character editor with full desktop parity: the character sits in the same reference
 * stage (silhouettes + stage graphics + camera-follow crosshair) as the desktop `CharacterEditorState`,
 * on a gesture-driven magnifying canvas. One finger drags the camera, two fingers pinch-zoom, and a
 * finger grabbing the character sets the current animation's offset (with a nudge action bar). Rail
 * pages hold CHARACTER / ANIMS / SETTINGS / GHOST; the health icon + bar preview the icon colors.
 *
 * Serializes the character JSON (`<name>.json`) with the same key order and offset conventions as the
 * desktop editor (via `PsychJsonPrinter` and `Character.getAuthoredOffset`), so files interop, and it
 * loads Sparrow, multi-atlas and Animate-atlas characters through the same `Character` paths.
 */
class MobileCharacterEditorState extends MobileEditorBase {
	var character:Character;
	var ghost:FlxSprite;
	var animateGhost:FlxAnimate;
	var animateGhostImage:String;
	var ghostAlpha:Float = 0.6;

	var silhouettes:FlxSpriteGroup;
	var cameraFollowPointer:FlxSprite;
	var dadPosition:FlxPoint = FlxPoint.get();
	var bfPosition:FlxPoint = FlxPoint.get();

	var hudCam:FlxCamera;
	var healthBar:Bar;
	var healthIcon:HealthIcon;

	var charName:String = 'bf';
	var curAnim:Int = 0;

	var animBtn:UIButton;

	// ANIMATIONS page fields, held so selecting another animation can refill them in place.
	var animNameIn:UITextInput;
	var animSymbolIn:UITextInput;
	var animFpsStepper:UIStepper;
	var animIndicesIn:UITextInput;
	var animLoopCheck:UICheckbox;
	var silhouetteBtn:UIButton;

	final _bounds:FlxRect = FlxRect.get();
	final _point:FlxPoint = FlxPoint.get();

	static inline var ZOOM_MIN:Float = 0.2;
	static inline var ZOOM_MAX:Float = 3.0;
	static inline var assetFolder:String = 'week1';

	override function create():Void {
		Paths.clearStoredMemory();
		Paths.clearUnusedMemory();

		initPsychCamera();
		FlxG.camera.bgColor = 0xFF1A1A2E;
		setupCanvas();
		previewCam.zoom = 0.9;

		hudCam = new FlxCamera();
		hudCam.bgColor.alpha = 0;
		FlxG.cameras.add(hudCam, false);

		UILocale.translate = function(k:String, f:String):String return Language.getPhrase(k, f);
		UIFonts.register('assets/fonts/vcr.ttf');

		loadBG();

		silhouettes = new FlxSpriteGroup();
		silhouettes.cameras = [previewCam];
		add(silhouettes);

		var dad:FlxSprite = new FlxSprite(dadPosition.x, dadPosition.y).loadGraphic(Paths.image('editors/silhouetteDad'));
		dad.antialiasing = ClientPrefs.data.antialiasing;
		dad.active = false;
		dad.offset.set(-4, 1);
		silhouettes.add(dad);

		var boyfriend:FlxSprite = new FlxSprite(bfPosition.x, bfPosition.y + 350).loadGraphic(Paths.image('editors/silhouetteBF'));
		boyfriend.antialiasing = ClientPrefs.data.antialiasing;
		boyfriend.active = false;
		boyfriend.offset.set(-6, 2);
		silhouettes.add(boyfriend);

		silhouettes.alpha = 0.25;

		ghost = new FlxSprite();
		ghost.visible = false;
		ghost.alpha = ghostAlpha;
		ghost.cameras = [previewCam];
		add(ghost);

		addCharacter();

		cameraFollowPointer = new FlxSprite();
		cameraFollowPointer.makeGraphic(40, 40, FlxColor.TRANSPARENT, true);
		for (i in 0...40) {
			cameraFollowPointer.pixels.setPixel32(20, i, FlxColor.WHITE);
			cameraFollowPointer.pixels.setPixel32(i, 20, FlxColor.WHITE);
		}
		cameraFollowPointer.updateHitbox();
		cameraFollowPointer.cameras = [previewCam];
		add(cameraFollowPointer);

		healthBar = new Bar(30, FlxG.height - 60);
		healthBar.scrollFactor.set();
		healthBar.cameras = [hudCam];
		add(healthBar);

		healthIcon = new HealthIcon(character.healthIcon, false, false);
		healthIcon.x = 30;
		healthIcon.y = FlxG.height - 140;
		healthIcon.cameras = [hudCam];
		add(healthIcon);

		buildChrome();

		gestures.onDragStart = onDragStartCanvas;
		gestures.onDragMove = onDragMoveCanvas;
		gestures.onPan = onPan;
		gestures.onZoom = onZoom;

		updateHealthBar();
		updatePointerPos(true);
		character.finishAnimation();

		super.create();
	}

	inline function loadBG():Void {
		var lastLoaded:String = Paths.currentLevel;
		Paths.currentLevel = assetFolder;

		var bg:FlxSprite = editorBackdrop('stageback', -600, -200, 0.9, 0.9);
		bg.cameras = [previewCam];
		add(bg);

		var stageFront:FlxSprite = editorBackdrop('stagefront', -650, 600, 0.9, 0.9);
		stageFront.setGraphicSize(Std.int(stageFront.width * 1.1));
		stageFront.updateHitbox();
		stageFront.cameras = [previewCam];
		add(stageFront);

		dadPosition.set(100, 100);
		bfPosition.set(770, 100);

		Paths.currentLevel = lastLoaded;
	}

	/** World x of a canvas (game-px) point on the magnifying preview camera. Mirrors `FlxPointer` math. **/
	inline function worldX(screenX:Float):Float {
		return (screenX - previewCam.x) / previewCam.zoom + previewCam.viewMarginX + previewCam.scroll.x;
	}

	inline function worldY(screenY:Float):Float {
		return (screenY - previewCam.y) / previewCam.zoom + previewCam.viewMarginY + previewCam.scroll.y;
	}

	function onPan(dx:Float, dy:Float):Void {
		previewCam.scroll.x -= dx / previewCam.zoom;
		previewCam.scroll.y -= dy / previewCam.zoom;
	}

	function onZoom(factor:Float, focalX:Float, focalY:Float):Void {
		var z:Float = previewCam.zoom * factor;
		z = (z < ZOOM_MIN) ? ZOOM_MIN : (z > ZOOM_MAX ? ZOOM_MAX : z);
		var beforeX:Float = worldX(focalX);
		var beforeY:Float = worldY(focalY);
		previewCam.zoom = z;
		previewCam.scroll.x += beforeX - worldX(focalX);
		previewCam.scroll.y += beforeY - worldY(focalY);
		updateStatus();
	}

	/** A press that lands on the character is claimed as an offset drag; empty space stays a camera pan. **/
	function onDragStartCanvas(x:Float, y:Float):Bool {
		if (character == null)
			return false;
		character.getScreenBounds(_bounds, previewCam);
		_bounds.x -= 20;
		_bounds.y -= 20;
		_bounds.width += 40;
		_bounds.height += 40;
		return _bounds.containsXY(x, y);
	}

	function onDragMoveCanvas(dx:Float, dy:Float, _x:Float, _y:Float):Void {
		if (character == null)
			return;
		character.offset.x -= dx / previewCam.zoom;
		character.offset.y -= dy / previewCam.zoom;
		commitOffset();
	}

	inline function updatePointerPos(?snap:Bool = true):Void {
		if (character == null || cameraFollowPointer == null)
			return;

		var offX:Float = 0;
		var offY:Float = 0;
		if (!character.isPlayer) {
			offX = character.getMidpoint(_point).x + 150 + character.cameraPosition[0];
			offY = character.getMidpoint(_point).y - 100 + character.cameraPosition[1];
		} else {
			offX = character.getMidpoint(_point).x - 100 - character.cameraPosition[0];
			offY = character.getMidpoint(_point).y - 100 + character.cameraPosition[1];
		}
		cameraFollowPointer.setPosition(offX, offY);

		if (snap) {
			previewCam.scroll.x = cameraFollowPointer.getMidpoint(_point).x - FlxG.width / 2;
			previewCam.scroll.y = cameraFollowPointer.getMidpoint(_point).y - FlxG.height / 2;
		}
	}

	inline function updateCharacterPositions():Void {
		if (character == null)
			return;
		if (!character.isPlayer)
			character.setPosition(dadPosition.x, dadPosition.y);
		else
			character.setPosition(bfPosition.x, bfPosition.y);

		character.x += character.positionArray[0];
		character.y += character.positionArray[1];
		updatePointerPos(false);
	}

	function addCharacter(reload:Bool = false):Void {
		var pos:Int = -1;
		if (character != null) {
			pos = members.indexOf(character);
			remove(character);
			character.destroy();
		}

		var isPlayer:Bool = (reload && character != null) ? character.isPlayer : !predictCharacterIsNotPlayer(charName);
		character = new Character(0, 0, charName, isPlayer);
		if (!reload && character.editorIsPlayer != null && isPlayer != character.editorIsPlayer) {
			character.isPlayer = !character.isPlayer;
			character.flipX = (character.originalFlipX != character.isPlayer);
		}
		character.debugMode = true;
		character.missingCharacter = false;
		character.cameras = [previewCam];

		if (pos > -1)
			insert(pos, character);
		else
			add(character);

		updateCharacterPositions();
		reloadAnimList();
		if (healthBar != null && healthIcon != null)
			updateHealthBar();
	}

	inline function predictCharacterIsNotPlayer(name:String):Bool {
		return (name != 'bf' && !name.startsWith('bf-') && !name.endsWith('-player') && !name.endsWith('-playable') && !name.endsWith('-dead'))
			|| name.endsWith('-opponent')
			|| name.startsWith('gf-')
			|| name.endsWith('-gf')
			|| name == 'gf';
	}

	inline function anims():Array<AnimArray>
		return (character != null && character.animationsArray != null) ? character.animationsArray : [];

	inline function reloadAnimList():Void {
		if (anims().length > 0)
			character.playAnim(anims()[0].anim, true);
		curAnim = 0;
		if (animBtn != null)
			animBtn.label = 'ANIM: ${anims().length > 0 ? anims()[0].anim : '-'}';
		syncAnimFields();
		updateStatus();
	}

	function playCurrent():Void {
		if (character == null || anims().length < 1)
			return;
		curAnim = FlxMath.wrap(curAnim, 0, anims().length - 1);
		character.playAnim(anims()[curAnim].anim, true);
		updateStatus();
	}

	function changeAnim(delta:Int):Void {
		if (character == null || anims().length < 1)
			return;
		curAnim = FlxMath.wrap(curAnim + delta, 0, anims().length - 1);
		character.playAnim(anims()[curAnim].anim, true);
		if (animBtn != null)
			animBtn.label = 'ANIM: ${anims()[curAnim].anim}';
		syncAnimFields();
		updateStatus();
	}

	function commitOffset():Void {
		if (character == null || anims().length < 1)
			return;
		markDirty();
		var a:AnimArray = anims()[curAnim];
		var authored:Array<Float> = character.getAuthoredOffset();
		a.offsets[0] = Std.int(authored[0]);
		a.offsets[1] = Std.int(authored[1]);
		character.addOffset(a.anim, authored[0], authored[1]);
		updateStatus();
	}

	function nudge(dxSign:Int, dySign:Int):Void {
		if (character == null)
			return;
		character.offset.x += dxSign;
		character.offset.y += dySign;
		commitOffset();
	}

	/** Single frame-step of the current animation (both Sparrow and Animate atlases), pausing playback. **/
	function frameStep(dir:Int):Void {
		if (character == null || character.isAnimationNull())
			return;
		character.animPaused = true;

		var frames:Int = -1;
		var length:Int = -1;
		if (!character.isAnimateAtlas && character.animation.curAnim != null) {
			frames = character.animation.curAnim.curFrame;
			length = character.animation.curAnim.numFrames;
		} else if (character.isAnimateAtlas && character.atlas.anim != null && character.atlas.anim.curAnim != null) {
			frames = character.atlas.anim.curAnim.curFrame;
			length = character.atlas.anim.curAnim.numFrames;
		}
		if (length <= 0)
			return;

		frames = FlxMath.wrap(frames + dir, 0, length - 1);
		if (!character.isAnimateAtlas)
			character.animation.curAnim.curFrame = frames;
		else if (character.atlas.anim.curAnim != null)
			character.atlas.anim.curAnim.curFrame = frames;
		updateStatus();
	}

	/**
	 * Rebuilds the character from its image file, auto-detecting an Animate atlas
	 * (`images/<image>/Animation.json`) vs. a Sparrow multi-atlas, then re-adds every
	 * animation and restores the last-played one. Same logic as the desktop editor.
	 */
	function reloadCharacterImage():Void {
		if (character == null)
			return;
		var lastAnim:String = character.getAnimationName();
		var savedAnims:Array<AnimArray> = character.animationsArray.copy();

		character.atlas = FlxDestroyUtil.destroy(character.atlas);
		character.isAnimateAtlas = false;
		character.color = FlxColor.WHITE;
		character.alpha = 1;

		if (Paths.fileExists('images/' + character.imageFile + '/Animation.json', TEXT)) {
			character.atlas = new FlxAnimate();
			try {
				Paths.loadAnimateAtlas(character.atlas, character.imageFile, null, null, character.swfMode);
			} catch (e:Dynamic) {
				FlxG.log.warn('Could not load atlas ${character.imageFile}: $e');
			}
			character.isAnimateAtlas = true;
		} else {
			character.frames = Paths.getMultiAtlas(character.imageFile.split(','));
		}

		for (anim in savedAnims)
			addAnimation('' + anim.anim, '' + anim.name, anim.fps, !!anim.loop, anim.indices);

		character.scale.set(character.jsonScale, character.jsonScale);
		character.updateHitbox();

		if (savedAnims.length > 0) {
			if (lastAnim != null && lastAnim != '')
				character.playAnim(lastAnim, true);
			else
				character.dance();
		}
	}

	function addAnimation(anim:String, name:String, fps:Float, loop:Bool, indices:Array<Int>):Void {
		if (!character.isAnimateAtlas) {
			if (indices != null && indices.length > 0)
				character.animation.addByIndices(anim, name, indices, '', fps, loop);
			else
				character.animation.addByPrefix(anim, name, fps, loop);
		} else {
			if (indices != null && indices.length > 0)
				character.atlas.anim.addBySymbolIndices(anim, name, indices, fps, loop);
			else
				character.atlas.anim.addBySymbol(anim, name, fps, loop);
		}

		if (!character.hasAnimation(anim))
			character.addOffset(anim, 0, 0);
	}

	function buildChrome():Void {
		shell = new MobileEditorShell();
		shell.addLeft('< EXIT', exitEditor);
		shell.railGap(true);
		shell.addLeft('OPEN', openCharacterFile);
		shell.addLeft('SAVE', function() saveCharacter(), true);
		shell.railGap(true);
		shell.addLeft('GHOST', openGhostPage);
		silhouetteBtn = shell.addLeft('SILHOU: ON', toggleSilhouettes);
		shell.addLeft('CAM RESET', function() {
			previewCam.zoom = 0.9;
			updatePointerPos(true);
			updateStatus();
		});

		shell.addRight('CHARACTER', openCharacterPage);
		shell.addRight('ANIMS', openAnimPage);
		shell.addRight('SETTINGS', openSettingsPage);
		shell.railGap(false);
		animBtn = shell.addRight('ANIM: -', function() changeAnim(1));
		shell.addRight('FRAME <', function() frameStep(-1));
		shell.addRight('FRAME >', function() frameStep(1));
		shell.railGap(false);
		shell.addRight('? GUIDE', function() shell.showGuide([
			'DRAG CHAR    move the current animation\'s offset',
			'DRAG EMPTY   pan the camera around the stage',
			'PINCH        zoom in / out',
			'CHARACTER    load / template / image / scale / flip / AA',
			'ANIMS        add / update / remove / pick animations',
			'SETTINGS     sing length, icon + colors, position, camera',
			'GHOST        overlay a frozen pose to line up offsets',
			'ACTION BAR   nudge the offset, replay the animation',
			'SAVE         writes <name>.json'
		]));

		shell.setActionBar([
			{label: '< ', cb: function() nudge(1, 0)},
			{label: ' >', cb: function() nudge(-1, 0)},
			{label: '^', cb: function() nudge(0, 1)},
			{label: 'v', cb: function() nudge(0, -1)},
			{label: 'PLAY', cb: playCurrent}
		]);
		shell.showActionBar(true);
	}

	function toggleSilhouettes():Void {
		silhouettes.visible = !silhouettes.visible;
		silhouetteBtn.label = 'SILHOU: ${silhouettes.visible ? "ON" : "OFF"}';
	}

	function openCharacterPage():Void {
		shell.openPage('CHARACTER', function(pane:UIScrollPane):Float {
			var w:Float = shell.pageWidth();
			var y:Float = 6;

			var list:Array<String> = characterList();
			if (list.indexOf(charName) < 0)
				list.unshift(charName);
			var drop:UIDropdown = new UIDropdown('Character:', w, function(_:Int, value:String):Void {
				if (value != null && value.length > 0)
					loadCharacter(value);
			});
			drop.controlWidth = 240;
			drop.setItems(list);
			drop.select(Std.int(Math.max(0, list.indexOf(charName))));
			drop.y = y;
			pane.content.addChild(drop);
			y += 48;

			var nameIn:UITextInput = new UITextInput('Name:', w, charName, null);
			nameIn.y = y;
			pane.content.addChild(nameIn);
			y += 52;

			var halfW:Float = (w - 10) / 2;
			var loadBtn:UIButton = new UIButton('Load', halfW, 40, function() loadCharacter(nameIn.text.trim()), true);
			loadBtn.y = y;
			pane.content.addChild(loadBtn);
			var reloadBtn:UIButton = new UIButton('Reload Char', halfW, 40, function() {
				addCharacter(true);
				updatePointerPos();
			});
			reloadBtn.x = halfW + 10;
			reloadBtn.y = y;
			pane.content.addChild(reloadBtn);
			y += 48;

			var template:UIButton = new UIButton('Load Template', w, 40, loadTemplate);
			template.danger = true;
			template.y = y;
			pane.content.addChild(template);
			y += 48;

			var img:UITextInput = new UITextInput('Image file name:', w, character.imageFile, function(v:String) {
				character.imageFile = v;
				markDirty();
			});
			img.controlWidth = 220;
			img.y = y;
			pane.content.addChild(img);
			y += 52;

			var reImg:UIButton = new UIButton('Reload Image', w, 40, function() {
				var lastAnim:String = character.getAnimationName();
				character.imageFile = img.text;
				reloadCharacterImage();
				if (!character.isAnimationNull())
					character.playAnim(lastAnim, true);
			});
			reImg.y = y;
			pane.content.addChild(reImg);
			y += 48;

			var sc:UIStepper = new UIStepper('Scale:', w, character.jsonScale, 0.1, function(v:Float) {
				character.jsonScale = v;
				markDirty();
				character.scale.set(v, v);
				character.updateHitbox();
				reapplyCurrentOffset();
				updatePointerPos(false);
			});
			sc.min = 0.05;
			sc.max = 30;
			sc.decimals = 2;
			sc.y = y;
			pane.content.addChild(sc);
			y += 56;

			var player:UICheckbox = new UICheckbox('Playable Character', w, character.isPlayer, function(v:Bool) {
				character.isPlayer = v;
				markDirty();
				character.flipX = (character.originalFlipX != character.isPlayer);
				reapplyCurrentOffset();
				updateCharacterPositions();
				updatePointerPos(false);
			});
			player.y = y;
			pane.content.addChild(player);
			y += 44;

			var flip:UICheckbox = new UICheckbox('Flip X', w, character.originalFlipX, function(v:Bool) {
				character.originalFlipX = v;
				markDirty();
				character.flipX = (character.originalFlipX != character.isPlayer);
				reapplyCurrentOffset();
			});
			flip.y = y;
			pane.content.addChild(flip);
			y += 44;

			var aa:UICheckbox = new UICheckbox('No antialiasing', w, character.noAntialiasing, function(v:Bool) {
				character.noAntialiasing = v;
				markDirty();
				character.antialiasing = !v && ClientPrefs.data.antialiasing;
			});
			aa.y = y;
			pane.content.addChild(aa);
			y += 44;

			var swf:UICheckbox = new UICheckbox('SWF Mode (atlas)', w, character.swfMode, function(v:Bool) {
				character.swfMode = v;
				markDirty();
				if (character.isAnimateAtlas) {
					var lastAnim:String = character.getAnimationName();
					clearGhost();
					Paths.clearAnimateAtlasCache(character.imageFile);
					reloadCharacterImage();
					if (!character.isAnimationNull() && lastAnim != null && lastAnim != '')
						character.playAnim(lastAnim, true);
				}
			});
			swf.y = y;
			pane.content.addChild(swf);
			return y + 44;
		});
	}

	/**
		Refills the ANIMATIONS page's editable fields from the selected animation, so picking one from
		the list (or cycling with the rail button) loads its symbol / framerate / indices / loop instead
		of leaving whichever animation was current when the page was built.
	**/
	function syncAnimFields():Void {
		if (animNameIn == null || shell == null || !shell.drawerOpen || shell.pageTitle != 'ANIMATIONS')
			return;

		var a:AnimArray = (anims().length > 0) ? anims()[curAnim] : null;
		animNameIn.text = (a != null) ? a.anim : '';
		animSymbolIn.text = (a != null && a.name != null) ? a.name : '';
		animFpsStepper.value = (a != null) ? a.fps : 24;
		animIndicesIn.text = (a != null && a.indices != null) ? a.indices.join(',') : '';
		animLoopCheck.checked = (a != null && a.loop);
	}

	function openAnimPage():Void {
		shell.openPage('ANIMATIONS', function(pane:UIScrollPane):Float {
			var w:Float = shell.pageWidth();
			var y:Float = 6;

			var cur:AnimArray = (anims().length > 0) ? anims()[curAnim] : null;

			animNameIn = new UITextInput('Animation name:', w, cur != null ? cur.anim : '', null);
			animNameIn.controlWidth = 200;
			animNameIn.y = y;
			pane.content.addChild(animNameIn);
			y += 52;

			animSymbolIn = new UITextInput('Symbol/Prefix:', w, cur != null ? cur.name : '', null);
			animSymbolIn.controlWidth = 200;
			animSymbolIn.y = y;
			pane.content.addChild(animSymbolIn);
			y += 52;

			animFpsStepper = new UIStepper('Framerate:', w, cur != null ? cur.fps : 24, 1, null);
			animFpsStepper.min = 0;
			animFpsStepper.max = 240;
			animFpsStepper.decimals = 0;
			animFpsStepper.y = y;
			pane.content.addChild(animFpsStepper);
			y += 54;

			animIndicesIn = new UITextInput('Indices (0,1 or 0-5):', w, cur != null ? cur.indices.join(',') : '', null);
			animIndicesIn.controlWidth = 170;
			animIndicesIn.y = y;
			pane.content.addChild(animIndicesIn);
			y += 52;

			animLoopCheck = new UICheckbox('Looped', w, cur != null && cur.loop, null);
			animLoopCheck.y = y;
			pane.content.addChild(animLoopCheck);
			y += 46;

			var halfW:Float = (w - 10) / 2;
			var addBtn:UIButton = new UIButton('Add / Update', halfW, 40, function() {
				addOrUpdate(animNameIn.text.trim(), animSymbolIn.text.trim(), Std.int(animFpsStepper.value), animLoopCheck.checked,
					parseIndices(animIndicesIn.text));
				openAnimPage();
			}, true);
			addBtn.y = y;
			pane.content.addChild(addBtn);

			var remBtn:UIButton = new UIButton('Remove', halfW, 40, function() {
				removeAnim(animNameIn.text.trim());
				openAnimPage();
			});
			remBtn.danger = true;
			remBtn.x = halfW + 10;
			remBtn.y = y;
			pane.content.addChild(remBtn);
			y += 50;

			var hdr:UILabel = new UILabel('ANIMATIONS', 12, 2);
			hdr.y = y;
			pane.content.addChild(hdr);
			y += 24;
			// No accent on the rows: picking one does not rebuild the page, so the highlight stuck to
			// whichever row was current when it opened. The rail button and status strip name the
			// animation that is actually playing.
			for (i in 0...anims().length) {
				var idx:Int = i;
				var a:AnimArray = anims()[i];
				var row:UIButton = new UIButton('${a.anim}: ${a.offsets}', w, 40, function() {
					curAnim = idx;
					character.playAnim(a.anim, true);
					animBtn.label = 'ANIM: ${a.anim}';
					syncAnimFields();
					updateStatus();
				});
				row.fontSize = 13;
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

			var sing:UIStepper = new UIStepper('Sing Anim length:', w, character.singDuration, 0.1, function(v:Float) {
				character.singDuration = v;
				markDirty();
			});
			sing.min = 0;
			sing.max = 999;
			sing.decimals = 1;
			sing.y = y;
			pane.content.addChild(sing);
			y += 56;

			var icon:UITextInput = new UITextInput('Health icon:', w, character.healthIcon, function(v:String) {
				character.healthIcon = v;
				markDirty();
				if (healthIcon != null)
					healthIcon.changeIcon(v, false);
			});
			icon.controlWidth = 200;
			icon.y = y;
			pane.content.addChild(icon);
			y += 52;

			var iconColor:UIButton = new UIButton('Get Icon Color', w, 40, function() {
				var coolColor:FlxColor = FlxColor.fromInt(CoolUtil.dominantColor(healthIcon));
				markDirty();
				character.healthColorArray[0] = coolColor.red;
				character.healthColorArray[1] = coolColor.green;
				character.healthColorArray[2] = coolColor.blue;
				updateHealthBar();
				openSettingsPage();
			});
			iconColor.y = y;
			pane.content.addChild(iconColor);
			y += 48;

			var labels:Array<String> = ['Health R:', 'Health G:', 'Health B:'];
			for (i in 0...3) {
				var ch:Int = i;
				var st:UIStepper = new UIStepper(labels[i], w, character.healthColorArray[i], 1, function(v:Float) {
					character.healthColorArray[ch] = Std.int(v);
					markDirty();
					updateHealthBar();
				});
				st.min = 0;
				st.max = 255;
				st.decimals = 0;
				st.y = y;
				pane.content.addChild(st);
				y += 52;
			}

			var px:UIStepper = new UIStepper('Char X:', w, character.positionArray[0], 5, function(v:Float) {
				character.positionArray[0] = v;
				markDirty();
				updateCharacterPositions();
			});
			px.min = -9000;
			px.max = 9000;
			px.decimals = 0;
			px.y = y;
			pane.content.addChild(px);
			y += 52;

			var py:UIStepper = new UIStepper('Char Y:', w, character.positionArray[1], 5, function(v:Float) {
				character.positionArray[1] = v;
				markDirty();
				updateCharacterPositions();
			});
			py.min = -9000;
			py.max = 9000;
			py.decimals = 0;
			py.y = y;
			pane.content.addChild(py);
			y += 52;

			var cx:UIStepper = new UIStepper('Camera X:', w, character.cameraPosition[0], 5, function(v:Float) {
				character.cameraPosition[0] = v;
				markDirty();
				updatePointerPos();
			});
			cx.min = -9000;
			cx.max = 9000;
			cx.decimals = 0;
			cx.y = y;
			pane.content.addChild(cx);
			y += 52;

			var cy:UIStepper = new UIStepper('Camera Y:', w, character.cameraPosition[1], 5, function(v:Float) {
				character.cameraPosition[1] = v;
				markDirty();
				updatePointerPos();
			});
			cy.min = -9000;
			cy.max = 9000;
			cy.decimals = 0;
			cy.y = y;
			pane.content.addChild(cy);
			y += 52;

			var vocals:UITextInput = new UITextInput('Vocals postfix:', w, character.vocalsFile != null ? character.vocalsFile : '',
				function(v:String) {
				character.vocalsFile = v;
				markDirty();
			});
			vocals.controlWidth = 200;
			vocals.y = y;
			pane.content.addChild(vocals);
			y += 52;

			var loopHold:UICheckbox = new UICheckbox('Loop sing on hold', w, character.loopSingOnHold, function(v:Bool) {
				character.loopSingOnHold = v;
				markDirty();
			});
			loopHold.y = y;
			pane.content.addChild(loopHold);
			return y + 44;
		});
	}

	function openGhostPage():Void {
		shell.openPage('GHOST', function(pane:UIScrollPane):Float {
			var w:Float = shell.pageWidth();
			var y:Float = 6;

			var make:UIButton = new UIButton('Make Ghost', w, 44, function() {
				makeGhost();
			}, true);
			make.y = y;
			pane.content.addChild(make);
			y += 52;

			var highlight:UICheckbox = new UICheckbox('Highlight Ghost', w, false, function(checked:Bool) {
				var value:Int = checked ? 125 : 0;
				ghost.colorTransform.redOffset = value;
				ghost.colorTransform.greenOffset = value;
				ghost.colorTransform.blueOffset = value;
				if (animateGhost != null) {
					animateGhost.colorTransform.redOffset = value;
					animateGhost.colorTransform.greenOffset = value;
					animateGhost.colorTransform.blueOffset = value;
				}
			});
			highlight.y = y;
			pane.content.addChild(highlight);
			y += 46;

			var opacity:UISlider = new UISlider('Opacity:', w, 0, 1, ghostAlpha, function(v:Float) {
				ghostAlpha = v;
				ghost.alpha = ghostAlpha;
				if (animateGhost != null)
					animateGhost.alpha = ghostAlpha;
			});
			opacity.y = y;
			pane.content.addChild(opacity);
			y += 56;

			var clear:UIButton = new UIButton('Clear Ghost', w, 44, function() {
				clearGhost();
			});
			clear.danger = true;
			clear.y = y;
			pane.content.addChild(clear);
			return y + 52;
		});
	}

	/**
	 * Snapshots the current character pose into a frozen semi-transparent overlay, so a new offset can be
	 * lined up against the old one. Handles both Sparrow (copy the animation) and Animate atlas (rebuild a
	 * one-shot symbol timeline and mirror the character's bounds-compensated offset).
	 */
	function makeGhost():Void {
		if (character == null || character.isAnimationNull() || anims().length < 1)
			return;
		var myAnim:AnimArray = anims()[curAnim];

		if (!character.isAnimateAtlas) {
			// Whole collection: a multi-atlas character's frames span several graphics.
			ghost.frames = character.frames;
			ghost.animation.copyFrom(character.animation);
			ghost.animation.play(character.animation.curAnim.name, true, false, character.animation.curAnim.curFrame);
			ghost.animation.pause();
		} else if (myAnim != null) {
			if (animateGhost == null) {
				animateGhost = new FlxAnimate(ghost.x, ghost.y);
				animateGhost.cameras = [previewCam];
				insert(members.indexOf(ghost), animateGhost);
				animateGhost.active = false;
			}
			if (animateGhostImage != character.imageFile)
				Paths.loadAnimateAtlas(animateGhost, character.imageFile);

			if (myAnim.indices != null && myAnim.indices.length > 0)
				animateGhost.anim.addBySymbolIndices('anim', myAnim.name, myAnim.indices, 0, false);
			else
				animateGhost.anim.addBySymbol('anim', myAnim.name, 0, false);

			animateGhost.anim.play('anim', true, false, character.atlas.anim.curAnim != null ? character.atlas.anim.curAnim.curFrame : 0);
			animateGhost.anim.pause();
			animateGhostImage = character.imageFile;
		}

		var spr:FlxSprite = !character.isAnimateAtlas ? ghost : animateGhost;
		if (spr == null)
			return;

		spr.setPosition(character.x, character.y);
		spr.antialiasing = character.antialiasing;
		spr.flipX = character.flipX;
		spr.alpha = ghostAlpha;
		spr.scale.set(character.scale.x, character.scale.y);

		#if flixel_animate
		if (spr == animateGhost) {
			animateGhost.origin.set(character.origin.x, character.origin.y);
			var bx:Float = 0;
			var by:Float = 0;
			@:privateAccess
			if (animateGhost.timeline != null && animateGhost.timeline._bounds != null) {
				bx = animateGhost.timeline._bounds.x;
				by = animateGhost.timeline._bounds.y;
			}
			if (bx != 0 || by != 0)
				animateGhost.offset.set(character.offset.x - bx * character.scale.x, character.offset.y - by * character.scale.y);
			else
				animateGhost.offset.set(character.offset.x, character.offset.y);
		} else
		#end
		{
			spr.updateHitbox();
			spr.offset.set(character.offset.x, character.offset.y);
		}
		spr.visible = true;

		var otherSpr:FlxSprite = (spr == animateGhost) ? ghost : animateGhost;
		if (otherSpr != null)
			otherSpr.visible = false;
	}

	function clearGhost():Void {
		if (animateGhost != null) {
			remove(animateGhost);
			animateGhost = FlxDestroyUtil.destroy(animateGhost);
			animateGhostImage = null;
		}
		if (ghost != null)
			ghost.visible = false;
	}

	function parseIndices(s:String):Array<Int> {
		var out:Array<Int> = [];
		for (p in s.split(',')) {
			var t:String = p.trim();
			if (t.length < 1)
				continue;
			if (t.indexOf('-') > 0) {
				var parts:Array<String> = t.split('-');
				var startParsed:Null<Int> = Std.parseInt(parts[0]);
				var start:Int = (startParsed == null || startParsed < 0) ? 0 : startParsed;
				var endParsed:Null<Int> = Std.parseInt(parts[1]);
				var end:Int = (endParsed == null || endParsed < start) ? start : endParsed;
				for (index in start...end + 1)
					out.push(index);
			} else {
				var n:Null<Int> = Std.parseInt(t);
				if (n != null && n > -1)
					out.push(n);
			}
		}
		return out;
	}

	function addOrUpdate(name:String, symbol:String, fps:Int, loop:Bool, indices:Array<Int>):Void {
		if (name.length < 1)
			return;
		markDirty();

		var lastOffsets:Array<Int> = [0, 0];
		for (a in anims().copy())
			if (a.anim == name) {
				lastOffsets = a.offsets;
				if (character.hasAnimation(name)) {
					if (!character.isAnimateAtlas)
						character.animation.remove(name);
					else
						character.atlas.anim.remove(name);
				}
				anims().remove(a);
			}

		var na:AnimArray = {
			anim: name,
			name: symbol,
			fps: fps,
			loop: loop,
			indices: indices,
			offsets: lastOffsets
		};
		anims().push(na);

		addAnimation(name, symbol, fps, loop, indices);
		character.addOffset(name, lastOffsets[0], lastOffsets[1]);

		curAnim = Std.int(Math.max(0, anims().indexOf(na)));
		character.playAnim(name, true);
		if (animBtn != null)
			animBtn.label = 'ANIM: $name';
		updateStatus();
	}

	function removeAnim(name:String):Void {
		if (character == null)
			return;
		markDirty();
		for (a in anims().copy())
			if (a.anim == name) {
				var resetAnim:Bool = (a.anim == character.getAnimationName());
				if (character.hasAnimation(a.anim)) {
					if (!character.isAnimateAtlas)
						character.animation.remove(a.anim);
					else
						character.atlas.anim.remove(a.anim);
				}
				character.animOffsets.remove(a.anim);
				anims().remove(a);

				if (resetAnim && anims().length > 0) {
					curAnim = FlxMath.wrap(curAnim, 0, anims().length - 1);
					character.playAnim(anims()[curAnim].anim, true);
				}
				break;
			}
		if (curAnim >= anims().length)
			curAnim = anims().length - 1;
		if (animBtn != null)
			animBtn.label = 'ANIM: ${anims().length > 0 ? anims()[curAnim].anim : '-'}';
		updateStatus();
	}

	/** Re-derives the live offset of the current animation after a flip / scale / playable change. **/
	function reapplyCurrentOffset():Void {
		if (character == null)
			return;
		var name:String = character.getAnimationName();
		if (name != null && name.length > 0 && character.animOffsets.exists(name)) {
			var raw:Array<Float> = character.animOffsets.get(name);
			character.applyAnimOffset(raw[0], raw[1]);
		}
	}

	function loadTemplate():Void {
		final template:CharacterFile = {
			animations: [
				newAnim('idle', 'BF idle dance'),
				newAnim('singLEFT', 'BF NOTE LEFT0'),
				newAnim('singDOWN', 'BF NOTE DOWN0'),
				newAnim('singUP', 'BF NOTE UP0'),
				newAnim('singRIGHT', 'BF NOTE RIGHT0')
			],
			no_antialiasing: false,
			flip_x: false,
			healthicon: 'face',
			image: 'characters/BOYFRIEND',
			sing_duration: 4,
			scale: 1,
			healthbar_colors: [161, 161, 161],
			camera_position: [0, 0],
			position: [0, 0],
			vocals_file: null
		};

		markDirty();
		character.loadCharacterFile(template);
		character.missingCharacter = false;
		character.color = FlxColor.WHITE;
		character.alpha = 1;
		reloadAnimList();
		updateCharacterPositions();
		updatePointerPos();
		updateHealthBar();
		UIToast.show('Loaded BF template');
	}

	inline function newAnim(anim:String, name:String):AnimArray {
		return {
			offsets: [0, 0],
			loop: false,
			fps: 24,
			anim: anim,
			indices: [],
			name: name
		};
	}

	function loadCharacter(name:String):Void {
		if (name == null || name.length < 1)
			return;
		charName = name;
		unsavedProgress = false;
		addCharacter();
		updatePointerPos();
		if (healthIcon != null)
			healthIcon.changeIcon(character.healthIcon, false);
	}

	/** Scanned character jsons for the picker (empty when MODS_ALLOWED is off). Same source as the desktop editor. **/
	function characterList():Array<String> {
		#if MODS_ALLOWED
		var list:Array<String> = editors.ChartingState.listEditorFiles('characters/', ['.json']);
		list.sort(function(a:String, b:String):Int return (a < b) ? -1 : (a > b ? 1 : 0));
		return list;
		#else
		return [];
		#end
	}

	inline function updateHealthBar():Void {
		if (character == null || healthBar == null)
			return;
		healthBar.leftBar.color = healthBar.rightBar.color = FlxColor.fromRGB(character.healthColorArray[0], character.healthColorArray[1],
			character.healthColorArray[2]);
		if (healthIcon != null)
			healthIcon.changeIcon(character.healthIcon, false);
	}

	function updateStatus():Void {
		if (shell == null)
			return;
		var a:AnimArray = (anims().length > 0) ? anims()[curAnim] : null;
		var zoomTxt:String = '${Math.round(previewCam.zoom * 10) / 10}x';
		shell.setStatus('CHAR: $charName    anim: ${a != null ? a.anim : '-'}    offset: ${a != null ? a.offsets : []}    ZOOM $zoomTxt');
	}

	function saveCharacter(?onSaved:Void->Void):Void {
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
		saveFile('$charName.json', data, onSaved);
	}

	// The unsaved-changes exit prompt (MobileEditorBase) saves through this hook.
	override function saveDocument(?onSaved:Void->Void):Void {
		saveCharacter(onSaved);
	}

	function openCharacterFile():Void {
		openFile('$charName.json', 'Open a character json', function(data:String, path:String):Void {
			try {
				var cf:Dynamic = haxe.Json.parse(data);
				charName = baseName(path);
				unsavedProgress = false;
				character.imageFile = cf.image;
				character.jsonScale = (cf.scale != null) ? cf.scale : 1;
				character.singDuration = (cf.sing_duration != null) ? cf.sing_duration : 4;
				character.healthIcon = (cf.healthicon != null) ? cf.healthicon : 'face';
				character.positionArray = (cf.position != null) ? cf.position : [0, 0];
				character.cameraPosition = (cf.camera_position != null) ? cf.camera_position : [0, 0];
				character.originalFlipX = cf.flip_x == true;
				character.isPlayer = cf._editor_isPlayer == true;
				character.flipX = (character.originalFlipX != character.isPlayer);
				character.noAntialiasing = cf.no_antialiasing == true;
				character.swfMode = cf.swfMode == true;
				character.healthColorArray = (cf.healthbar_colors != null) ? cf.healthbar_colors : [255, 0, 0];
				character.vocalsFile = (cf.vocals_file != null) ? cf.vocals_file : '';
				character.loopSingOnHold = cf.loop_sing_on_hold == true;
				character.animationsArray = (cf.animations != null) ? cf.animations : [];
				character.animOffsets = new Map();
				curAnim = 0;
				reloadCharacterImage();
				character.scale.set(character.jsonScale, character.jsonScale);
				character.updateHitbox();
				updateCharacterPositions();
				updatePointerPos();
				updateHealthBar();
				if (anims().length > 0) {
					character.playAnim(anims()[0].anim, true);
					if (animBtn != null)
						animBtn.label = 'ANIM: ${anims()[0].anim}';
				}
				updateStatus();
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

	override function update(elapsed:Float):Void {
		gestures.update(elapsed);
		super.update(elapsed);
	}

	override function destroy():Void {
		clearGhost();
		if (gestures != null)
			gestures.enabled = false;
		if (hudCam != null)
			FlxG.cameras.remove(hudCam);
		super.destroy();
	}

	/**
		The character editor's stand-in stage backdrop, set up the way the engine's old `BGSprite`
		constructor did.
	**/
	inline function editorBackdrop(image:String, x:Float, y:Float, scrollX:Float, scrollY:Float):FlxSprite {
		var spr:FlxSprite = new FlxSprite(x, y).loadGraphic(Paths.image(image));
		spr.scrollFactor.set(scrollX, scrollY);
		spr.active = false;
		spr.antialiasing = ClientPrefs.data.antialiasing;
		return spr;
	}

}
