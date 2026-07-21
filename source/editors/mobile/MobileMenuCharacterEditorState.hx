package editors.mobile;

import flixel.FlxG;
import flixel.group.FlxGroup.FlxTypedGroup;
import objects.MenuCharacter;
import objects.MenuCharacter.MenuCharacterFile;
import smidr.UILocale;
import smidr.UIFonts;
import smidr.widgets.UICheckbox;
import smidr.widgets.UILabel;
import smidr.widgets.UIScrollPane;
import smidr.widgets.UIStepper;
import smidr.widgets.UITextInput;
import smidr.overlays.UIToast;

/**
 * Touch-native Menu Character editor: the story-menu character preview (3 slots) with the selected slot's
 * config in a rail SETTINGS page, position editable by dragging the character on the canvas (or the nudge
 * action bar). Slot picked from a rail button. Saves `<image>.json`. Same JSON shape as desktop.
 */
class MobileMenuCharacterEditorState extends MobileEditorBase {
	var grpWeekCharacters:FlxTypedGroup<MenuCharacter>;
	var defaultCharacters:Array<String> = ['dad', 'bf', 'gf'];
	var slotNames:Array<String> = ['Opponent', 'Boyfriend', 'Girlfriend'];
	var characterFile:MenuCharacterFile;
	var charType:Int = 0;

	var slotBtn:smidr.widgets.UIButton;

	override function create():Void {
		initPsychCamera();
		FlxG.camera.bgColor = 0xFF1A1A2E;

		UILocale.translate = function(k:String, f:String):String return Language.getPhrase(k, f);
		UIFonts.register('assets/fonts/vcr.ttf');

		characterFile = {
			image: 'Menu_Dad',
			scale: 1,
			position: [0, 0],
			idle_anim: 'M Dad Idle',
			confirm_anim: 'M Dad Idle',
			flipX: false,
			antialiasing: true
		};

		grpWeekCharacters = new FlxTypedGroup<MenuCharacter>();
		for (char in 0...3) {
			var c:MenuCharacter = new MenuCharacter((FlxG.width * 0.25) * (1 + char) - 150, defaultCharacters[char]);
			c.scrollFactor.set();
			grpWeekCharacters.add(c);
		}
		add(grpWeekCharacters);

		buildChrome();

		setupCanvas();
		gestures.onDragMove = function(_x:Float, _y:Float, dx:Float, dy:Float):Void {
			characterFile.position[0] += Std.int(dx);
			characterFile.position[1] += Std.int(dy);
			updateOffset();
		};

		updateCharacters();
		super.create();
	}

	function buildChrome():Void {
		shell = new MobileEditorShell();
		shell.addLeft('< EXIT', exitEditor);
		shell.railGap(true);
		shell.addLeft('OPEN', openCharacter);
		shell.addLeft('SAVE', saveCharacter, true);

		slotBtn = shell.addRight('SLOT: ${slotNames[charType]}', cycleSlot);
		shell.addRight('SETTINGS', openSettingsPage);
		shell.railGap(false);
		shell.addRight('? GUIDE', function() shell.showGuide([
			'SLOT      pick which menu slot to edit (opp / bf / gf)',
			'SETTINGS  image, idle/confirm anims, scale, flip, AA',
			'DRAG      move the character (position offset)',
			'ACTION BAR nudge the position, play confirm',
			'SAVE      writes <image>.json'
		]));

		shell.setActionBar([
			{label: '< ', cb: function() nudge(-1, 0)},
			{label: ' >', cb: function() nudge(1, 0)},
			{label: '^', cb: function() nudge(0, -1)},
			{label: 'v', cb: function() nudge(0, 1)},
			{label: 'CONFIRM', cb: playConfirm}
		]);
		shell.showActionBar(true);
	}

	function cycleSlot():Void {
		charType = (charType + 1) % 3;
		slotBtn.label = 'SLOT: ${slotNames[charType]}';
		reloadSelectedCharacter();
		if (shell.drawerOpen)
			openSettingsPage();
	}

	function nudge(dx:Int, dy:Int):Void {
		characterFile.position[0] += dx * 5;
		characterFile.position[1] += dy * 5;
		updateOffset();
	}

	function playConfirm():Void {
		var c:MenuCharacter = grpWeekCharacters.members[charType];
		if (c.animation.getByName('confirm') != null)
			c.animation.play('confirm', true);
	}

	function openSettingsPage():Void {
		shell.openPage('MENU CHAR: ${slotNames[charType]}', function(pane:UIScrollPane):Float {
			var w:Float = shell.pageWidth();
			var y:Float = 6;

			var img:UITextInput = new UITextInput('Image file name:', w, characterFile.image, function(v:String) {
				characterFile.image = v;
				reloadSelectedCharacter();
			});
			img.y = y;
			pane.content.addChild(img);
			y += 56;

			var idle:UITextInput = new UITextInput('Idle anim (.XML):', w, characterFile.idle_anim, function(v:String) {
				characterFile.idle_anim = v;
				reloadSelectedCharacter();
			});
			idle.y = y;
			pane.content.addChild(idle);
			y += 56;

			var conf:UITextInput = new UITextInput('Start Press anim:', w, characterFile.confirm_anim, function(v:String) {
				characterFile.confirm_anim = v;
				reloadSelectedCharacter();
			});
			conf.y = y;
			pane.content.addChild(conf);
			y += 56;

			var sc:UIStepper = new UIStepper('Scale:', w, characterFile.scale, 0.05, function(v:Float) {
				characterFile.scale = v;
				reloadSelectedCharacter();
			});
			sc.min = 0.1;
			sc.max = 30;
			sc.decimals = 2;
			sc.y = y;
			pane.content.addChild(sc);
			y += 56;

			var flip:UICheckbox = new UICheckbox('Flip X', w, characterFile.flipX == true, function(c:Bool) {
				characterFile.flipX = c;
				grpWeekCharacters.members[charType].flipX = c;
			});
			flip.y = y;
			pane.content.addChild(flip);
			y += 44;

			var aa:UICheckbox = new UICheckbox('Antialiasing', w, characterFile.antialiasing != false, function(c:Bool) {
				characterFile.antialiasing = c;
				grpWeekCharacters.members[charType].antialiasing = c;
			});
			aa.y = y;
			pane.content.addChild(aa);
			y += 44;

			var hint:UILabel = new UILabel('Drag the character on the canvas to set its position.', 13, 2);
			hint.y = y;
			pane.content.addChild(hint);
			return y + 30;
		});
	}

	function updateCharacters():Void {
		for (i in 0...3) {
			var c:MenuCharacter = grpWeekCharacters.members[i];
			c.alpha = 0.2;
			c.character = '';
			c.changeCharacter(defaultCharacters[i]);
		}
		reloadSelectedCharacter();
	}

	function reloadSelectedCharacter():Void {
		var c:MenuCharacter = grpWeekCharacters.members[charType];
		c.alpha = 1;
		c.frames = Paths.getSparrowAtlas('menucharacters/' + characterFile.image);
		c.animation.addByPrefix('idle', characterFile.idle_anim, 24);
		if (charType == 1)
			c.animation.addByPrefix('confirm', characterFile.confirm_anim, 24, false);
		c.flipX = (characterFile.flipX == true);
		c.antialiasing = (characterFile.antialiasing != false) && ClientPrefs.data.antialiasing;
		c.scale.set(characterFile.scale, characterFile.scale);
		c.updateHitbox();
		c.animation.play('idle');
		updateOffset();
	}

	function updateOffset():Void {
		var c:MenuCharacter = grpWeekCharacters.members[charType];
		c.offset.set(characterFile.position[0], characterFile.position[1]);
		shell.setStatus('MENU CHAR EDITOR    slot: ${slotNames[charType]}    image: ${characterFile.image}    pos: ${characterFile.position}');
	}

	function saveCharacter():Void {
		saveFile('${characterFile.image}.json', haxe.Json.stringify(characterFile, '\t'));
	}

	function openCharacter():Void {
		openFile('Menu_Dad.json', 'Open a menu character', function(data:String, _:String):Void {
			try {
				characterFile = cast haxe.Json.parse(data);
				if (characterFile.position == null)
					characterFile.position = [0, 0];
				reloadSelectedCharacter();
				if (shell.drawerOpen)
					openSettingsPage();
			} catch (e:Dynamic) {
				UIToast.show('Load failed: ${Std.string(e)}');
			}
		});
	}
}
