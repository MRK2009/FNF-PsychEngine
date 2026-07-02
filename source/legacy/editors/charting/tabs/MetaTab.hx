package legacy.editors.charting.tabs;

import haxe.Json;
import backend.Song;
import legacy.editors.ChartingState;

/**
	Builds the "Meta" tab of the chart editor's main box: edits the per-song `data/<song>/metadata.json`
	that FreeplayState's info flyout reads. Standard fields, optional display overrides, then a growable
	list of custom label/value rows. Unknown keys already in the file (icon/color/difficulties/beatmapId
	from osu! converts) are preserved. Owns load/parse/rebuild/save of the working metadata. Reaches editor
	state/widgets via `@:access`.
**/
@:access(legacy.editors.ChartingState)
class MetaTab {
	/**
		Populates the Meta tab in `s.mainBox`.
		@param s the chart editor that owns the tab box and the metadata working state
	**/
	public static function build(s:ChartingState):Void {
		var tab_group = s.mainBox.getTab('Meta').menu;
		s.metaTabGroup = tab_group;
		loadMetaWorking(s);

		var objX = 10;
		var labW = 78;
		var inX = objX + labW;
		var inW = 200;
		var y = 24;
		var step = 24;

		tab_group.add(new FlxText(objX, y + 2, labW, 'Title:'));
		s.metaTitleInput = new PsychUIInputText(inX, y, inW, (s.metaWorking.songName != null) ? s.metaWorking.songName : '', 8);
		s.metaTitleInput.onChange = function(old:String, cur:String) s.metaWorking.songName = cur;
		tab_group.add(s.metaTitleInput);
		y += step;

		tab_group.add(new FlxText(objX, y + 2, labW, 'Artist:'));
		s.metaArtistInput = new PsychUIInputText(inX, y, inW, (s.metaWorking.artist != null) ? s.metaWorking.artist : '', 8);
		s.metaArtistInput.onChange = function(old:String, cur:String) s.metaWorking.artist = cur;
		tab_group.add(s.metaArtistInput);
		y += step;

		tab_group.add(new FlxText(objX, y + 2, labW, 'Charter:'));
		s.metaCharterInput = new PsychUIInputText(inX, y, inW, (s.metaWorking.charter != null) ? s.metaWorking.charter : '', 8);
		s.metaCharterInput.onChange = function(old:String, cur:String) s.metaWorking.charter = cur;
		tab_group.add(s.metaCharterInput);
		y += step;

		tab_group.add(new FlxText(objX, y + 2, labW, 'Source/Mod:'));
		s.metaSourceInput = new PsychUIInputText(inX, y, inW, (metaSourceValue(s) != null) ? metaSourceValue(s) : '', 8);
		s.metaSourceInput.onChange = function(old:String, cur:String) s.metaWorking.source = cur;
		tab_group.add(s.metaSourceInput);
		y += step;

		tab_group.add(new FlxText(objX, y + 2, labW, 'Tags:'));
		s.metaTagsInput = new PsychUIInputText(inX, y, inW, (s.metaWorking.tags != null) ? s.metaWorking.tags.join(', ') : '', 8);
		s.metaTagsInput.onChange = function(old:String, cur:String) s.metaWorking.tags = parseMetaTags(cur);
		tab_group.add(s.metaTagsInput);
		y += step;

		// Display overrides (0 / blank == use the chart's own value).
		tab_group.add(new FlxText(objX, y + 2, labW, 'Disp BPM:'));
		s.metaBpmStepper = new PsychUINumericStepper(inX, y, 1, (s.metaWorking.displayBpm != null) ? s.metaWorking.displayBpm : 0, 0, 999, 0, 55);
		tab_group.add(s.metaBpmStepper);
		var sig:Array<Int> = s.metaWorking.displayTimeSignature;
		tab_group.add(new FlxText(inX + 65, y + 2, 30, 'Sig:'));
		s.metaSigNumStepper = new PsychUINumericStepper(inX + 95, y, 1, (sig != null && sig.length > 0) ? sig[0] : 0, 0, 16, 0, 42);
		tab_group.add(new FlxText(inX + 140, y + 2, 12, '/'));
		s.metaSigDenStepper = new PsychUINumericStepper(inX + 150, y, 1, (sig != null && sig.length > 1) ? sig[1] : 0, 0, 16, 0, 42);
		tab_group.add(s.metaSigNumStepper);
		tab_group.add(s.metaSigDenStepper);
		y += 30;

		// Custom-field header + the "+" and Save buttons stay put as rows grow below them.
		tab_group.add(new FlxText(objX, y + 4, 90, 'Custom Fields:'));
		var addBtn = new PsychUIButton(objX + 95, y, '+', function() {
			s.metaCustomData.push({label: '', value: ''});
			rebuildMetaCustomRows(s);
		}, 24);
		tab_group.add(addBtn);
		var saveBtn = new PsychUIButton(objX + 130, y, 'Save Metadata', function() saveMeta(s), 110);
		tab_group.add(saveBtn);

		s.metaCustomBaseY = y + 26;
		rebuildMetaCustomRows(s);
	}

	/** Loads the song's metadata.json into the editor's working object (and seeds the custom-field list). **/
	static function loadMetaWorking(s:ChartingState):Void {
		var key:String = Paths.formatToSongPath(PlayState.SONG.song);
		var loaded:backend.SongMeta.SongMetaInfo = backend.SongMeta.load(key);
		s.metaWorking = (loaded != null) ? loaded : (cast {});
		s.metaCustomData = [];
		if (s.metaWorking.info != null)
			for (entry in s.metaWorking.info)
				if (entry != null)
					s.metaCustomData.push({label: entry.label, value: entry.value});
	}

	/** The source field, falling back to the legacy `mod` key. **/
	static inline function metaSourceValue(s:ChartingState):String
		return (s.metaWorking.source != null && s.metaWorking.source.length > 0) ? s.metaWorking.source : s.metaWorking.mod;

	/** Splits a comma-separated tag string into a trimmed list (null when empty). **/
	static function parseMetaTags(raw:String):Array<String> {
		var out:Array<String> = [];
		for (part in raw.split(',')) {
			var t:String = part.trim();
			if (t.length > 0)
				out.push(t);
		}
		return (out.length > 0) ? out : null;
	}

	/**
		Rebuilds the custom-field row widgets from `metaCustomData` (simpler than repositioning survivors
		after a removal).
	**/
	static function rebuildMetaCustomRows(s:ChartingState):Void {
		for (row in s.metaCustomRows) {
			s.metaTabGroup.remove(row.label, true);
			row.label.destroy();
			s.metaTabGroup.remove(row.value, true);
			row.value.destroy();
			s.metaTabGroup.remove(row.del, true);
			row.del.destroy();
		}
		s.metaCustomRows = [];

		for (i in 0...s.metaCustomData.length) {
			var data = s.metaCustomData[i];
			var ry:Float = s.metaCustomBaseY + i * 24;
			var lab = new PsychUIInputText(10, ry, 78, data.label, 8);
			lab.onChange = function(old:String, cur:String) data.label = cur;
			var val = new PsychUIInputText(92, ry, 132, data.value, 8);
			val.onChange = function(old:String, cur:String) data.value = cur;
			var del = new PsychUIButton(Std.int(230), Std.int(ry), 'X', function() {
				s.metaCustomData.remove(data);
				rebuildMetaCustomRows(s);
			}, 20);
			s.metaTabGroup.add(lab);
			s.metaTabGroup.add(val);
			s.metaTabGroup.add(del);
			s.metaCustomRows.push({label: lab, value: val, del: del});
		}
	}

	/** Syncs the override steppers + custom rows into the working object and writes metadata.json. **/
	static function saveMeta(s:ChartingState):Void {
		#if sys
		if (Song.chartPath == null) {
			s.showOutput('Save the chart first so the editor knows where to write metadata.json.', true);
			return;
		}

		// Sync the override steppers + custom rows into the working object.
		var bpm:Float = s.metaBpmStepper.value;
		if (bpm > 0) s.metaWorking.displayBpm = bpm; else Reflect.deleteField(s.metaWorking, 'displayBpm');

		var sn:Int = Std.int(s.metaSigNumStepper.value);
		var sd:Int = Std.int(s.metaSigDenStepper.value);
		if (sn > 0 && sd > 0) s.metaWorking.displayTimeSignature = [sn, sd]; else Reflect.deleteField(s.metaWorking, 'displayTimeSignature');

		var info:Array<{label:String, value:String}> = [];
		for (data in s.metaCustomData)
			if (data.label != null && data.label.trim().length > 0)
				info.push({label: data.label.trim(), value: (data.value != null) ? data.value : ''});
		if (info.length > 0) s.metaWorking.info = info; else Reflect.deleteField(s.metaWorking, 'info');

		// Drop empty standard fields so we never write blank keys.
		for (field in ['songName', 'artist', 'charter', 'source']) {
			var v:Dynamic = Reflect.field(s.metaWorking, field);
			if (v == null || Std.string(v).length < 1)
				Reflect.deleteField(s.metaWorking, field);
		}
		if (s.metaWorking.tags != null && s.metaWorking.tags.length < 1)
			Reflect.deleteField(s.metaWorking, 'tags');

		var p:String = Song.chartPath.replace('\\', '/');
		var dir:String = p.substr(0, p.lastIndexOf('/'));
		var metaPath:String = '$dir/metadata.json';
		try {
			File.saveContent(metaPath, Json.stringify(s.metaWorking, null, '\t'));
			s.showOutput('Metadata saved to: $metaPath');
		} catch (e:Dynamic) {
			s.showOutput('Error saving metadata: $e', true);
		}
		#else
		s.showOutput('Metadata saving is only available on desktop.', true);
		#end
	}
}
