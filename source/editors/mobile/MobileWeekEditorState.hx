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
		var bgYellow:FlxSprite = new FlxSprite(0, 90).makeGraphic(FlxG.width, 300, 0xFFF9CF51);
		bgYellow.scrollFactor.set();
		add(bgYellow);

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

	function refreshPreview():Void {
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

	inline function field(pane:UIScrollPane, y:Float, label:String, value:String, onChange:String->Void):Float {
		var t:UITextInput = new UITextInput(label, shell.pageWidth(), value != null ? value : '', onChange);
		t.y = y;
		pane.content.addChild(t);
		return y + 56;
	}

	inline function toggle(pane:UIScrollPane, y:Float, label:String, checked:Bool, onChange:Bool->Void):Float {
		var c:UICheckbox = new UICheckbox(label, shell.pageWidth(), checked, onChange);
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
			y = field(pane, y, 'Background Asset:', weekFile.weekBackground, function(v) weekFile.weekBackground = v.trim());
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
			var t:UITextInput = new UITextInput('Songs:', shell.pageWidth(), lines.join(', '), function(v:String) {
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
			y += 56;
			var hint:UILabel = new UILabel('Comma-separated song folder names, in play order.', 13, 2);
			hint.y = y;
			pane.content.addChild(hint);
			return y + 30;
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

	function openWeek():Void {
		openFile('week.json', 'Open a week file', function(data:String, path:String):Void {
			try {
				weekFile = cast haxe.Json.parse(data);
				fileName = baseName(path);
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
