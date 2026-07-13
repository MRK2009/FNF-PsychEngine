package editors.content;

import haxe.io.Path;
import flixel.util.FlxDestroyUtil;
import flash.net.FileFilter;
import backend.StageData;
import editors.content.FileDialogHandler;
import editors.content.Prompt.BasePrompt;
import smidr.UIComponent;
import smidr.UITheme;
import smidr.widgets.UIButton;
import smidr.widgets.UICheckbox;
import smidr.widgets.UIScrollPane;
import smidr.overlays.UIToast;

class PreloadListSubState extends BasePrompt {
	var lockedList:Array<String>;
	var preloadList:Map<String, LoadFilters>;
	var preloadListKeys:Array<String> = [];
	var saveCallback:Map<String, LoadFilters>->Void;

	var fileDialog:FileDialogHandler = new FileDialogHandler();

	var listPane:UIScrollPane;
	var listButtons:Array<UIButton> = [];
	var selIndex:Int = -1;

	var removeButton:UIButton;
	var lqCheckBox:UICheckbox;
	var hqCheckBox:UICheckbox;
	var smCheckBox:UICheckbox;

	static inline var W:Int = 560;
	static inline var H:Int = 520;

	public function new(saveCallback:Map<String, LoadFilters>->Void, locked:Array<String> = null, list:Map<String, LoadFilters> = null) {
		this.saveCallback = saveCallback;
		lockedList = (locked != null) ? locked : [];
		preloadList = (list != null) ? list : [];

		for (k => v in preloadList)
			preloadListKeys.push(k);

		super(W, H, 'Preload List', buildUI);
	}

	function buildUI(_):Void {
		var body = modal.body;
		var bodyH:Float = H - UITheme.px(40);

		listPane = new UIScrollPane(330, bodyH - 70);
		listPane.x = 16;
		listPane.y = 4;
		body.addChild(listPane);

		var rightX:Float = 362;
		var rightW:Float = W - rightX - 16;

		function updateFilters(_:Bool):Void {
			var name:String = getCurCheckedName();
			if (!preloadList.exists(name))
				return;

			var filters:LoadFilters = 0;
			if (lqCheckBox.checked)
				filters |= LOW_QUALITY;
			if (hqCheckBox.checked)
				filters |= HIGH_QUALITY;
			if (smCheckBox.checked)
				filters |= STORY_MODE;
			preloadList.set(name, filters);
		}

		lqCheckBox = new UICheckbox('Low Qual.', rightW, false, updateFilters);
		lqCheckBox.x = rightX;
		lqCheckBox.y = 4;
		body.addChild(lqCheckBox);

		hqCheckBox = new UICheckbox('High Qual.', rightW, false, updateFilters);
		hqCheckBox.x = rightX;
		hqCheckBox.y = 32;
		body.addChild(hqCheckBox);

		smCheckBox = new UICheckbox('Story Mode', rightW, false, updateFilters);
		smCheckBox.x = rightX;
		smCheckBox.y = 60;
		body.addChild(smCheckBox);

		removeButton = new UIButton('Remove Selected', rightW, 26, function() {
			var name:String = getCurCheckedName();
			if (!preloadList.exists(name))
				return;

			preloadList.remove(name);
			preloadListKeys.remove(name);
			selIndex = -1;
			rebuildList();
			updateButtons();
		});
		removeButton.danger = true;
		removeButton.x = rightX;
		removeButton.y = 100;
		body.addChild(removeButton);

		var btnY:Float = bodyH - 46;
		var loadFileBtn:UIButton = new UIButton('Load File', 160, 28, function() {
			if (!fileDialog.completed)
				return;

			fileDialog.open(null, 'Load a .PNG/.OGG File...', [#if !mac new FileFilter('Image/Audio', '*.png;*.ogg') #end], function() {
				var path:Path = new Path(fileDialog.path.replace('\\', '/'));

				var ext:String = path.ext;
				if (ext != null)
					ext = ext.toLowerCase();

				switch (ext) {
					case 'png', 'ogg':
						addToList(path, false);
					default:
						showOutput('Unsupported Extension: $ext', true);
				}
			});
		});
		loadFileBtn.x = 16;
		loadFileBtn.y = btnY;
		body.addChild(loadFileBtn);

		var loadFolderBtn:UIButton = new UIButton('Load Folder', 160, 28, function() {
			if (!fileDialog.completed)
				return;

			fileDialog.openDirectory('Load a folder...', function() {
				addToList(new Path(fileDialog.path.replace('\\', '/')), true);
			});
		});
		loadFolderBtn.x = 186;
		loadFolderBtn.y = btnY;
		body.addChild(loadFolderBtn);

		var saveBtn:UIButton = new UIButton('Save', 150, 28, function() {
			if (!fileDialog.completed)
				return;

			if (saveCallback != null)
				saveCallback(preloadList);
			close();
		}, true);
		saveBtn.x = W - 16 - 150;
		saveBtn.y = btnY;
		body.addChild(saveBtn);

		rebuildList();
		updateButtons();
	}

	function addToList(path:Path, isFolder:Bool):Void {
		var exePath:String = Sys.getCwd().replace('\\', '/');
		if (path.dir.startsWith(exePath)) {
			var pathStr:String = path.dir.substr(exePath.length);
			var split:Array<String> = pathStr.split('/');
			switch (split[0]) {
				case 'assets', 'mods':
					for (i in 1...3) {
						switch (split[i]) {
							case 'sounds', 'music', 'songs', 'images':
								split.shift();
								if (i == 2)
									split.shift();

								pathStr = split.join('/') + '/' + path.file;
								if (isFolder && !pathStr.endsWith('/'))
									pathStr += '/';

								if (!lockedList.contains(pathStr)) {
									preloadList.set(pathStr, LOW_QUALITY | HIGH_QUALITY);
									preloadListKeys.push(pathStr);
									rebuildList();
									showOutput('File added to preload: $pathStr');
								} else
									showOutput('File is already preloaded automatically!', true);
								return;
						}
					}
					showOutput('File must be inside images/music/songs subfolder!', true);
				default:
					showOutput('File must be inside assets/mods folder!', true);
			}
		} else
			showOutput('File is not inside Psych Engine\'s folder!', true);
	}

	function rebuildList():Void {
		if (listPane == null)
			return;
		var i:Int = listPane.content.numChildren;
		while (--i >= 0) {
			var c = listPane.content.getChildAt(i);
			if (c is UIComponent)
				(cast c : UIComponent).dispose();
		}
		listPane.content.removeChildren();

		listButtons = [];
		var rowW:Float = listPane.w - UITheme.px(4) - 12;
		var y:Float = 2;
		for (n in 0...preloadListKeys.length) {
			var idx:Int = n;
			var btn:UIButton = new UIButton(preloadListKeys[n], rowW, 24, function() {
				selIndex = idx;
				for (b in 0...listButtons.length)
					listButtons[b].accent = (b == idx);
				updateButtons();
			});
			btn.fontSize = 10;
			btn.tooltip = preloadListKeys[n];
			btn.accent = (n == selIndex);
			btn.y = y;
			listPane.content.addChild(btn);
			listButtons.push(btn);
			y += 27;
		}
		listPane.refreshContent(y + 2);
	}

	override function update(elapsed:Float) {
		super.update(elapsed);
		if (fileDialog.completed && controls.BACK)
			close();
	}

	function updateButtons():Void {
		var hasSel:Bool = (selIndex >= 0 && selIndex < preloadListKeys.length);
		if (hasSel) {
			var filters:LoadFilters = getCurLoadFilters();
			lqCheckBox.checked = (filters & LOW_QUALITY == LOW_QUALITY);
			hqCheckBox.checked = (filters & HIGH_QUALITY == HIGH_QUALITY);
			smCheckBox.checked = (filters & STORY_MODE == STORY_MODE);
		}

		removeButton.visible = hasSel;
		lqCheckBox.visible = hasSel;
		hqCheckBox.visible = hasSel;
		smCheckBox.visible = hasSel;
	}

	inline function getCurLoadFilters():LoadFilters {
		return (selIndex >= 0 && selIndex < preloadListKeys.length) ? preloadList.get(getCurCheckedName()) : 0;
	}

	inline function getCurCheckedName():String {
		return (selIndex >= 0 && selIndex < preloadListKeys.length) ? preloadListKeys[selIndex] : '';
	}

	function showOutput(txt:String, isError:Bool = false):Void {
		UIToast.show(txt);

		if (isError)
			FlxG.sound.play(Paths.sound('cancelMenu'), 0.4);
		else
			FlxG.sound.play(Paths.sound('scrollMenu'), 0.4);
	}

	override function destroy() {
		fileDialog = FlxDestroyUtil.destroy(fileDialog);
		super.destroy();
	}
}
