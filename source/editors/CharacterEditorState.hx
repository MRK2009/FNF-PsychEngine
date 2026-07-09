package editors;

import flixel.graphics.FlxGraphic;
import flixel.util.FlxDestroyUtil;
import openfl.net.FileReference;
import openfl.events.Event;
import openfl.events.IOErrorEvent;
import openfl.utils.Assets;
import openfl.display.Sprite;
import objects.Character;
import objects.HealthIcon;
import objects.Bar;
import editors.content.Prompt;
import editors.content.PsychJsonPrinter;
import smidr.UIRoot;
import smidr.flixel.FlxSmidr;
import smidr.UITheme;
import smidr.UIFonts;
import smidr.UILocale;
import smidr.input.UIFocus;
import smidr.widgets.UIButton;
import smidr.widgets.UICheckbox;
import smidr.widgets.UIDropdown;
import smidr.widgets.UILabel;
import smidr.widgets.UIModal;
import smidr.widgets.UIPanel;
import smidr.widgets.UIScrollPane;
import smidr.widgets.UISlider;
import smidr.widgets.UIStepper;
import smidr.widgets.UITabs;
import smidr.widgets.UITextInput;

class CharacterEditorState extends MusicBeatState {
	var character:Character;
	var ghost:FlxSprite;
	var animateGhost:FlxAnimate;
	var animateGhostImage:String;
	var cameraFollowPointer:FlxSprite;
	var isAnimateSprite:Bool = false;

	var silhouettes:FlxSpriteGroup;
	var dadPosition = FlxPoint.weak();
	var bfPosition = FlxPoint.weak();

	var helpModal:UIModal = null;
	var cameraZoomText:FlxText;
	var frameAdvanceText:FlxText;

	var healthBar:Bar;
	var healthIcon:HealthIcon;

	var copiedOffset:Array<Float> = [0, 0];
	var _char:String = null;
	var _goToPlayState:Bool = true;

	var anims = null;
	var animsTxt:FlxText;
	var curAnim = 0;

	private var camEditor:FlxCamera;
	private var camHUD:FlxCamera;

	var uiRoot:UIRoot;

	var unsavedProgress:Bool = false;

	var selectedFormat:FlxTextFormat = new FlxTextFormat(FlxColor.LIME);

	public function new(char:String = null, goToPlayState:Bool = true) {
		this._char = char;
		this._goToPlayState = goToPlayState;
		if (this._char == null)
			this._char = Character.DEFAULT_CHARACTER;

		super();
	}

	override function create() {
		Paths.clearStoredMemory();
		Paths.clearUnusedMemory();

		FlxG.sound.music.stop();
		camEditor = initPsychCamera();

		camHUD = new FlxCamera();
		camHUD.bgColor.alpha = 0;
		FlxG.cameras.add(camHUD, false);

		loadBG();

		silhouettes = new FlxSpriteGroup();
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
		add(ghost);

		animsTxt = new FlxText(10, 32, 400, '');
		animsTxt.setFormat(null, 16, FlxColor.WHITE, LEFT, OUTLINE_FAST, FlxColor.BLACK);
		animsTxt.scrollFactor.set();
		animsTxt.borderSize = 1;
		animsTxt.cameras = [camHUD];

		addCharacter();

		// Create a simple crosshair graphic
		cameraFollowPointer = new FlxSprite();
		cameraFollowPointer.makeGraphic(40, 40, FlxColor.TRANSPARENT, true);
		// Draw crosshair lines
		for (i in 0...40) {
			cameraFollowPointer.pixels.setPixel32(20, i, FlxColor.WHITE);
			cameraFollowPointer.pixels.setPixel32(i, 20, FlxColor.WHITE);
		}
		cameraFollowPointer.updateHitbox();
		healthBar = new Bar(30, FlxG.height - 75);
		healthBar.scrollFactor.set();
		healthBar.cameras = [camHUD];

		healthIcon = new HealthIcon(character.healthIcon, false, false);
		healthIcon.y = FlxG.height - 150;
		healthIcon.cameras = [camHUD];

		add(cameraFollowPointer);
		add(healthBar);
		add(healthIcon);
		add(animsTxt);

		var tipText:FlxText = new FlxText(FlxG.width - 300, FlxG.height - 24, 300, "Press F1 for Help", 20);
		tipText.cameras = [camHUD];
		tipText.setFormat(null, 16, FlxColor.WHITE, RIGHT, OUTLINE_FAST, FlxColor.BLACK);
		tipText.borderColor = FlxColor.BLACK;
		tipText.scrollFactor.set();
		tipText.borderSize = 1;
		tipText.active = false;
		add(tipText);

		cameraZoomText = new FlxText(0, 50, 200, 'Zoom: 1x');
		cameraZoomText.setFormat(null, 16, FlxColor.WHITE, CENTER, OUTLINE_FAST, FlxColor.BLACK);
		cameraZoomText.scrollFactor.set();
		cameraZoomText.borderSize = 1;
		cameraZoomText.screenCenter(X);
		cameraZoomText.cameras = [camHUD];
		add(cameraZoomText);

		frameAdvanceText = new FlxText(0, 75, 350, '');
		frameAdvanceText.setFormat(null, 16, FlxColor.WHITE, CENTER, OUTLINE_FAST, FlxColor.BLACK);
		frameAdvanceText.scrollFactor.set();
		frameAdvanceText.borderSize = 1;
		frameAdvanceText.screenCenter(X);
		frameAdvanceText.cameras = [camHUD];
		add(frameAdvanceText);

		FlxG.mouse.visible = true;
		FlxG.camera.zoom = 1;

		makeUIMenu();

		updatePointerPos();
		updateHealthBar();
		character.finishAnimation();

		if (ClientPrefs.data.cacheOnGPU)
			Paths.clearUnusedMemory();

		super.create();
	}

	/** Opens (or closes, when already open) the F1 keybind reference as a SmidrUI modal. **/
	function toggleHelpModal():Void {
		if (helpModal != null) {
			helpModal.close();
			return;
		}

		var modal:UIModal = editors.content.EditorHelp.open('Character Editor Help', [
			{
				title: 'CAMERA',
				lines: ['E/Q - Camera Zoom In/Out', 'J/K/L/I - Move Camera', 'R - Reset Camera Zoom']
			},
			{
				title: 'CHARACTER',
				lines: [
					'Ctrl + R - Reset Current Offset',
					'Ctrl + C - Copy Current Offset',
					'Ctrl + V - Paste Copied Offset on Current Animation',
					'Ctrl + Z - Undo Last Paste or Reset',
					'W/S - Previous/Next Animation',
					'Space - Replay Animation',
					'Arrow Keys/Mouse & Right Click - Move Offset',
					'A/D - Frame Advance (Back/Forward)'
				]
			},
			{
				title: 'OTHER',
				lines: [
					'F12 - Toggle Silhouettes',
					'Hold Shift - Move Offsets 10x faster and Camera 4x faster',
					'Hold Control - Move camera 4x slower'
				]
			}
		]);
		helpModal = modal;
		modal.onClosed = function() {
			if (helpModal == modal)
				helpModal = null;
		};
	}

	function addCharacter(reload:Bool = false) {
		var pos:Int = -1;
		if (character != null) {
			pos = members.indexOf(character);
			remove(character);
			character.destroy();
		}

		var isPlayer = (reload ? character.isPlayer : !predictCharacterIsNotPlayer(_char));
		character = new Character(0, 0, _char, isPlayer);
		if (!reload && character.editorIsPlayer != null && isPlayer != character.editorIsPlayer) {
			character.isPlayer = !character.isPlayer;
			character.flipX = (character.originalFlipX != character.isPlayer);
			if (check_player != null)
				check_player.checked = character.isPlayer;
		}
		character.debugMode = true;
		character.missingCharacter = false;

		if (pos > -1)
			insert(pos, character);
		else
			add(character);
		updateCharacterPositions();
		reloadAnimList();
		if (healthBar != null && healthIcon != null)
			updateHealthBar();
	}

	// ================================ UI (SmidrUI) ================================

	static inline var BOX1_W:Int = 260;
	static inline var BOX2_W:Int = 360;
	static inline var PAD:Int = 10;

	var settingsTabs:UITabs;
	var characterTabs:UITabs;
	var tabPanes1:Array<Sprite> = [];
	var tabPanes2:Array<UIScrollPane> = [];

	function makeUIMenu() {
		UILocale.translate = function(k:String, f:String):String return Language.getPhrase(k, f);
		UIFonts.register('assets/fonts/vcr.ttf');

		uiRoot = FlxSmidr.init();
		FlxSmidr.autoBlockMouse = true;

		// Top box: Ghost / Settings.
		var box1X:Float = FlxG.width - BOX1_W - 15;
		var box1Y:Float = 25;

		settingsTabs = new UITabs(BOX1_W, [{label: 'Ghost'}, {label: 'Settings'}], function(i:Int):Void {
			for (n in 0...tabPanes1.length)
				tabPanes1[n].visible = (n == i);
		});

		var pane1Y:Float = box1Y + settingsTabs.h + 8;
		var pane1H:Float = 100;
		var box1H:Float = settingsTabs.h + 8 + pane1H + PAD;

		var panel1:UIPanel = new UIPanel(BOX1_W, box1H, PANEL);
		panel1.x = box1X;
		panel1.y = box1Y;
		uiRoot.content.addChild(panel1);

		settingsTabs.x = box1X;
		settingsTabs.y = box1Y;
		uiRoot.content.addChild(settingsTabs);

		tabPanes1 = [];
		for (i in 0...2) {
			var pane:Sprite = new Sprite();
			pane.x = box1X + PAD;
			pane.y = pane1Y;
			pane.visible = false;
			uiRoot.content.addChild(pane);
			tabPanes1.push(pane);
		}

		// Bottom box: Animations / Character (scrollable tab contents).
		var box2X:Float = FlxG.width - BOX2_W - 15;
		var box2Y:Float = box1Y + box1H + 10;

		characterTabs = new UITabs(BOX2_W, [{label: 'Animations'}, {label: 'Character'}], function(i:Int):Void {
			for (n in 0...tabPanes2.length)
				tabPanes2[n].visible = (n == i);
		});

		var pane2Y:Float = box2Y + characterTabs.h + 8;
		var pane2H:Float = 330;
		var box2H:Float = characterTabs.h + 8 + pane2H + PAD;

		var panel2:UIPanel = new UIPanel(BOX2_W, box2H, PANEL);
		panel2.x = box2X;
		panel2.y = box2Y;
		uiRoot.content.addChild(panel2);

		characterTabs.x = box2X;
		characterTabs.y = box2Y;
		uiRoot.content.addChild(characterTabs);

		tabPanes2 = [];
		for (i in 0...2) {
			var pane:UIScrollPane = new UIScrollPane(BOX2_W - PAD * 2, pane2H);
			pane.x = box2X + PAD;
			pane.y = pane2Y;
			pane.visible = false;
			uiRoot.content.addChild(pane);
			tabPanes2.push(pane);
		}

		addGhostUI(tabPanes1[0]);
		addSettingsUI(tabPanes1[1]);
		addAnimationsUI(tabPanes2[0]);
		addCharacterUI(tabPanes2[1]);

		settingsTabs.select(1);
		tabPanes1[1].visible = true;
		characterTabs.select(1);
		tabPanes2[1].visible = true;
	}

	var ghostAlpha:Float = 0.6;

	function addGhostUI(pane:Sprite) {
		var rowW:Float = BOX1_W - PAD * 2;

		var makeGhostButton:UIButton = new UIButton("Make Ghost", 110, 26, function() {
			var anim = anims[curAnim];
			if (!character.isAnimationNull()) {
				var myAnim = anims[curAnim];
				if (!character.isAnimateAtlas) {
					ghost.loadGraphic(character.graphic);
					ghost.frames.frames = character.frames.frames;
					ghost.animation.copyFrom(character.animation);
					ghost.animation.play(character.animation.curAnim.name, true, false, character.animation.curAnim.curFrame);
					ghost.animation.pause();
				} else
					if (myAnim != null) // This is VERY unoptimized and bad, I hope to find a better replacement that loads only a specific frame as bitmap in the future.
				{
					if (animateGhost == null) // If I created the animateGhost on create() and you didn't load an atlas, it would crash the game on destroy, so we create it here
					{
						animateGhost = new FlxAnimate(ghost.x, ghost.y);
						insert(members.indexOf(ghost), animateGhost);
						animateGhost.active = false;
					}

					if (animateGhost == null || animateGhostImage != character.imageFile)
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
				if (spr != null) {
					spr.setPosition(character.x, character.y);
					spr.antialiasing = character.antialiasing;
					spr.flipX = character.flipX;
					spr.alpha = ghostAlpha;

					spr.scale.set(character.scale.x, character.scale.y);

					#if flixel_animate
					if (spr == animateGhost) {
						// Mirror exactly what Character.copyAtlasValues() does for
						// the live atlas: use the character's origin (NOT a centered
						// updateHitbox() origin) and the same bounds-compensated
						// offset, so the ghost overlays the character precisely.
						animateGhost.origin.set(character.origin.x, character.origin.y);

						var bx:Float = 0;
						var by:Float = 0;
						@:privateAccess
						if (animateGhost.timeline != null && animateGhost.timeline._bounds != null) {
							bx = animateGhost.timeline._bounds.x;
							by = animateGhost.timeline._bounds.y;
						}
						if (bx != 0 || by != 0)
							animateGhost.offset.set(character.offset.x - bx * character.scale.x,
							                        character.offset.y - by * character.scale.y);
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
				trace('created ghost image');
			}
		});
		pane.addChild(makeGhostButton);

		var highlightGhost:UICheckbox = new UICheckbox("Highlight Ghost", rowW, false, function(checked:Bool) {
			var value = checked ? 125 : 0;
			ghost.colorTransform.redOffset = value;
			ghost.colorTransform.greenOffset = value;
			ghost.colorTransform.blueOffset = value;
			if (animateGhost != null) {
				animateGhost.colorTransform.redOffset = value;
				animateGhost.colorTransform.greenOffset = value;
				animateGhost.colorTransform.blueOffset = value;
			}
		});
		highlightGhost.y = 34;
		pane.addChild(highlightGhost);

		var ghostAlphaSlider:UISlider = new UISlider('Opacity:', rowW, 0, 1, ghostAlpha, function(v:Float) {
			ghostAlpha = v;
			ghost.alpha = ghostAlpha;
			if (animateGhost != null)
				animateGhost.alpha = ghostAlpha;
		});
		ghostAlphaSlider.y = 68;
		pane.addChild(ghostAlphaSlider);
	}

	var check_player:UICheckbox;
	var charDropDown:UIDropdown;

	function addSettingsUI(pane:Sprite) {
		var rowW:Float = BOX1_W - PAD * 2;

		charDropDown = new UIDropdown('Character:', rowW, function(index:Int, intended:String) {
			if (intended == null || intended.length < 1 || intended == _char)
				return;

			var characterPath:String = 'characters/$intended.json';
			var path:String = Paths.getPath(characterPath, TEXT, null, true);
			#if MODS_ALLOWED
			if (FileSystem.exists(path))
			#else
			if (Assets.exists(path))
			#end
			{
				_char = intended;
				check_player.checked = character.isPlayer;
				addCharacter();
				reloadCharacterOptions();
				reloadCharacterDropDown();
				updatePointerPos();
			}
		else {
			reloadCharacterDropDown();
			FlxG.sound.play(Paths.sound('cancelMenu'));
		}
		});
		pane.addChild(charDropDown);
		reloadCharacterDropDown();

		check_player = new UICheckbox("Playable Character", rowW, character.isPlayer, function(checked:Bool) {
			character.isPlayer = !character.isPlayer;
			character.flipX = !character.flipX;
			reapplyCurrentOffset();
			updateCharacterPositions();
			updatePointerPos(false);
			unsavedProgress = true;
		});
		check_player.y = 32;
		pane.addChild(check_player);

		var reloadCharacter:UIButton = new UIButton("Reload Char", 115, 26, function() {
			addCharacter(true);
			updatePointerPos();
			reloadCharacterOptions();
			reloadCharacterDropDown();
		});
		reloadCharacter.y = 64;
		pane.addChild(reloadCharacter);

		var templateCharacter:UIButton = new UIButton("Load Template", 115, 26, function() {
			final _template:CharacterFile = {
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

			character.loadCharacterFile(_template);
			character.missingCharacter = false;
			character.color = FlxColor.WHITE;
			character.alpha = 1;
			reloadAnimList();
			reloadCharacterOptions();
			updateCharacterPositions();
			updatePointerPos();
			reloadCharacterDropDown();
			updateHealthBar();
		});
		templateCharacter.danger = true;
		templateCharacter.x = 125;
		templateCharacter.y = 64;
		pane.addChild(templateCharacter);
	}

	var animationDropDown:UIDropdown;
	var animationInputText:UITextInput;
	var animationNameInputText:UITextInput;
	var animationIndicesInputText:UITextInput;
	var animationFramerate:UIStepper;
	var animationLoopCheckBox:UICheckbox;

	function addAnimationsUI(pane:UIScrollPane) {
		var rowW:Float = pane.w - PAD - 12;

		animationDropDown = new UIDropdown('Animations:', rowW, function(selectedAnimation:Int, pressed:String) {
			var anim:AnimArray = character.animationsArray[selectedAnimation];
			if (anim == null)
				return;
			animationInputText.text = anim.anim;
			animationNameInputText.text = anim.name;
			animationLoopCheckBox.checked = anim.loop;
			animationFramerate.value = anim.fps;

			var indicesStr:String = anim.indices.toString();
			animationIndicesInputText.text = indicesStr.substr(1, indicesStr.length - 2);
		});
		pane.content.addChild(animationDropDown);

		animationInputText = new UITextInput('Animation name:', rowW, '');
		animationInputText.y = 32;
		animationInputText.boxWidth = 190;
		pane.content.addChild(animationInputText);

		animationNameInputText = new UITextInput('Symbol Name/Tag:', rowW, '');
		animationNameInputText.y = 64;
		animationNameInputText.boxWidth = 180;
		pane.content.addChild(animationNameInputText);

		animationFramerate = new UIStepper('Framerate:', rowW, 24, 1);
		animationFramerate.min = 0;
		animationFramerate.max = 240;
		animationFramerate.y = 96;
		pane.content.addChild(animationFramerate);

		animationLoopCheckBox = new UICheckbox("Should it Loop?", rowW);
		animationLoopCheckBox.y = 128;
		pane.content.addChild(animationLoopCheckBox);

		animationIndicesInputText = new UITextInput('ADVANCED - Indices:', rowW, '');
		animationIndicesInputText.y = 160;
		animationIndicesInputText.boxWidth = 160;
		pane.content.addChild(animationIndicesInputText);

		var addUpdateButton:UIButton = new UIButton("Add/Update", 150, 28, function() {
			var indicesText:String = animationIndicesInputText.text.trim();
			var indices:Array<Int> = [];
			if (indicesText.length > 0) {
				var indicesStr:Array<String> = animationIndicesInputText.text.trim().split(',');
				if (indicesStr.length > 0) {
					for (ind in indicesStr) {
						if (ind.contains('-')) {
							var splitIndices:Array<String> = ind.split('-');
							var startParsed:Null<Int> = Std.parseInt(splitIndices[0]);
							var indexStart:Int = (startParsed == null || startParsed < 0) ? 0 : startParsed;

							var endParsed:Null<Int> = Std.parseInt(splitIndices[1]);
							var indexEnd:Int = (endParsed == null || endParsed < indexStart) ? indexStart : endParsed;

							for (index in indexStart...indexEnd + 1)
								indices.push(index);
						} else {
							var index:Null<Int> = Std.parseInt(ind);
							if (index != null && index > -1)
								indices.push(index);
						}
					}
				}
			}

			var lastAnim:String = (character.animationsArray[curAnim] != null) ? character.animationsArray[curAnim].anim : '';
			var lastOffsets:Array<Int> = [0, 0];
			for (anim in character.animationsArray)
				if (animationInputText.text == anim.anim) {
					lastOffsets = anim.offsets;
					if (character.hasAnimation(animationInputText.text)) {
						if (!character.isAnimateAtlas)
							character.animation.remove(animationInputText.text);
						else
							character.atlas.anim.remove(animationInputText.text);
					}
					character.animationsArray.remove(anim);
				}

			var addedAnim:AnimArray = newAnim(animationInputText.text, animationNameInputText.text);
			addedAnim.fps = Math.round(animationFramerate.value);
			addedAnim.loop = animationLoopCheckBox.checked;
			addedAnim.indices = indices;
			addedAnim.offsets = lastOffsets;
			addAnimation(addedAnim.anim, addedAnim.name, addedAnim.fps, addedAnim.loop, addedAnim.indices);
			character.animationsArray.push(addedAnim);

			reloadAnimList();
			@:arrayAccess curAnim = Std.int(Math.max(0, character.animationsArray.indexOf(addedAnim)));
			character.playAnim(addedAnim.anim, true);
			unsavedProgress = true;
			trace('Added/Updated animation: ' + animationInputText.text);
		}, true);
		addUpdateButton.y = 196;
		pane.content.addChild(addUpdateButton);

		var removeButton:UIButton = new UIButton("Remove", 120, 28, function() {
			for (anim in character.animationsArray)
				if (animationInputText.text == anim.anim) {
					var resetAnim:Bool = false;
					if (anim.anim == character.getAnimationName())
						resetAnim = true;
					if (character.hasAnimation(anim.anim)) {
						if (!character.isAnimateAtlas)
							character.animation.remove(anim.anim);
						else
							character.atlas.anim.remove(anim.anim);
						character.animOffsets.remove(anim.anim);
						character.animationsArray.remove(anim);
					}

					if (resetAnim && character.animationsArray.length > 0) {
						curAnim = FlxMath.wrap(curAnim, 0, anims.length - 1);
						character.playAnim(anims[curAnim].anim, true);
					}
					reloadAnimList();
					unsavedProgress = true;
					trace('Removed animation: ' + animationInputText.text);
					break;
				}
		});
		removeButton.danger = true;
		removeButton.x = 160;
		removeButton.y = 196;
		pane.content.addChild(removeButton);

		pane.refreshContent(236);

		reloadAnimList();
		animationDropDown.select(0);
	}

	var imageInputText:UITextInput;
	var healthIconInputText:UITextInput;
	var vocalsInputText:UITextInput;

	var singDurationStepper:UIStepper;
	var scaleStepper:UIStepper;
	var positionXStepper:UIStepper;
	var positionYStepper:UIStepper;
	var positionCameraXStepper:UIStepper;
	var positionCameraYStepper:UIStepper;

	var flipXCheckBox:UICheckbox;
	var noAntialiasingCheckBox:UICheckbox;
	var swfModeCheckBox:UICheckbox;
	var loopSingCheckBox:UICheckbox;

	var healthColorStepperR:UIStepper;
	var healthColorStepperG:UIStepper;
	var healthColorStepperB:UIStepper;

	function addCharacterUI(pane:UIScrollPane) {
		var rowW:Float = pane.w - PAD - 12;
		var halfW:Float = (rowW - 10) / 2;

		imageInputText = new UITextInput('Image file name:', rowW, character.imageFile, function(v:String) {
			character.imageFile = v;
			unsavedProgress = true;
		});
		pane.content.addChild(imageInputText);

		var reloadImage:UIButton = new UIButton("Reload Image", halfW, 26, function() {
			var lastAnim = character.getAnimationName();
			character.imageFile = imageInputText.text;
			reloadCharacterImage();
			if (!character.isAnimationNull()) {
				character.playAnim(lastAnim, true);
			}
		});
		reloadImage.y = 32;
		pane.content.addChild(reloadImage);

		var decideIconColor:UIButton = new UIButton("Get Icon Color", halfW, 26, function() {
			var coolColor:FlxColor = FlxColor.fromInt(CoolUtil.dominantColor(healthIcon));
			character.healthColorArray[0] = coolColor.red;
			character.healthColorArray[1] = coolColor.green;
			character.healthColorArray[2] = coolColor.blue;
			updateHealthBar();
			unsavedProgress = true;
		});
		decideIconColor.x = halfW + 10;
		decideIconColor.y = 32;
		pane.content.addChild(decideIconColor);

		healthIconInputText = new UITextInput('Health icon name:', rowW, healthIcon.getCharacter(), function(v:String) {
			var lastIcon = healthIcon.getCharacter();
			healthIcon.changeIcon(v, false);
			character.healthIcon = v;
			if (lastIcon != healthIcon.getCharacter())
				updatePresence();
			unsavedProgress = true;
		});
		healthIconInputText.y = 66;
		healthIconInputText.boxWidth = 180;
		pane.content.addChild(healthIconInputText);

		vocalsInputText = new UITextInput('Vocals File Postfix:', rowW, character.vocalsFile != null ? character.vocalsFile : '', function(v:String) {
			character.vocalsFile = v;
			unsavedProgress = true;
		});
		vocalsInputText.y = 98;
		vocalsInputText.boxWidth = 160;
		pane.content.addChild(vocalsInputText);

		singDurationStepper = new UIStepper('Sing Anim length:', rowW, character.singDuration, 0.1, function(v:Float) {
			character.singDuration = v;
			unsavedProgress = true;
		});
		singDurationStepper.min = 0;
		singDurationStepper.max = 999;
		singDurationStepper.decimals = 1;
		singDurationStepper.y = 130;
		pane.content.addChild(singDurationStepper);

		scaleStepper = new UIStepper('Scale:', rowW, character.jsonScale, 0.1, function(v:Float) {
			reloadCharacterImage();
			character.jsonScale = v;
			character.scale.set(character.jsonScale, character.jsonScale);
			character.updateHitbox();
			reapplyCurrentOffset(); // width changed -> refresh flipped offset
			updatePointerPos(false);
			unsavedProgress = true;
		});
		scaleStepper.min = 0.05;
		scaleStepper.max = 10;
		scaleStepper.decimals = 2;
		scaleStepper.y = 162;
		pane.content.addChild(scaleStepper);

		flipXCheckBox = new UICheckbox("Flip X", halfW, character.originalFlipX, function(checked:Bool) {
			character.originalFlipX = !character.originalFlipX;
			character.flipX = (character.originalFlipX != character.isPlayer);
			reapplyCurrentOffset();
			unsavedProgress = true;
		});
		flipXCheckBox.y = 194;
		pane.content.addChild(flipXCheckBox);

		noAntialiasingCheckBox = new UICheckbox("No Antialiasing", halfW, character.noAntialiasing, function(checked:Bool) {
			character.antialiasing = false;
			if (!checked && ClientPrefs.data.antialiasing) {
				character.antialiasing = true;
			}
			character.noAntialiasing = checked;
			unsavedProgress = true;
		});
		noAntialiasingCheckBox.x = halfW + 10;
		noAntialiasingCheckBox.y = 194;
		pane.content.addChild(noAntialiasingCheckBox);

		// Loop Sing on Hold: re-fire the sing anim each step while a sustain is held (classic "jitter");
		// off freezes the sing pose through the hold. Shares its row with the SWF Mode toggle.
		loopSingCheckBox = new UICheckbox("Loop Sing on Hold", halfW, character.loopSingOnHold, function(checked:Bool) {
			character.loopSingOnHold = checked;
			unsavedProgress = true;
		});
		loopSingCheckBox.y = 226;
		pane.content.addChild(loopSingCheckBox);

		// SWF Mode: only meaningful for Animate atlas characters; reload the atlas
		// so the change (movieclip timelines baked vs. static) takes effect live.
		swfModeCheckBox = new UICheckbox("SWF Mode", halfW, character.swfMode, function(checked:Bool) {
			character.swfMode = checked;
			if (character.isAnimateAtlas) {
				var lastAnim:String = character.getAnimationName();
				// swfMode is baked at parse time, so the cached atlas must be
				// evicted to take effect. Reset the ghost first -- it shares the
				// cached frames, and drawing a dangling reference after the evict
				// would throw "sprite was destroyed".
				if (animateGhost != null) {
					remove(animateGhost);
					animateGhost = FlxDestroyUtil.destroy(animateGhost);
					animateGhostImage = null;
				}
				ghost.visible = false;
				Paths.clearAnimateAtlasCache(character.imageFile);
				reloadCharacterImage();
				if (!character.isAnimationNull() && lastAnim != null && lastAnim != '')
					character.playAnim(lastAnim, true);
			}
			unsavedProgress = true;
		});
		swfModeCheckBox.x = halfW + 10;
		swfModeCheckBox.y = 226;
		pane.content.addChild(swfModeCheckBox);

		positionXStepper = new UIStepper('Char X:', halfW, character.positionArray[0], 10, function(v:Float) {
			character.positionArray[0] = v;
			updateCharacterPositions();
			unsavedProgress = true;
		});
		positionXStepper.min = -9000;
		positionXStepper.max = 9000;
		positionXStepper.y = 258;
		pane.content.addChild(positionXStepper);

		positionYStepper = new UIStepper('Y:', halfW, character.positionArray[1], 10, function(v:Float) {
			character.positionArray[1] = v;
			updateCharacterPositions();
			unsavedProgress = true;
		});
		positionYStepper.min = -9000;
		positionYStepper.max = 9000;
		positionYStepper.x = halfW + 10;
		positionYStepper.y = 258;
		pane.content.addChild(positionYStepper);

		positionCameraXStepper = new UIStepper('Camera X:', halfW, character.cameraPosition[0], 10, function(v:Float) {
			character.cameraPosition[0] = v;
			updatePointerPos();
			unsavedProgress = true;
		});
		positionCameraXStepper.min = -9000;
		positionCameraXStepper.max = 9000;
		positionCameraXStepper.y = 290;
		pane.content.addChild(positionCameraXStepper);

		positionCameraYStepper = new UIStepper('Y:', halfW, character.cameraPosition[1], 10, function(v:Float) {
			character.cameraPosition[1] = v;
			updatePointerPos();
			unsavedProgress = true;
		});
		positionCameraYStepper.min = -9000;
		positionCameraYStepper.max = 9000;
		positionCameraYStepper.x = halfW + 10;
		positionCameraYStepper.y = 290;
		pane.content.addChild(positionCameraYStepper);

		var thirdW:Float = (rowW - 20) / 3;
		healthColorStepperR = new UIStepper('R:', thirdW, character.healthColorArray[0], 20, function(v:Float) {
			character.healthColorArray[0] = Math.round(v);
			updateHealthBar();
			unsavedProgress = true;
		});
		healthColorStepperR.min = 0;
		healthColorStepperR.max = 255;
		healthColorStepperR.boxWidth = 52;
		healthColorStepperR.y = 322;
		pane.content.addChild(healthColorStepperR);

		healthColorStepperG = new UIStepper('G:', thirdW, character.healthColorArray[1], 20, function(v:Float) {
			character.healthColorArray[1] = Math.round(v);
			updateHealthBar();
			unsavedProgress = true;
		});
		healthColorStepperG.min = 0;
		healthColorStepperG.max = 255;
		healthColorStepperG.boxWidth = 52;
		healthColorStepperG.x = thirdW + 10;
		healthColorStepperG.y = 322;
		pane.content.addChild(healthColorStepperG);

		healthColorStepperB = new UIStepper('B:', thirdW, character.healthColorArray[2], 20, function(v:Float) {
			character.healthColorArray[2] = Math.round(v);
			updateHealthBar();
			unsavedProgress = true;
		});
		healthColorStepperB.min = 0;
		healthColorStepperB.max = 255;
		healthColorStepperB.boxWidth = 52;
		healthColorStepperB.x = (thirdW + 10) * 2;
		healthColorStepperB.y = 322;
		pane.content.addChild(healthColorStepperB);

		var saveCharacterButton:UIButton = new UIButton("Save Character", rowW, 32, function() {
			saveCharacter();
		}, true);
		saveCharacterButton.y = 358;
		pane.content.addChild(saveCharacterButton);

		pane.refreshContent(402);
	}

	function reloadCharacterImage() {
		var lastAnim:String = character.getAnimationName();
		var anims:Array<AnimArray> = character.animationsArray.copy();

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

		for (anim in anims) {
			var animAnim:String = '' + anim.anim;
			var animName:String = '' + anim.name;
			var animFps:Int = anim.fps;
			var animLoop:Bool = !!anim.loop; // Bruh
			var animIndices:Array<Int> = anim.indices;
			addAnimation(animAnim, animName, animFps, animLoop, animIndices);
		}

		if (anims.length > 0) {
			if (lastAnim != '')
				character.playAnim(lastAnim, true);
			else
				character.dance();
		}
	}

	function reloadCharacterOptions() {
		if (imageInputText == null)
			return;

		check_player.checked = character.isPlayer;
		imageInputText.text = character.imageFile;
		healthIconInputText.text = character.healthIcon;
		vocalsInputText.text = character.vocalsFile != null ? character.vocalsFile : '';
		singDurationStepper.value = character.singDuration;
		scaleStepper.value = character.jsonScale;
		flipXCheckBox.checked = character.originalFlipX;
		noAntialiasingCheckBox.checked = character.noAntialiasing;
		if (swfModeCheckBox != null)
			swfModeCheckBox.checked = character.swfMode;
		positionXStepper.value = character.positionArray[0];
		positionYStepper.value = character.positionArray[1];
		positionCameraXStepper.value = character.cameraPosition[0];
		positionCameraYStepper.value = character.cameraPosition[1];
		reloadAnimationDropDown();
		updateHealthBar();
	}

	var holdingArrowsTime:Float = 0;
	var holdingArrowsElapsed:Float = 0;
	var holdingFrameTime:Float = 0;
	var holdingFrameElapsed:Float = 0;
	var undoOffsets:Array<Float> = null;

	override function update(elapsed:Float) {
		super.update(elapsed);

		if (UIFocus.focused != null) {
			ClientPrefs.toggleVolumeKeys(false);
			return;
		}
		ClientPrefs.toggleVolumeKeys(true);

		// F1 toggles the help modal even while it is open (the modal also closes on Escape).
		if (FlxG.keys.justPressed.F1)
			toggleHelpModal();

		if (UIRoot.overlayOpen)
			return;

		var shiftMult:Float = 1;
		var ctrlMult:Float = 1;
		var shiftMultBig:Float = 1;
		if (FlxG.keys.pressed.SHIFT) {
			shiftMult = 4;
			shiftMultBig = 10;
		}
		if (FlxG.keys.pressed.CONTROL)
			ctrlMult = 0.25;

		// CAMERA CONTROLS
		if (FlxG.keys.pressed.J)
			FlxG.camera.scroll.x -= elapsed * 500 * shiftMult * ctrlMult;
		if (FlxG.keys.pressed.K)
			FlxG.camera.scroll.y += elapsed * 500 * shiftMult * ctrlMult;
		if (FlxG.keys.pressed.L)
			FlxG.camera.scroll.x += elapsed * 500 * shiftMult * ctrlMult;
		if (FlxG.keys.pressed.I)
			FlxG.camera.scroll.y -= elapsed * 500 * shiftMult * ctrlMult;

		var lastZoom = FlxG.camera.zoom;
		if (FlxG.keys.justPressed.R && !FlxG.keys.pressed.CONTROL)
			FlxG.camera.zoom = 1;
		else if (FlxG.keys.pressed.E && FlxG.camera.zoom < 3) {
			FlxG.camera.zoom += elapsed * FlxG.camera.zoom * shiftMult * ctrlMult;
			if (FlxG.camera.zoom > 3)
				FlxG.camera.zoom = 3;
		} else if (FlxG.keys.pressed.Q && FlxG.camera.zoom > 0.1) {
			FlxG.camera.zoom -= elapsed * FlxG.camera.zoom * shiftMult * ctrlMult;
			if (FlxG.camera.zoom < 0.1)
				FlxG.camera.zoom = 0.1;
		}

		if (lastZoom != FlxG.camera.zoom)
			cameraZoomText.text = 'Zoom: ' + FlxMath.roundDecimal(FlxG.camera.zoom, 2) + 'x';

		// CHARACTER CONTROLS
		var changedAnim:Bool = false;
		if (anims.length > 1) {
			if (FlxG.keys.justPressed.W && (changedAnim = true))
				curAnim--;
			else if (FlxG.keys.justPressed.S && (changedAnim = true))
				curAnim++;

			if (changedAnim) {
				undoOffsets = null;
				curAnim = FlxMath.wrap(curAnim, 0, anims.length - 1);
				character.playAnim(anims[curAnim].anim, true);
				updateText();
			}
		}

		var changedOffset = false;
		var moveKeysP = [
			FlxG.keys.justPressed.LEFT,
			FlxG.keys.justPressed.RIGHT,
			FlxG.keys.justPressed.UP,
			FlxG.keys.justPressed.DOWN
		];
		var moveKeys = [
			FlxG.keys.pressed.LEFT,
			FlxG.keys.pressed.RIGHT,
			FlxG.keys.pressed.UP,
			FlxG.keys.pressed.DOWN
		];
		if (moveKeysP.contains(true)) {
			character.offset.x += ((moveKeysP[0] ? 1 : 0) - (moveKeysP[1] ? 1 : 0)) * shiftMultBig;
			character.offset.y += ((moveKeysP[2] ? 1 : 0) - (moveKeysP[3] ? 1 : 0)) * shiftMultBig;
			changedOffset = true;
		}

		if (moveKeys.contains(true)) {
			holdingArrowsTime += elapsed;
			if (holdingArrowsTime > 0.6) {
				holdingArrowsElapsed += elapsed;
				while (holdingArrowsElapsed > (1 / 60)) {
					character.offset.x += ((moveKeys[0] ? 1 : 0) - (moveKeys[1] ? 1 : 0)) * shiftMultBig;
					character.offset.y += ((moveKeys[2] ? 1 : 0) - (moveKeys[3] ? 1 : 0)) * shiftMultBig;
					holdingArrowsElapsed -= (1 / 60);
					changedOffset = true;
				}
			}
		} else
			holdingArrowsTime = 0;

		if (!FlxSmidr.mouseBlocked && FlxG.mouse.pressedRight && (FlxG.mouse.deltaScreenX != 0 || FlxG.mouse.deltaScreenY != 0)) {
			character.offset.x -= FlxG.mouse.deltaScreenX;
			character.offset.y -= FlxG.mouse.deltaScreenY;
			changedOffset = true;
		}

		if (FlxG.keys.pressed.CONTROL) {
			if (FlxG.keys.justPressed.C) {
				copiedOffset[0] = character.offset.x;
				copiedOffset[1] = character.offset.y;
				changedOffset = true;
			} else if (FlxG.keys.justPressed.V) {
				undoOffsets = [character.offset.x, character.offset.y];
				character.offset.x = copiedOffset[0];
				character.offset.y = copiedOffset[1];
				changedOffset = true;
			} else if (FlxG.keys.justPressed.R) {
				undoOffsets = [character.offset.x, character.offset.y];
				character.offset.set(0, 0);
				changedOffset = true;
			} else if (FlxG.keys.justPressed.Z && undoOffsets != null) {
				character.offset.x = undoOffsets[0];
				character.offset.y = undoOffsets[1];
				changedOffset = true;
			}
		}

		var anim = anims[curAnim];
		if (changedOffset && anim != null && anim.offsets != null) {
			// `character.offset` is the live (possibly flipped/scaled) value; store
			// the authored equivalent so the JSON keeps flipX==false / base-scale
			// offsets that applyAnimOffset re-derives in-game and in this editor.
			var authored = character.getAuthoredOffset();
			anim.offsets[0] = Std.int(authored[0]);
			anim.offsets[1] = Std.int(authored[1]);

			character.addOffset(anim.anim, authored[0], authored[1]);
			updateText();
		}

		var txt = 'ERROR: No Animation Found';
		var clr = FlxColor.RED;
		if (!character.isAnimationNull()) {
			if (FlxG.keys.pressed.A || FlxG.keys.pressed.D) {
				holdingFrameTime += elapsed;
				if (holdingFrameTime > 0.5)
					holdingFrameElapsed += elapsed;
			} else
				holdingFrameTime = 0;

			if (FlxG.keys.justPressed.SPACE)
				character.playAnim(character.getAnimationName(), true);

			var frames:Int = -1;
			var length:Int = -1;
			if (!character.isAnimateAtlas && character.animation.curAnim != null) {
				frames = character.animation.curAnim.curFrame;
				length = character.animation.curAnim.numFrames;
			} else if (character.isAnimateAtlas && character.atlas.anim != null) {
				final curAnim = character.atlas.anim.curAnim;
				if (curAnim != null) {
					frames = curAnim.curFrame;
					length = curAnim.numFrames;
				}
			}

			if (length >= 0) {
				if (FlxG.keys.justPressed.A || FlxG.keys.justPressed.D || holdingFrameTime > 0.5) {
					var isLeft = false;
					if ((holdingFrameTime > 0.5 && FlxG.keys.pressed.A) || FlxG.keys.justPressed.A)
						isLeft = true;
					character.animPaused = true;

					if (holdingFrameTime <= 0.5 || holdingFrameElapsed > 0.1) {
						frames = FlxMath.wrap(frames + Std.int(isLeft ? -shiftMult : shiftMult), 0, length - 1);
						if (!character.isAnimateAtlas)
							character.animation.curAnim.curFrame = frames;
						else if (character.atlas.anim.curAnim != null)
							character.atlas.anim.curAnim.curFrame = frames;
						holdingFrameElapsed -= 0.1;
					}
				}

				txt = 'Frames: ( $frames / ${length - 1} )';
				// if(character.animation.curAnim.paused) txt += ' - PAUSED';
				clr = FlxColor.WHITE;
			}
		}
		if (txt != frameAdvanceText.text)
			frameAdvanceText.text = txt;
		frameAdvanceText.color = clr;

		// OTHER CONTROLS
		if (FlxG.keys.justPressed.F12)
			silhouettes.visible = !silhouettes.visible;

		if (FlxG.keys.justPressed.ESCAPE || controls.BACK) {
			if (!_goToPlayState) {
				if (!unsavedProgress) {
					MusicBeatState.switchState(new editors.MasterEditorMenu());
					FlxG.sound.playMusic(Paths.music('freakyMenu'));
				} else
					openSubState(new ExitConfirmationPrompt());
			} else {
				FlxG.mouse.visible = false;
				MusicBeatState.switchState(new PlayState());
			}
			return;
		}
	}

	final assetFolder = 'week1'; // load from assets/week1/

	inline function loadBG() {
		var lastLoaded = Paths.currentLevel;
		Paths.currentLevel = assetFolder;

		/////////////
		// bg data //
		/////////////
		#if !BASE_GAME_FILES
		camEditor.bgColor = 0xFF666666;
		#else
		var bg:BGSprite = new BGSprite('stageback', -600, -200, 0.9, 0.9);
		add(bg);

		var stageFront:BGSprite = new BGSprite('stagefront', -650, 600, 0.9, 0.9);
		stageFront.setGraphicSize(Std.int(stageFront.width * 1.1));
		stageFront.updateHitbox();
		add(stageFront);
		#end

		dadPosition.set(100, 100);
		bfPosition.set(770, 100);
		/////////////

		Paths.currentLevel = lastLoaded;
	}

	inline function updatePointerPos(?snap:Bool = true) {
		if (character == null || cameraFollowPointer == null)
			return;

		var offX:Float = 0;
		var offY:Float = 0;
		if (!character.isPlayer) {
			offX = character.getMidpoint().x + 150 + character.cameraPosition[0];
			offY = character.getMidpoint().y - 100 + character.cameraPosition[1];
		} else {
			offX = character.getMidpoint().x - 100 - character.cameraPosition[0];
			offY = character.getMidpoint().y - 100 + character.cameraPosition[1];
		}
		cameraFollowPointer.setPosition(offX, offY);

		if (snap) {
			FlxG.camera.scroll.x = cameraFollowPointer.getMidpoint().x - FlxG.width / 2;
			FlxG.camera.scroll.y = cameraFollowPointer.getMidpoint().y - FlxG.height / 2;
		}
	}

	inline function updateHealthBar() {
		if (healthColorStepperR != null) {
			healthColorStepperR.value = character.healthColorArray[0];
			healthColorStepperG.value = character.healthColorArray[1];
			healthColorStepperB.value = character.healthColorArray[2];
		}
		healthBar.leftBar.color = healthBar.rightBar.color = FlxColor.fromRGB(character.healthColorArray[0], character.healthColorArray[1],
			character.healthColorArray[2]);
		healthIcon.changeIcon(character.healthIcon, false);
		updatePresence();
	}

	inline function updatePresence() {
		#if DISCORD_ALLOWED
		// Updating Discord Rich Presence
		DiscordClient.changePresence("Character Editor", "Character: " + _char, healthIcon.getCharacter());
		#end
	}

	inline function reloadAnimList() {
		anims = character.animationsArray;
		if (anims.length > 0)
			character.playAnim(anims[0].anim, true);
		curAnim = 0;

		updateText();
		if (animationDropDown != null)
			reloadAnimationDropDown();
	}

	inline function updateText() {
		animsTxt.removeFormat(selectedFormat);

		var intendText:String = '';
		for (num => anim in anims) {
			if (num > 0)
				intendText += '\n';

			if (num == curAnim) {
				var n:Int = intendText.length;
				intendText += anim.anim + ": " + anim.offsets;
				animsTxt.addFormat(selectedFormat, n, intendText.length);
			} else
				intendText += anim.anim + ": " + anim.offsets;
		}
		animsTxt.text = intendText;
	}

	// Recompute the current animation's live offset so the preview reflects the
	// flip/scale offset correction after toggling Playable / Flip X, without
	// restarting the animation.
	function reapplyCurrentOffset() {
		if (character == null)
			return;
		var name = character.getAnimationName();
		if (name != null && name.length > 0 && character.animOffsets.exists(name)) {
			var raw = character.animOffsets.get(name);
			character.applyAnimOffset(raw[0], raw[1]);
		}
	}

	inline function updateCharacterPositions() {
		if ((character != null && !character.isPlayer) || (character == null && predictCharacterIsNotPlayer(_char)))
			character.setPosition(dadPosition.x, dadPosition.y);
		else
			character.setPosition(bfPosition.x, bfPosition.y);

		character.x += character.positionArray[0];
		character.y += character.positionArray[1];
		updatePointerPos(false);
	}

	inline function predictCharacterIsNotPlayer(name:String) {
		return (name != 'bf' && !name.startsWith('bf-') && !name.endsWith('-player') && !name.endsWith('-playable') && !name.endsWith('-dead'))
			|| name.endsWith('-opponent')
			|| name.startsWith('gf-')
			|| name.endsWith('-gf')
			|| name == 'gf';
	}

	function addAnimation(anim:String, name:String, fps:Float, loop:Bool, indices:Array<Int>) {
		if (!character.isAnimateAtlas) {
			if (indices != null && indices.length > 0)
				character.animation.addByIndices(anim, name, indices, "", fps, loop);
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

	var characterList:Array<String> = [];

	function reloadCharacterDropDown() {
		characterList = Mods.mergeAllTextsNamed('data/characterList.txt');
		var foldersToCheck:Array<String> = Mods.directoriesWithFile(Paths.getSharedPath(), 'characters/');
		for (folder in foldersToCheck)
			for (file in FileSystem.readDirectory(folder))
				if (file.toLowerCase().endsWith('.json')) {
					var charToCheck:String = file.substr(0, file.length - 5);
					if (!characterList.contains(charToCheck))
						characterList.push(charToCheck);
				}

		if (characterList.length < 1)
			characterList.push('');
		charDropDown.setItems(characterList);
		charDropDown.select(Std.int(Math.max(0, characterList.indexOf(_char))));
	}

	function reloadAnimationDropDown() {
		var animList:Array<String> = [];
		for (anim in anims)
			animList.push(anim.anim);
		if (animList.length < 1)
			animList.push('NO ANIMATIONS'); // Prevents crash

		animationDropDown.setItems(animList);
	}

	// save
	var _file:FileReference;

	function onSaveComplete(_):Void {
		if (_file == null)
			return;
		_file.removeEventListener(Event.COMPLETE, onSaveComplete);
		_file.removeEventListener(Event.CANCEL, onSaveCancel);
		_file.removeEventListener(IOErrorEvent.IO_ERROR, onSaveError);
		_file = null;
		FlxG.log.notice("Successfully saved file.");
	}

	/**
	 * Called when the save file dialog is cancelled.
	 */
	function onSaveCancel(_):Void {
		if (_file == null)
			return;
		_file.removeEventListener(Event.COMPLETE, onSaveComplete);
		_file.removeEventListener(Event.CANCEL, onSaveCancel);
		_file.removeEventListener(IOErrorEvent.IO_ERROR, onSaveError);
		_file = null;
	}

	/**
	 * Called if there is an error while saving the gameplay recording.
	 */
	function onSaveError(_):Void {
		if (_file == null)
			return;
		_file.removeEventListener(Event.COMPLETE, onSaveComplete);
		_file.removeEventListener(Event.CANCEL, onSaveCancel);
		_file.removeEventListener(IOErrorEvent.IO_ERROR, onSaveError);
		_file = null;
		FlxG.log.error("Problem saving file");
	}

	function saveCharacter() {
		if (_file != null)
			return;

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

		if (data.length > 0) {
			_file = new FileReference();
			_file.addEventListener(#if desktop Event.SELECT #else Event.COMPLETE #end, onSaveComplete);
			_file.addEventListener(Event.CANCEL, onSaveCancel);
			_file.addEventListener(IOErrorEvent.IO_ERROR, onSaveError);
			_file.save(data, '$_char.json');
		}
	}

	override function destroy() {
		ClientPrefs.toggleVolumeKeys(true);
		if (uiRoot != null) {
			FlxSmidr.dispose();
			uiRoot = null;
		}
		super.destroy();
	}
}
