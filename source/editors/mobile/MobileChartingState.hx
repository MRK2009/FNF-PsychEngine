package editors.mobile;

import flixel.FlxCamera;
import flixel.FlxG;
import flixel.math.FlxRect;
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
import smidr.widgets.UIScrollPane;
import smidr.widgets.UIStepper;
import smidr.widgets.UIToast;

/**
 * The touch-first Chart Editor, designed for Android (landscape, two-thumb use).
 *
 * The chart grid fills the WHOLE screen on its own magnifying `FlxCamera`: it renders big by
 * default (auto-fit zoom) and a two-finger pinch makes it bigger still -- true magnification, not
 * a row stretch. One finger scrolls the chart (with fling) and pans sideways while zoomed in.
 * Tap places or selects a note; holding a note deletes it. Selecting shows a floating action bar
 * (Delete / Sustain -/+ / Deselect). Everything else lives on two thumb rails of big buttons and
 * full-height drawer pages (note type, snap, settings) with large rows. A gesture guide opens on
 * first run and from the "?" button.
 *
 * Reuses the desktop chart core unchanged: `ChartEditorModel` / `SelectionModel` / `UndoStack` /
 * `ClipboardModel` / `SnapGrid` / `EditorNoteField` / `IChartAudio`. Scripts and the advanced
 * desktop tabs are follow-up drawer pages.
 */
class MobileChartingState extends MusicBeatState {
	static inline var ZOOM_MIN:Float = 1.0;
	static inline var ZOOM_MAX:Float = 3.2;

	var snap:SnapGrid;
	var model:ChartEditorModel;
	var undoStack:UndoStack;
	var selection:SelectionModel;
	var clipboard:ClipboardModel;
	var audio:IChartAudio;
	var noteField:EditorNoteField;

	var shell:MobileEditorShell;
	var gestures:EditorCanvasGestures;
	var gridCam:FlxCamera;

	var playBtn:UIButton;
	var typeBtn:UIButton;
	var snapBtn:UIButton;

	var noteTypes:Array<String> = [];
	var placeType:String = '';

	var statusTick:Float = 0;

	override function create():Void {
		// Claim the psych camera FIRST: MusicBeatState.create (super.create, called last) runs
		// FlxG.cameras.reset when it wasn't initialized, which would DESTROY the grid camera
		// created below (nulling its scroll -> NPE on the first gesture).
		initPsychCamera();
		FlxG.mouse.visible = false;
		FlxG.camera.bgColor = 0xFF101014;

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

		// The grid: full-screen logical field on its own magnifying camera.
		noteField = new EditorNoteField(model, selection, 0, 0, FlxG.width, FlxG.height);
		noteField.setDownscroll(EditorPrefs.downscroll);
		noteField.maxTime = audio.loaded ? audio.length : -1;
		noteField.vortexEnabled = false;
		noteField.waveEnabled = false;
		add(noteField.group);
		add(noteField.overlay);

		gridCam = new FlxCamera(0, 0, FlxG.width, FlxG.height);
		gridCam.bgColor = 0x00000000;
		FlxG.cameras.add(gridCam, false);
		noteField.group.cameras = [gridCam];
		noteField.overlay.cameras = [gridCam];
		gridCam.zoom = fitZoom();

		model.onChanged = function():Void noteField.onModelChanged();
		selection.onChanged = refreshActionBar;

		buildChrome();

		gestures = new EditorCanvasGestures(FlxRect.get(0, 0, FlxG.width, FlxG.height));
		gestures.onPan = onPan;
		gestures.onZoom = onZoom;
		gestures.onTap = onTap;
		gestures.onLongPress = onLongPress;

		if (FlxG.save.data.mobileChartGuideSeen != true)
			openGuide(true);

		super.create();
	}

	function buildNoteTypes():Void {
		noteTypes = [''];
		for (id => t in NoteDefaults.defaultNoteTypes)
			if (!noteTypes.contains(t))
				noteTypes.push(t);
	}

	// ---- Chrome (rails / action bar / guide) ----

	function buildChrome():Void {
		shell = new MobileEditorShell();

		shell.addLeft('< EXIT', exitEditor);
		shell.railGap(true);
		playBtn = shell.addLeft('PLAY', togglePlayback, true);
		shell.addLeft('SECT ^', function() gotoSectionDelta(-1));
		shell.addLeft('SECT v', function() gotoSectionDelta(1));
		shell.railGap(true);
		shell.addLeft('UNDO', doUndo);
		shell.addLeft('REDO', doRedo);

		typeBtn = shell.addRight(typeLabel(), openTypePage);
		snapBtn = shell.addRight('SNAP ${snap.label()}', openSnapPage);
		shell.railGap(false);
		shell.addRight('SETTINGS', openSettingsPage);
		shell.railGap(false);
		shell.addRight('? GUIDE', function() openGuide(false));

		shell.setActionBar([
			{label: 'DELETE', cb: deleteSelection, danger: true},
			{label: 'SUS -', cb: function() bumpSelectedSustains(-1)},
			{label: 'SUS +', cb: function() bumpSelectedSustains(1)},
			{label: 'DONE', cb: function() selection.clear()}
		]);
		refreshActionBar();
		updateStatus();
	}

	function typeLabel():String {
		return 'NOTE: ' + ((placeType == '') ? 'Normal' : placeType);
	}

	function openGuide(firstRun:Bool):Void {
		shell.showGuide([
			'DRAG          scroll the chart (flick to fling)',
			'PINCH         zoom the grid bigger / smaller',
			'TAP           place a note / select a note',
			'HOLD A NOTE   delete it',
			'THUMB RAILS   playback, sections, note type, snap'
		], function() {
			if (firstRun) {
				FlxG.save.data.mobileChartGuideSeen = true;
				FlxG.save.flush();
			}
		});
	}

	// ---- Drawer pages ----

	function openTypePage():Void {
		shell.openPage('NOTE TYPE', function(pane:UIScrollPane):Float {
			var w:Float = shell.pageWidth();
			var y:Float = 4;
			for (i in 0...noteTypes.length) {
				var t:String = noteTypes[i];
				var label:String = (t == '') ? '$i. Normal' : '$i. $t';
				var row:UIButton = new UIButton(label, w, 54, function() {
					placeType = t;
					typeBtn.label = typeLabel();
					applyTypeToSelection();
					shell.closeDrawer();
				}, t == placeType);
				row.fontSize = 15;
				row.y = y;
				pane.content.addChild(row);
				y += 60;
			}
			return y + 8;
		});
	}

	function openSnapPage():Void {
		shell.openPage('SNAP', function(pane:UIScrollPane):Float {
			var w:Float = shell.pageWidth();
			var chipW:Float = (w - 20) / 3;
			var x:Float = 0;
			var y:Float = 4;
			var col:Int = 0;
			for (i in 0...SnapGrid.SNAPS.length) {
				var idx:Int = i;
				var chip:UIButton = new UIButton('1/${SnapGrid.SNAPS[i]}', chipW, 56, function() {
					snap.select(idx);
					EditorPrefs.snapIndex = snap.index;
					snapBtn.label = 'SNAP ${snap.label()}';
					shell.closeDrawer();
				}, i == snap.index);
				chip.fontSize = 16;
				chip.x = x;
				chip.y = y;
				pane.content.addChild(chip);
				col++;
				if (col >= 3) {
					col = 0;
					x = 0;
					y += 64;
				} else
					x += chipW + 10;
			}
			return y + 72;
		});
	}

	function openSettingsPage():Void {
		shell.openPage('SETTINGS', function(pane:UIScrollPane):Float {
			var w:Float = shell.pageWidth();
			var y:Float = 6;

			var bpm:UIStepper = new UIStepper('BPM', w, model.chart.bpm, 1, function(v:Float):Void {
				undoStack.snapshotCoalesced(model, 'BPM');
				model.chart.bpm = v;
				model.rebuildTiming();
				noteField.refreshTiming();
			});
			bpm.min = 1;
			bpm.max = 1000;
			bpm.decimals = 2;
			bpm.y = y;
			pane.content.addChild(bpm);
			y += 52;

			var speed:UIStepper = new UIStepper('Scroll Speed', w, model.chart.speed, 0.1, function(v:Float):Void {
				undoStack.snapshotCoalesced(model, 'Speed');
				model.chart.speed = v;
			});
			speed.min = 0.1;
			speed.max = 10;
			speed.decimals = 2;
			speed.y = y;
			pane.content.addChild(speed);
			y += 52;

			var down:UICheckbox = new UICheckbox('Downscroll', w, EditorPrefs.downscroll, function(checked:Bool):Void {
				EditorPrefs.downscroll = checked;
				noteField.setDownscroll(checked);
			});
			down.y = y;
			pane.content.addChild(down);
			y += 60;

			var save:UIButton = new UIButton('SAVE CHART', w, 60, saveChart, true);
			save.fontSize = 16;
			save.y = y;
			pane.content.addChild(save);
			y += 70;

			return y + 8;
		});
	}

	// ---- Camera (magnification) ----

	/** Grid world bounds (left/right), for pan clamping and fit-zoom. **/
	function gridBounds():{left:Float, right:Float} {
		var left:Float = noteField.laneScreenX(-1, 0); // the event lane starts the grid
		var right:Float = left + 200;
		var lines:Array<backend.SongChart.StrumLineData> = model.chart.strumLines;
		var i:Int = lines.length;
		while (--i >= 0) {
			if (lines[i].visible) {
				var x:Float = noteField.laneScreenX(i, lines[i].keyCount - 1);
				if (x >= 0) {
					right = x + noteField.cellSize;
					break;
				}
			}
		}
		return {left: left, right: right};
	}

	/** The auto-fit magnification: the grid fills the space between the thumb rails. **/
	function fitZoom():Float {
		var b = gridBounds();
		var gridW:Float = b.right - b.left + 60;
		if (gridW <= 0)
			return 2.0;
		var usable:Float = FlxG.width - MobileEditorShell.RAIL_W * 2 - 30;
		var z:Float = usable / gridW;
		return (z < ZOOM_MIN) ? ZOOM_MIN : (z > 2.6 ? 2.6 : z);
	}

	// world x of a screen x: world = screen/zoom + viewMargin + scroll, and at the screen center
	// the margins cancel: world(cx) = cx + scroll.x. Mirrors FlxPointer.getViewPosition math.
	inline function worldX(screenX:Float):Float {
		return (screenX - gridCam.x) / gridCam.zoom + gridCam.viewMarginX + gridCam.scroll.x;
	}

	inline function worldY(screenY:Float):Float {
		return (screenY - gridCam.y) / gridCam.zoom + gridCam.viewMarginY + gridCam.scroll.y;
	}

	function clampScrollX():Void {
		var b = gridBounds();
		var halfVis:Float = (FlxG.width / gridCam.zoom) / 2;
		var centerWorld:Float = FlxG.width / 2 + gridCam.scroll.x;
		var min:Float = b.left - 40 + halfVis;
		var max:Float = b.right + 40 - halfVis;
		if (min > max) {
			// grid narrower than the view: keep it centered
			gridCam.scroll.x = (b.left + b.right) / 2 - FlxG.width / 2;
			return;
		}
		if (centerWorld < min)
			gridCam.scroll.x = min - FlxG.width / 2;
		else if (centerWorld > max)
			gridCam.scroll.x = max - FlxG.width / 2;
	}

	// ---- Gestures ----

	function onPan(dx:Float, dy:Float):Void {
		if (!audio.playing) {
			var cell:Float = noteField.cellSize;
			if (cell > 0) {
				var dir:Float = EditorPrefs.downscroll ? -1 : 1;
				noteField.scrollSteps(-(dy / gridCam.zoom) / cell * dir);
			}
		}
		gridCam.scroll.x -= dx / gridCam.zoom;
		clampScrollX();
	}

	function onZoom(factor:Float, focalX:Float, _:Float):Void {
		var z:Float = gridCam.zoom * factor;
		z = (z < ZOOM_MIN) ? ZOOM_MIN : (z > ZOOM_MAX ? ZOOM_MAX : z);
		// keep the world point under the fingers horizontally fixed while magnifying
		var before:Float = worldX(focalX);
		gridCam.zoom = z;
		gridCam.scroll.x += before - worldX(focalX);
		clampScrollX();
		updateStatus();
	}

	function onTap(x:Float, y:Float):Void {
		if (audio.playing)
			return;
		var wx:Float = worldX(x);
		var wy:Float = worldY(y);
		var hit:SongNote = noteField.noteUnder(wx, wy);
		if (hit != null) {
			selection.setAll([hit]);
			return;
		}
		var lane:Int = noteField.laneAt(wx);
		var line:Int = noteField.laneStrumLine(lane);
		if (line < 0)
			return;
		var t:Float = model.floorTime(noteField.timeAtY(wy), snap.value);
		if (t < 0)
			t = 0;
		undoStack.snapshot(model, 'Place Note');
		var n:SongNote = model.addNote(t, line, noteField.laneColumn(lane), 0, placeType);
		selection.setAll([n]);
	}

	function onLongPress(x:Float, y:Float):Void {
		var hit:SongNote = noteField.noteUnder(worldX(x), worldY(y));
		if (hit == null)
			return;
		undoStack.snapshot(model, 'Remove Note');
		selection.remove(hit);
		model.removeNote(hit);
	}

	// ---- Selection actions ----

	function refreshActionBar():Void {
		shell.showActionBar(selection.count > 0);
	}

	function deleteSelection():Void {
		if (selection.count == 0)
			return;
		undoStack.snapshot(model, 'Remove Notes');
		var i:Int = selection.notes.length;
		while (--i >= 0)
			model.removeNote(selection.notes[i]);
		selection.clear();
	}

	function bumpSelectedSustains(dir:Int):Void {
		if (selection.count == 0)
			return;
		undoStack.snapshotCoalesced(model, 'Sustain');
		var i:Int = selection.notes.length;
		while (--i >= 0) {
			var n:SongNote = selection.notes[i];
			var unit:Float = model.snapMs(model.sectionAt(n.time), snap.value);
			var len:Float = n.length + dir * unit;
			n.length = (len > 0) ? len : 0;
		}
		model.markDirty();
	}

	function applyTypeToSelection():Void {
		if (selection.count == 0)
			return;
		undoStack.snapshot(model, 'Note Type');
		var i:Int = selection.notes.length;
		while (--i >= 0)
			selection.notes[i].type = placeType;
		model.markDirty();
	}

	// ---- Transport / undo / save ----

	function togglePlayback():Void {
		if (audio.playing)
			audio.pause();
		else
			audio.play(noteField.viewTime);
		playBtn.label = audio.playing ? 'PAUSE' : 'PLAY';
		playBtn.accent = !audio.playing;
	}

	function gotoSectionDelta(dir:Int):Void {
		var sec:Int = model.sectionAt(noteField.viewTime) + dir;
		if (sec < 0)
			sec = 0;
		if (sec >= model.sectionCount())
			sec = model.sectionCount() - 1;
		noteField.setViewTime(model.sectionTimes[sec]);
		updateStatus();
	}

	function doUndo():Void {
		var label:String = undoStack.undo(model);
		if (label != null) {
			selection.prune(model.chart.noteList);
			UIToast.show('Undid: $label');
		} else
			UIToast.show('Nothing to undo');
	}

	function doRedo():Void {
		var label:String = undoStack.redo(model);
		if (label != null) {
			selection.prune(model.chart.noteList);
			UIToast.show('Redid: $label');
		} else
			UIToast.show('Nothing to redo');
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

	// ---- Status strip ----

	function updateStatus():Void {
		var t:Float = noteField.viewTime;
		var sec:Int = model.sectionAt(t);
		var zoomTxt:String = '${Math.round(gridCam.zoom * 10) / 10}x';
		shell.setStatus('${model.chart.song}    SECTION ${sec + 1}/${model.sectionCount()}    ${fmtTime(t)} / ${fmtTime(model.endTime)}    ZOOM $zoomTxt');
	}

	static function fmtTime(ms:Float):String {
		var s:Int = Std.int(ms / 1000);
		var m:Int = Std.int(s / 60);
		var r:Int = s - m * 60;
		return '$m:' + (r < 10 ? '0$r' : '$r');
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

		statusTick += elapsed;
		if (statusTick >= 0.25) {
			statusTick = 0;
			updateStatus();
		}

		#if android
		if (mobile.backend.BackButton.justPressed) {
			if (shell.guideOpen)
				shell.closeGuide();
			else if (shell.drawerOpen)
				shell.closeDrawer();
			else if (selection.count > 0)
				selection.clear();
			else
				exitEditor();
		}
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
		if (gridCam != null)
			FlxG.cameras.remove(gridCam);
		if (shell != null)
			shell.dispose();
		super.destroy();
	}
}
