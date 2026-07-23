package editors.mobile;

import flixel.FlxG;
import flixel.FlxSprite;
import flixel.text.FlxText;
import flixel.util.FlxColor;
import backend.WeekData;
import backend.WeekData.WeekFile;
import smidr.UILocale;
import smidr.UIFonts;
import smidr.widgets.UICheckbox;
import smidr.widgets.UILabel;
import smidr.widgets.UIScrollPane;
import smidr.widgets.UITextInput;
import smidr.overlays.UIToast;

using StringTools;

/**
 * Touch-native Week editor: the desktop `WeekEditorState`'s full week config on the mobile shell. A light
 * preview (banner + title + tracklist + characters) fills the canvas; every field lives in a rail-opened
 * drawer page (DETAILS / SONGS / CHARACTERS / UNLOCK). Saves the week JSON directly to `weeks/<file>.json`
 * (the desktop editor uses a file dialog, which doesn't exist on touch), byte-identical to the desktop
 * output so the two interop.
 */
class MobileWeekEditorState extends MobileEditorBase {
	/** The story-menu preview band the background art and the week title live in. **/
	static inline var BAND_Y:Float = 90;

	static inline var BAND_H:Float = 300;

	var weekFile:WeekFile;
	var fileName:String = 'week1';

	var bg:FlxSprite;
	var titleTxt:FlxText;
	var trackTxt:FlxText;
	var charTxt:FlxText;

	public function new(?weekFile:WeekFile) {
		super();
		this.weekFile = (weekFile != null) ? weekFile : WeekData.createWeekFile();
	}

	override function create():Void {
		initPsychCamera();
		FlxG.camera.bgColor = 0xFF12141F;

		UILocale.translate = function(k:String, f:String):String return Language.getPhrase(k, f);
		UIFonts.register('assets/fonts/vcr.ttf');

		buildPreview();
		buildChrome();
		refreshPreview();

		super.create();
	}

	function buildPreview():Void {
		var bgYellow:FlxSprite = new FlxSprite(0, BAND_Y).makeGraphic(FlxG.width, Std.int(BAND_H), 0xFFF9CF51);
		bgYellow.scrollFactor.set();
		add(bgYellow);

		// The story-menu background art, same lookup the desktop editor and Story Menu use, scaled into
		// the (shorter) preview band. Stays hidden while the asset name names nothing.
		bg = new FlxSprite(0, BAND_Y);
		bg.antialiasing = ClientPrefs.data.antialiasing;
		bg.scrollFactor.set();
		bg.visible = false;
		add(bg);

		titleTxt = new FlxText(0, 110, FlxG.width, '', 48);
		titleTxt.setFormat(Paths.font('vcr.ttf'), 48, FlxColor.BLACK, CENTER);
		titleTxt.scrollFactor.set();
		add(titleTxt);

		trackTxt = new FlxText(0, 200, FlxG.width, '', 22);
		trackTxt.setFormat(Paths.font('vcr.ttf'), 22, FlxColor.BLACK, CENTER);
		trackTxt.scrollFactor.set();
		add(trackTxt);

		charTxt = new FlxText(0, 400, FlxG.width, '', 20);
		charTxt.setFormat(Paths.font('vcr.ttf'), 20, FlxColor.WHITE, CENTER, OUTLINE, FlxColor.BLACK);
		charTxt.scrollFactor.set();
		add(charTxt);
	}

	/**
		Loads `images/menubackgrounds/menu_<weekBackground>` into the preview band, letterboxed to its
		width. Hides the sprite when the week names no background (or one that isn't there).
	**/
	function reloadBG():Void {
		var assetName:String = weekFile.weekBackground;
		if (assetName == null || assetName.length < 1) {
			bg.visible = false;
			return;
		}

		var found:Bool = #if MODS_ALLOWED FileSystem.exists(Paths.modsImages('menubackgrounds/menu_' + assetName))
			|| #end openfl.utils.Assets.exists(Paths.getPath('images/menubackgrounds/menu_$assetName.png', IMAGE), IMAGE);
		if (!found) {
			bg.visible = false;
			return;
		}

		try {
			bg.loadGraphic(Paths.image('menubackgrounds/menu_$assetName'));
			// Contain: the story-menu art is wider than the preview band is tall, so fit whichever axis
			// runs out first and centre the result in the band.
			var fit:Float = Math.min(FlxG.width / bg.frameWidth, BAND_H / bg.frameHeight);
			bg.scale.set(fit, fit);
			bg.updateHitbox();
			bg.x = (FlxG.width - bg.width) / 2;
			bg.y = BAND_Y + (BAND_H - bg.height) / 2;
			bg.visible = true;
		} catch (e:Dynamic) {
			bg.visible = false;
		}
	}

	function refreshPreview():Void {
		reloadBG();
		titleTxt.text = (weekFile.storyName != null && weekFile.storyName.length > 0) ? weekFile.storyName : fileName;
		var songs:Array<String> = [];
		for (s in weekFile.songs)
			if (s != null && s[0] != null)
				songs.push(Std.string(s[0]));
		trackTxt.text = 'TRACKS\n' + (songs.length > 0 ? songs.join('\n') : '(none)');
		var chars:Array<String> = weekFile.weekCharacters != null ? weekFile.weekCharacters : ['', '', ''];
		charTxt.text = 'Opponent: ${chars[0]}    BF: ${chars[1] != null ? chars[1] : ''}    GF: ${chars[2] != null ? chars[2] : ''}';
		shell.setStatus('WEEK EDITOR    file: $fileName.json    ${weekFile.songs.length} songs');
	}

	function buildChrome():Void {
		shell = new MobileEditorShell();

		shell.addLeft('< EXIT', exitEditor);
		shell.railGap(true);
		shell.addLeft('OPEN', openWeek);
		shell.addLeft('SAVE', saveWeek, true);

		shell.addRight('DETAILS', openDetailsPage);
		shell.addRight('SONGS', openSongsPage);
		shell.addRight('CHARS', openCharactersPage);
		shell.addRight('UNLOCK', openUnlockPage);
		shell.railGap(false);
		shell.addRight('? GUIDE', function() shell.showGuide([
			'DETAILS   file name, display name, background',
			'SONGS     the week tracklist (one per line)',
			'CHARS     opponent / bf / gf menu characters',
			'UNLOCK    lock state, prerequisite week, difficulties',
			'SAVE      writes weeks/<file>.json'
		]));
	}

	/**
		A labelled field, stacked: the caption on its own line above a full-width box. Side-by-side rows
		put the box at 42% of the width, which the longer week captions ("Week Before (unlocks after):")
		run straight into on the narrow drawer.
	**/
	function field(pane:UIScrollPane, y:Float, label:String, value:String, onChange:String->Void):Float {
		var w:Float = shell.pageWidth();

		var cap:UILabel = new UILabel(label, 13, 2);
		cap.wrapWidth = w;
		var capH:Float = cap.measure();
		cap.y = y;
		pane.content.addChild(cap);

		var t:UITextInput = new UITextInput('', w, value != null ? value : '', function(v:String):Void {
			markDirty();
			onChange(v);
		});
		t.y = y + capH + 2;
		pane.content.addChild(t);
		return y + capH + 2 + t.h + 12;
	}

	inline function toggle(pane:UIScrollPane, y:Float, label:String, checked:Bool, onChange:Bool->Void):Float {
		var c:UICheckbox = new UICheckbox(label, shell.pageWidth(), checked, function(v:Bool):Void {
			markDirty();
			onChange(v);
		});
		c.y = y;
		pane.content.addChild(c);
		return y + 44;
	}

	function openDetailsPage():Void {
		shell.openPage('WEEK DETAILS', function(pane:UIScrollPane):Float {
			var y:Float = 6;
			y = field(pane, y, 'Week File:', fileName, function(v) {
				fileName = v.trim();
				refreshPreview();
			});
			y = field(pane, y, 'Display Name:', weekFile.storyName, function(v) {
				weekFile.storyName = v.trim();
				refreshPreview();
			});
			y = field(pane, y, 'Week Name:', weekFile.weekName, function(v) weekFile.weekName = v.trim());
			y = field(pane, y, 'Background Asset:', weekFile.weekBackground, function(v) {
				weekFile.weekBackground = v.trim();
				refreshPreview();
			});
			return y;
		});
	}

	function openSongsPage():Void {
		shell.openPage('SONGS (one per line)', function(pane:UIScrollPane):Float {
			var y:Float = 6;
			var lines:Array<String> = [];
			for (s in weekFile.songs)
				if (s != null && s[0] != null)
					lines.push(Std.string(s[0]));
			var cap:UILabel = new UILabel('Songs:', 13, 2);
			cap.wrapWidth = shell.pageWidth();
			y += cap.measure() + 2;
			cap.y = 6;
			pane.content.addChild(cap);
			var t:UITextInput = new UITextInput('', shell.pageWidth(), lines.join(', '), function(v:String) {
				markDirty();
				var parts:Array<String> = v.split(',');
				var out:Array<Dynamic> = [];
				for (p in parts) {
					var name:String = p.trim();
					if (name.length < 1)
						continue;
					// keep the icon/color from the matching old entry when the name is unchanged
					var icon:String = 'face';
					var color:Array<Int> = [146, 113, 253];
					for (old in weekFile.songs)
						if (old != null && Std.string(old[0]) == name) {
							if (old[1] != null)
								icon = Std.string(old[1]);
							if (old[2] != null)
								color = old[2];
						}
					out.push([name, icon, color]);
				}
				weekFile.songs = out;
				refreshPreview();
			});
			t.y = y;
			pane.content.addChild(t);
			y += t.h + 12;
			var hint:UILabel = new UILabel('Comma-separated song folder names, in play order.', 13, 2);
			hint.wrapWidth = shell.pageWidth();
			hint.y = y;
			pane.content.addChild(hint);
			return y + hint.measure() + 8;
		});
	}

	function openCharactersPage():Void {
		shell.openPage('MENU CHARACTERS', function(pane:UIScrollPane):Float {
			if (weekFile.weekCharacters == null)
				weekFile.weekCharacters = ['dad', 'bf', 'gf'];
			while (weekFile.weekCharacters.length < 3)
				weekFile.weekCharacters.push('');
			var y:Float = 6;
			y = field(pane, y, 'Opponent:', weekFile.weekCharacters[0], function(v) {
				weekFile.weekCharacters[0] = v.trim();
				refreshPreview();
			});
			y = field(pane, y, 'Boyfriend:', weekFile.weekCharacters[1], function(v) {
				weekFile.weekCharacters[1] = v.trim();
				refreshPreview();
			});
			y = field(pane, y, 'Girlfriend:', weekFile.weekCharacters[2], function(v) {
				weekFile.weekCharacters[2] = v.trim();
				refreshPreview();
			});
			return y;
		});
	}

	function openUnlockPage():Void {
		shell.openPage('UNLOCK & VISIBILITY', function(pane:UIScrollPane):Float {
			var y:Float = 6;
			y = toggle(pane, y, 'Week starts Locked', !weekFile.startUnlocked, function(c) weekFile.startUnlocked = !c);
			y = toggle(pane, y, 'Hidden until Unlocked', weekFile.hiddenUntilUnlocked, function(c) weekFile.hiddenUntilUnlocked = c);
			y = toggle(pane, y, 'Hide from Story Mode', weekFile.hideStoryMode, function(c) weekFile.hideStoryMode = c);
			y = toggle(pane, y, 'Hide from Freeplay', weekFile.hideFreeplay, function(c) weekFile.hideFreeplay = c);
			y += 8;
			y = field(pane, y, 'Week Before (unlocks after):', weekFile.weekBefore, function(v) weekFile.weekBefore = v.trim());
			y = field(pane, y, 'Difficulties (comma list):', weekFile.difficulties, function(v) weekFile.difficulties = v.trim());
			return y;
		});
	}

	function saveWeek():Void {
		saveFile('$fileName.json', haxe.Json.stringify(weekFile, '\t'));
		WeekEditorState.unsavedProgress = false;
	}

	// The unsaved-changes exit prompt (MobileEditorBase) saves through this hook.
	override function saveDocument(?onSaved:Void->Void):Void {
		saveFile('$fileName.json', haxe.Json.stringify(weekFile, '\t'), onSaved);
		WeekEditorState.unsavedProgress = false;
	}

	function openWeek():Void {
		openFile('week.json', 'Open a week file', function(data:String, path:String):Void {
			try {
				weekFile = cast haxe.Json.parse(data);
				fileName = baseName(path);
				unsavedProgress = false;
				refreshPreview();
			} catch (e:Dynamic) {
				UIToast.show('Load failed: ${Std.string(e)}');
			}
		});
	}

	static function baseName(path:String):String {
		if (path == null)
			return 'week1';
		var b:String = path;
		var slash:Int = Std.int(Math.max(b.lastIndexOf('/'), b.lastIndexOf('\\')));
		if (slash >= 0)
			b = b.substr(slash + 1);
		if (b.endsWith('.json'))
			b = b.substr(0, b.length - 5);
		return b.length > 0 ? b : 'week1';
	}
}
