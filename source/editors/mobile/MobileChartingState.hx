package editors.mobile;

import flixel.FlxG;
import backend.SongChart;
import backend.SongChart.SongNote;
import editors.charting.audio.FlxChartAudio;
import editors.charting.audio.IChartAudio;
import editors.charting.data.ChartEditorModel;
import editors.charting.data.ClipboardModel;
import editors.charting.data.EditorPrefs;
import editors.charting.data.SelectionModel;
import editors.charting.data.SnapGrid;
import editors.charting.data.UndoStack;
import editors.charting.render.EditorNoteField;
import editors.content.PsychJsonPrinter;
import mobile.input.EditorCanvasGestures;
import objects.notes.NoteDefaults;
import smidr.UIFonts;
import smidr.UILocale;
import smidr.UITheme;
import smidr.widgets.UIButton;
import smidr.widgets.UICheckbox;
import smidr.widgets.UIDropdown;
import smidr.widgets.UILabel;
import smidr.widgets.UIStepper;
import smidr.widgets.UIToast;

/**
 * Touch-first Chart Editor. Reuses the desktop chart core unchanged -- `ChartEditorModel`,
 * `SelectionModel`, `UndoStack`, `ClipboardModel`, `SnapGrid`, the Flixel `EditorNoteField`, and
 * `IChartAudio` -- and swaps only the UI: a `MobileEditorShell` (top toolbar + settings drawer)
 * plus `EditorCanvasGestures` (pan / pinch-zoom / tap-place / long-press-delete) over the notefield.
 *
 * MVP scope: place/select/delete notes, scroll+fling the timeline, pinch-zoom, playback, BPM, snap,
 * note type, downscroll, and save. Advanced desktop tabs (events, patterns, strumlines, waveform,
 * scripts) are follow-up drawer pages; scripts are skipped because `EditorScriptHost` is bound to
 * the desktop `ChartingState`.
 */
class MobileChartingState extends MusicBeatState {
	static final ZOOM_MIN:Float = 0.25;
	static final ZOOM_MAX:Float = 24;

	var snap:SnapGrid;
	var model:ChartEditorModel;
	var undoStack:UndoStack;
	var selection:SelectionModel;
	var clipboard:ClipboardModel;
	var audio:IChartAudio;
	var noteField:EditorNoteField;

	var shell:MobileEditorShell;
	var gestures:EditorCanvasGestures;

	var noteTypes:Array<String> = [];
	var placeType:String = '';

	override function create():Void {
		FlxG.mouse.visible = false;
		FlxG.camera.bgColor = UITheme.bg;

		EditorPrefs.load();

		snap = new SnapGrid();
		snap.select(EditorPrefs.snapIndex);
		model = new ChartEditorModel();
		undoStack = new UndoStack();
		selection = new SelectionModel();
		clipboard = new ClipboardModel();

		var chart:SongChart = PlayState.SONG;
		if (chart == null || chart.sections.length == 0) {
			chart = new SongChart();
			chart.song = 'Test';
			chart.bpm = 150;
			chart.speed = 1;
			chart.keyCount = 4;
			chart.strumLines.push({index: 0, id: 'opponent', type: 0, isPlayer: false, visible: true, characters: ['dad'], keyCount: 4});
			chart.strumLines.push({index: 1, id: 'player', type: 1, isPlayer: true, visible: true, characters: ['bf'], keyCount: 4});
			model.load(chart);
			model.ensureSectionCount(16);
			PlayState.SONG = chart;
		} else {
			model.load(chart);
		}

		audio = new FlxChartAudio();
		audio.load(backend.Song.loadedSongName, chart.needsVoices);
		audio.setVolumes(EditorPrefs.instVol, EditorPrefs.mainVol, EditorPrefs.oppVol);
		if (audio.loaded) {
			var guard:Int = 0;
			while (model.endTime < audio.length && guard++ < 4000)
				model.ensureSectionCount(model.sectionCount() + 1);
		}

		buildNoteTypes();

		UILocale.translate = function(k:String, f:String):String return Language.getPhrase(k, f);
		UIFonts.register('assets/fonts/vcr.ttf');

		shell = new MobileEditorShell(chart.song);
		shell.onBack = exitEditor;
		shell.onPlayPause = togglePlayback;
		shell.onUndo = doUndo;
		shell.onRedo = doRedo;

		noteField = new EditorNoteField(model, selection, shell.field.x, shell.field.y, shell.field.width, shell.field.height);
		noteField.setDownscroll(EditorPrefs.downscroll);
		noteField.maxTime = audio.loaded ? audio.length : -1;
		add(noteField.group);
		add(noteField.overlay);

		model.onChanged = function():Void noteField.onModelChanged();

		buildDrawer();

		gestures = new EditorCanvasGestures(shell.field);
		gestures.onPan = onPan;
		gestures.onZoom = onZoom;
		gestures.onTap = onTap;
		gestures.onLongPress = onLongPress;

		super.create();
	}

	function buildNoteTypes():Void {
		noteTypes = [''];
		for (id => t in NoteDefaults.defaultNoteTypes)
			if (!noteTypes.contains(t))
				noteTypes.push(t);
	}

	// ---- Drawer settings ----

	function buildDrawer():Void {
		var w:Float = shell.panel.w - UITheme.px(12);
		var y:Float = UITheme.px(4);
		// Typed as UIComponent (not Dynamic): hxcpp can't resolve openfl's `x`/`y` properties through
		// Dynamic reflection ("Invalid field:x"), but the concrete base has them as real fields.
		inline function place(c:smidr.UIComponent, h:Float):Void {
			c.x = UITheme.px(4);
			c.y = y;
			shell.panel.content.addChild(c);
			y += h + UITheme.px(8);
		}

		var header:UILabel = new UILabel('Chart Settings', 15, 0);
		place(header, UITheme.px(20));

		var bpm:UIStepper = new UIStepper('BPM', w, model.chart.bpm, 1, function(v:Float):Void {
			undoStack.snapshotCoalesced(model, 'BPM');
			model.chart.bpm = v;
			model.rebuildTiming();
			noteField.refreshTiming();
		});
		bpm.min = 1;
		bpm.max = 1000;
		bpm.decimals = 2;
		place(bpm, UITheme.px(24));

		var speed:UIStepper = new UIStepper('Scroll Speed', w, model.chart.speed, 0.1, function(v:Float):Void {
			undoStack.snapshotCoalesced(model, 'Speed');
			model.chart.speed = v;
		});
		speed.min = 0.1;
		speed.max = 10;
		speed.decimals = 2;
		place(speed, UITheme.px(24));

		var snapDrop:UIDropdown = new UIDropdown('Snap', w, function(index:Int, _:String):Void {
			snap.select(index);
			EditorPrefs.snapIndex = snap.index;
		});
		var snapLabels:Array<String> = [for (s in SnapGrid.SNAPS) '1/$s'];
		snapDrop.setItems(snapLabels, snapLabels);
		snapDrop.select(snap.index);
		place(snapDrop, UITheme.px(24));

		var typeDrop:UIDropdown = new UIDropdown('New Note Type', w, function(index:Int, value:String):Void {
			placeType = (index >= 0 && index < noteTypes.length) ? noteTypes[index] : '';
			applyTypeToSelection();
		});
		typeDrop.setItems(noteTypes, [for (i => n in noteTypes) (n == '') ? '$i. Normal' : '$i. $n']);
		typeDrop.select(0);
		place(typeDrop, UITheme.px(24));

		var down:UICheckbox = new UICheckbox('Downscroll', w, EditorPrefs.downscroll, function(checked:Bool):Void {
			EditorPrefs.downscroll = checked;
			noteField.setDownscroll(checked);
		});
		place(down, UITheme.px(24));

		var half:Float = (w - UITheme.px(8)) / 2;
		var prev:UIButton = new UIButton('< Section', half, UITheme.px(26), function() gotoSectionDelta(-1));
		prev.x = UITheme.px(4);
		prev.y = y;
		shell.panel.content.addChild(prev);
		var next:UIButton = new UIButton('Section >', half, UITheme.px(26), function() gotoSectionDelta(1));
		next.x = UITheme.px(4) + half + UITheme.px(8);
		next.y = y;
		shell.panel.content.addChild(next);
		y += UITheme.px(26) + UITheme.px(8);

		var save:UIButton = new UIButton('Save Chart', w, UITheme.px(30), saveChart, true);
		place(save, UITheme.px(30));

		shell.panel.refreshContent(y + UITheme.px(8));
	}

	function applyTypeToSelection():Void {
		if (selection.notes.length == 0)
			return;
		undoStack.snapshot(model, 'Note Type');
		var i:Int = selection.notes.length;
		while (--i >= 0)
			selection.notes[i].type = placeType;
		model.markDirty();
	}

	// ---- Gesture handlers ----

	function onPan(dx:Float, dy:Float):Void {
		if (audio.playing)
			return; // don't fight playback auto-scroll
		var cell:Float = noteField.cellSize;
		if (cell > 0)
			noteField.scrollSteps(-dy / cell);
	}

	function onZoom(factor:Float, _:Float, __:Float):Void {
		var z:Float = noteField.zoom * factor;
		z = (z < ZOOM_MIN) ? ZOOM_MIN : (z > ZOOM_MAX ? ZOOM_MAX : z);
		noteField.setZoom(z);
	}

	function onTap(x:Float, y:Float):Void {
		if (audio.playing)
			return;
		var hit:SongNote = noteField.noteUnder(x, y);
		if (hit != null) {
			if (selection.notes.indexOf(hit) >= 0)
				selection.remove(hit);
			else
				selection.setAll([hit]);
			return;
		}
		var lane:Int = noteField.laneAt(x);
		var line:Int = noteField.laneStrumLine(lane);
		if (line < 0)
			return;
		var t:Float = model.floorTime(noteField.timeAtY(y), snap.value);
		if (t < 0)
			t = 0;
		undoStack.snapshot(model, 'Place Note');
		var n:SongNote = model.addNote(t, line, noteField.laneColumn(lane), 0, placeType);
		selection.setAll([n]);
	}

	function onLongPress(x:Float, y:Float):Void {
		var hit:SongNote = noteField.noteUnder(x, y);
		if (hit == null)
			return;
		undoStack.snapshot(model, 'Remove Note');
		selection.remove(hit);
		model.removeNote(hit);
	}

	// ---- Transport / sections / undo ----

	function togglePlayback():Void {
		if (audio.playing)
			audio.pause();
		else
			audio.play(noteField.viewTime);
		shell.setPlaying(audio.playing);
	}

	function gotoSectionDelta(dir:Int):Void {
		var sec:Int = model.sectionAt(noteField.viewTime) + dir;
		if (sec < 0)
			sec = 0;
		if (sec >= model.sectionCount())
			sec = model.sectionCount() - 1;
		noteField.setViewTime(model.sectionTimes[sec]);
	}

	function doUndo():Void {
		var label:String = undoStack.undo(model);
		if (label != null) {
			selection.prune(model.chart.noteList);
			UIToast.show('Undid: $label');
		}
	}

	function doRedo():Void {
		var label:String = undoStack.redo(model);
		if (label != null) {
			selection.prune(model.chart.noteList);
			UIToast.show('Redid: $label');
		}
	}

	function saveChart():Void {
		#if sys
		try {
			var data:String = PsychJsonPrinter.print(backend.Song.buildPsychV2(cast model.chart, model.chart), backend.Song.PSYCH_V2_INLINE,
				backend.Song.PSYCH_V2_KEY_ORDER);
			var name:String = Paths.formatToSongPath(model.chart.song);
			if (!sys.FileSystem.exists('charts'))
				sys.FileSystem.createDirectory('charts');
			var path:String = 'charts/$name.json';
			sys.io.File.saveContent(path, data);
			UIToast.show('Saved to $path');
		} catch (e:Dynamic) {
			UIToast.show('Save failed: ${Std.string(e)}');
		}
		#end
	}

	function exitEditor():Void {
		MusicBeatState.switchState(new editors.MasterEditorMenu());
		FlxG.sound.playMusic(Paths.music('freakyMenu'));
	}

	override function update(elapsed:Float):Void {
		audio.update(elapsed);
		if (audio.playing) {
			noteField.setViewTime(audio.time);
			if (audio.time >= audio.length)
				togglePlayback();
		}
		noteField.updateHot(elapsed);
		gestures.update(elapsed);

		#if android
		if (mobile.backend.BackButton.justPressed)
			exitEditor();
		#end

		super.update(elapsed);
	}

	override function destroy():Void {
		if (gestures != null)
			gestures.enabled = false;
		if (audio != null)
			audio.destroy();
		if (noteField != null)
			noteField.dispose();
		if (shell != null)
			shell.dispose();
		super.destroy();
	}
}
