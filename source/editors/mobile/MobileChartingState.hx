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
import smidr.widgets.UILabel;
import smidr.widgets.UIScrollPane;
import smidr.widgets.UIStepper;
import smidr.widgets.UITextInput;
import smidr.overlays.UIToast;

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
	var multiBtn:UIButton;

	var multiSelect:Bool = false;

	var noteTypes:Array<String> = [];
	var placeType:String = '';

	var eventNames:Array<String> = [];
	var placeEvent:String = ''; // the event type placed when tapping the event lane

	var statusTick:Float = 0;
	var nextHitIndex:Int = 0; // cursor into the sorted note list for playback hitsounds
	var lastMetroKey:Int = -1; // section*10000 + beat, to tick the metronome once per beat

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
		buildEvents();

		UILocale.translate = function(k:String, f:String):String return Language.getPhrase(k, f);
		UIFonts.register('assets/fonts/vcr.ttf');

		// The grid: full-screen logical field on its own magnifying camera.
		noteField = new EditorNoteField(model, selection, 0, 0, FlxG.width, FlxG.height);
		noteField.setDownscroll(EditorPrefs.downscroll);
		noteField.maxTime = audio.loaded ? audio.length : -1;
		noteField.vortexEnabled = false;
		noteField.waveEnabled = EditorPrefs.waveform;
		if (audio.loaded)
			noteField.waveSource = audio.waveformSound(0);
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
		gestures.onDragStart = onDragStart;
		gestures.onDragMove = onDragMove;
		gestures.onDragEnd = onDragEnd;

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

	function buildEvents():Void {
		eventNames = [];
		for (e in legacy.editors.ChartingState.defaultEvents)
			if (e.length > 0 && e[0].length > 0 && !eventNames.contains(e[0]))
				eventNames.push(e[0]);
		placeEvent = (eventNames.length > 0) ? eventNames[0] : '';
	}

	// ---- Chrome (rails / action bar / guide) ----

	function buildChrome():Void {
		shell = new MobileEditorShell();

		shell.addLeft('< EXIT', exitEditor);
		shell.railGap(true);
		playBtn = shell.addLeft('PLAY', togglePlayback, true);
		shell.addLeft('TEST', playtest);
		shell.addLeft('SECT ^', function() gotoSectionDelta(-1));
		shell.addLeft('SECT v', function() gotoSectionDelta(1));
		shell.railGap(true);
		shell.addLeft('UNDO', doUndo);
		shell.addLeft('REDO', doRedo);
		shell.addLeft('PASTE', pasteClipboard);

		typeBtn = shell.addRight(typeLabel(), openTypePage);
		snapBtn = shell.addRight('SNAP ${snap.label()}', openSnapPage);
		shell.addRight('EVENTS', openEventsPage);
		shell.railGap(false);
		multiBtn = shell.addRight('MULTI: OFF', toggleMulti);
		shell.addRight('SECTION', openSectionPage);
		shell.addRight('SETTINGS', openSettingsPage);
		shell.railGap(false);
		shell.addRight('? GUIDE', function() openGuide(false));

		shell.setActionBar([
			{label: 'COPY', cb: copySelection},
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
			'DRAG EMPTY    scroll the chart (flick to fling)',
			'PINCH         zoom the grid bigger / smaller',
			'TAP           place a note / select a note',
			'DRAG A NOTE   move it -- drag its tail to set the sustain',
			'HOLD A NOTE   delete it',
			'EVENT LANE    tap to place / edit, hold to remove',
			'MULTI         tap-add notes, then copy / delete / retype',
			'LEFT RAIL     play, TEST, sections, undo/redo, paste',
			'RIGHT RAIL    note type, snap, events, section, settings'
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

	/** Picks the event type placed when tapping the event lane. **/
	function openEventsPage():Void {
		shell.openPage('EVENT TYPE', function(pane:UIScrollPane):Float {
			var w:Float = shell.pageWidth();
			var y:Float = 4;
			for (i in 0...eventNames.length) {
				var name:String = eventNames[i];
				var row:UIButton = new UIButton(name, w, 54, function() {
					placeEvent = name;
					UIToast.show('Tap the event lane to place: $name');
					shell.closeDrawer();
				}, name == placeEvent);
				row.fontSize = 14;
				row.y = y;
				pane.content.addChild(row);
				y += 60;
			}
			return y + 8;
		});
	}

	/** Edits the (first sub-)event of a group: its two values, or delete it. **/
	function openEventEditorPage(group:Array<Dynamic>):Void {
		var subs:Array<Dynamic> = group[1];
		if (subs == null || subs.length == 0)
			return;
		var sub:Array<Dynamic> = subs[0];
		shell.openPage('EVENT', function(pane:UIScrollPane):Float {
			var w:Float = shell.pageWidth();
			var y:Float = 6;
			var nameLbl:UILabel = new UILabel('Event: ${sub[0]}', 15, 0);
			nameLbl.y = y;
			pane.content.addChild(nameLbl);
			y += 36;

			var v1:UITextInput = new UITextInput('Value 1', w, (sub[1] != null) ? Std.string(sub[1]) : '', function(v:String):Void {
				undoStack.snapshotCoalesced(model, 'Event Value');
				sub[1] = v;
				model.markDirty();
			});
			v1.y = y;
			pane.content.addChild(v1);
			y += 54;

			var v2:UITextInput = new UITextInput('Value 2', w, (sub[2] != null) ? Std.string(sub[2]) : '', function(v:String):Void {
				undoStack.snapshotCoalesced(model, 'Event Value');
				sub[2] = v;
				model.markDirty();
			});
			v2.y = y;
			pane.content.addChild(v2);
			y += 62;

			var del:UIButton = new UIButton('DELETE EVENT', w, 56, function() {
				undoStack.snapshot(model, 'Remove Event');
				model.chart.events.remove(group);
				model.markDirty();
				shell.closeDrawer();
			}, false);
			del.danger = true;
			del.y = y;
			pane.content.addChild(del);
			y += 66;
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

	/** Per-section page: which strumline the camera focuses (mustHit side) + the section tools. **/
	function openSectionPage():Void {
		shell.openPage('SECTION', function(pane:UIScrollPane):Float {
			var w:Float = shell.pageWidth();
			var y:Float = 4;
			var sec:Int = model.sectionAt(noteField.viewTime);

			var timingHead:UILabel = new UILabel('Timing (section ${sec + 1})', 14, 0);
			timingHead.y = y;
			pane.content.addChild(timingHead);
			y += 30;

			var secBpm:UIStepper = new UIStepper('BPM', w, model.bpmAt(sec), 1, function(v:Float):Void {
				undoStack.snapshotCoalesced(model, 'BPM');
				model.setBpm(sec, v, EditorPrefs.bpmAdapt);
				noteField.refreshTiming();
			});
			secBpm.min = 1;
			secBpm.max = 1000;
			secBpm.decimals = 2;
			secBpm.y = y;
			pane.content.addChild(secBpm);
			y += 52;

			var secBeats:UIStepper = new UIStepper('Beats/Bar', w, model.beatsAt(sec), 1, function(v:Float):Void {
				undoStack.snapshotCoalesced(model, 'Time Signature');
				model.setBeats(sec, v, EditorPrefs.timeSigAdapt);
				noteField.refreshTiming();
			});
			secBeats.min = 1;
			secBeats.max = 16;
			secBeats.y = y;
			pane.content.addChild(secBeats);
			y += 52;

			var denomLbl:UILabel = new UILabel('Denominator', 12, 0);
			denomLbl.y = y;
			pane.content.addChild(denomLbl);
			y += 24;
			var denoms:Array<Int> = [2, 4, 8, 16];
			var curDenom:Int = model.denominatorAt(sec);
			var dw:Float = (w - 30) / 4;
			for (di in 0...denoms.length) {
				var dv:Int = denoms[di];
				var db:UIButton = new UIButton('/$dv', dw, 46, function() {
					undoStack.snapshot(model, 'Time Signature');
					model.setDenominator(sec, dv, EditorPrefs.timeSigAdapt);
					noteField.refreshTiming();
					shell.closeDrawer();
				}, dv == curDenom);
				db.fontSize = 15;
				db.x = di * (dw + 10);
				db.y = y;
				pane.content.addChild(db);
			}
			y += 58;

			var secSpeed:UIStepper = new UIStepper('Scroll Speed', w, model.scrollSpeedAt(sec), 0.1, function(v:Float):Void {
				undoStack.snapshotCoalesced(model, 'Speed');
				model.setScrollSpeed(sec, v);
			});
			secSpeed.min = 0.1;
			secSpeed.max = 10;
			secSpeed.decimals = 2;
			secSpeed.y = y;
			pane.content.addChild(secSpeed);
			y += 60;

			var head:UILabel = new UILabel('Camera Target (section ${sec + 1})', 14, 0);
			head.y = y;
			pane.content.addChild(head);
			y += 30;

			var cur:Int = model.cameraTargetAt(sec);
			var lines = model.chart.strumLines;
			for (li in 0...lines.length) {
				var idx:Int = li;
				var label:String = lines[li].id + (lines[li].isPlayer ? ' (you)' : '');
				var b:UIButton = new UIButton(label, w, 50, function() {
					undoStack.snapshot(model, 'Camera Target');
					model.setCameraTarget(sec, idx);
					shell.closeDrawer();
				}, li == cur);
				b.fontSize = 15;
				b.y = y;
				pane.content.addChild(b);
				y += 56;
			}
			y += 14;

			var toolsHead:UILabel = new UILabel('Section Tools', 14, 0);
			toolsHead.y = y;
			pane.content.addChild(toolsHead);
			y += 30;

			function tool(label:String, snapshot:String, act:Void->Void, danger:Bool):Void {
				var b:UIButton = new UIButton(label, w, 50, function() {
					undoStack.snapshot(model, snapshot);
					act();
					shell.closeDrawer();
				}, false);
				if (danger)
					b.danger = true;
				b.fontSize = 15;
				b.y = y;
				pane.content.addChild(b);
				y += 56;
			}
			tool('Copy Previous Section', 'Copy Prev', function() model.copyFromSection(sec, -1), false);
			tool('Duet (mirror to other side)', 'Duet', function() model.duetSection(sec), false);
			tool('Mirror Lanes', 'Mirror', function() model.mirrorSection(sec), false);
			tool('Clear Section', 'Clear Section', function() model.clearSection(sec, true, true), true);

			return y + 8;
		});
	}

	function openSettingsPage():Void {
		shell.openPage('SETTINGS', function(pane:UIScrollPane):Float {
			var w:Float = shell.pageWidth();
			var y:Float = 6;

			var bpm:UIStepper = new UIStepper('BPM', w, model.chart.bpm, 1, function(v:Float):Void {
				undoStack.snapshotCoalesced(model, 'BPM');
				model.setBpm(0, v, EditorPrefs.bpmAdapt);
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
				model.setScrollSpeed(0, v);
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

			var wave:UICheckbox = new UICheckbox('Waveform', w, EditorPrefs.waveform, function(checked:Bool):Void {
				EditorPrefs.waveform = checked;
				if (checked && noteField.waveSource == null && audio.loaded)
					noteField.waveSource = audio.waveformSound(0);
				noteField.waveEnabled = checked;
			});
			wave.y = y;
			pane.content.addChild(wave);
			y += 60;

			var metro:UICheckbox = new UICheckbox('Metronome (on playback)', w, EditorPrefs.metronome, function(checked:Bool):Void {
				EditorPrefs.metronome = checked;
			});
			metro.y = y;
			pane.content.addChild(metro);
			y += 60;

			var hits:UICheckbox = new UICheckbox('Hitsounds (on playback)', w, EditorPrefs.hitsounds, function(checked:Bool):Void {
				EditorPrefs.hitsounds = checked;
			});
			hits.y = y;
			pane.content.addChild(hits);
			y += 60;

			// Characters: one row per strumline (name + lane count).
			var charsHead:UILabel = new UILabel('Characters', 14, 0);
			charsHead.y = y;
			pane.content.addChild(charsHead);
			y += 30;
			var lines = model.chart.strumLines;
			for (li in 0...lines.length) {
				var idx:Int = li;
				var line = lines[li];
				var cur:String = (line.characters.length > 0) ? line.characters[0] : '';
				var input:UITextInput = new UITextInput(line.id, w, cur, function(v:String):Void {
					undoStack.snapshotCoalesced(model, 'Character');
					model.setLineCharacter(idx, v);
				});
				input.controlWidth = 200;
				input.y = y;
				pane.content.addChild(input);
				y += 52;
				var kc:UIStepper = new UIStepper('  ${line.id} keys', w, line.keyCount, 1, function(v:Float):Void {
					undoStack.snapshot(model, 'Key Count');
					model.setLineKeyCount(idx, Std.int(v));
					noteField.onModelChanged();
				});
				kc.min = 1;
				kc.max = 9;
				kc.y = y;
				pane.content.addChild(kc);
				y += 54;
			}

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
		if (multiSelect) {
			// Multi mode: build a selection by tapping notes; tapping empty clears it (no placing).
			if (hit != null)
				selection.toggle(hit);
			else
				selection.clear();
			return;
		}
		if (hit != null) {
			selection.setAll([hit]);
			return;
		}
		var lane:Int = noteField.laneAt(wx);
		if (lane < 0)
			return;
		var line:Int = noteField.laneStrumLine(lane);
		if (line < 0) {
			// A valid lane with no strumline is the event lane.
			tapEventLane(wy);
			return;
		}
		var t:Float = model.floorTime(noteField.timeAtY(wy), snap.value);
		if (t < 0)
			t = 0;
		undoStack.snapshot(model, 'Place Note');
		var n:SongNote = model.addNote(t, line, noteField.laneColumn(lane), 0, placeType);
		selection.setAll([n]);
	}

	/** Event lane: tap an existing event to edit it, or place the chosen event type on an empty spot. **/
	function tapEventLane(wy:Float):Void {
		var t:Float = model.floorTime(noteField.timeAtY(wy), snap.value);
		if (t < 0)
			t = 0;
		var unit:Float = model.snapMs(model.sectionAt(t), snap.value);
		var found:Array<Dynamic> = [];
		model.eventsBetween(t - 1, t + unit - 1, found);
		if (found.length > 0) {
			openEventEditorPage(found[0]);
			return;
		}
		if (placeEvent == '') {
			UIToast.show('Pick an event type (EVENTS)');
			return;
		}
		undoStack.snapshot(model, 'Place Event');
		model.addEvent(t, placeEvent, '', '');
		model.eventsBetween(t - 1, t + unit - 1, found);
		if (found.length > 0)
			openEventEditorPage(found[0]);
	}

	function onLongPress(x:Float, y:Float):Void {
		var hit:SongNote = noteField.noteUnder(worldX(x), worldY(y));
		if (hit != null) {
			undoStack.snapshot(model, 'Remove Note');
			selection.remove(hit);
			model.removeNote(hit);
			return;
		}
		// Event lane long-press: remove the event group there.
		var lane:Int = noteField.laneAt(worldX(x));
		if (lane >= 0 && noteField.laneStrumLine(lane) < 0) {
			var t:Float = model.floorTime(noteField.timeAtY(worldY(y)), snap.value);
			if (t < 0)
				t = 0;
			var unit:Float = model.snapMs(model.sectionAt(t), snap.value);
			var found:Array<Dynamic> = [];
			model.eventsBetween(t - 1, t + unit - 1, found);
			if (found.length > 0) {
				undoStack.snapshot(model, 'Remove Event');
				model.chart.events.remove(found[0]);
				model.markDirty();
				UIToast.show('Event removed');
			}
		}
	}

	// ---- Note drag (move / set sustain) ----

	var dragNote:SongNote = null;
	var dragSustain:Bool = false; // grabbed near the tail -> resize the hold instead of moving the note

	/** A press that lands on a note is claimed as a drag: grab the head to move it, the tail to resize. **/
	function onDragStart(x:Float, y:Float):Bool {
		if (audio.playing)
			return false;
		var hit:SongNote = noteField.noteUnder(worldX(x), worldY(y));
		if (hit == null)
			return false;
		if (!selection.notes.contains(hit))
			selection.setAll([hit]);
		dragNote = hit;
		// Time under the finger vs the note's head/tail: closer to the tail (and it has length) => resize.
		var grabT:Float = noteField.timeAtY(worldY(y));
		dragSustain = (hit.length > 0 && Math.abs(grabT - (hit.time + hit.length)) < Math.abs(grabT - hit.time));
		undoStack.snapshot(model, dragSustain ? 'Sustain' : 'Move Note');
		return true;
	}

	function onDragMove(dx:Float, dy:Float, x:Float, y:Float):Void {
		if (dragNote == null)
			return;
		var t:Float = model.floorTime(noteField.timeAtY(worldY(y)), snap.value);
		if (t < 0)
			t = 0;
		if (dragSustain) {
			var len:Float = t - dragNote.time;
			dragNote.length = (len > 0) ? len : 0;
			model.markDirty();
		} else {
			var lane:Int = noteField.laneAt(worldX(x));
			var line:Int = noteField.laneStrumLine(lane);
			if (line < 0)
				model.moveNote(dragNote, t, dragNote.strumLine, dragNote.column);
			else
				model.moveNote(dragNote, t, line, noteField.laneColumn(lane));
		}
	}

	function onDragEnd():Void {
		dragNote = null;
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

	/** Toggles tap-add multi-select: on, tapping notes builds a selection for bulk copy/delete/type. **/
	function toggleMulti():Void {
		multiSelect = !multiSelect;
		multiBtn.label = 'MULTI: ${multiSelect ? "ON" : "OFF"}';
		multiBtn.accent = multiSelect;
	}

	function copySelection():Void {
		if (selection.count == 0)
			return;
		var anchor:Float = selection.notes[0].time;
		for (n in selection.notes)
			if (n.time < anchor)
				anchor = n.time;
		clipboard.copyNotes(selection.notes.copy(), anchor);
		UIToast.show('Copied ${selection.count} notes');
	}

	/** Pastes the clipboard, anchored to the start of the section at the playhead. **/
	function pasteClipboard():Void {
		var at:Float = model.sectionStart(model.sectionAt(noteField.viewTime));
		undoStack.snapshot(model, 'Paste');
		var placed:Int = clipboard.paste(model, at);
		if (placed > 0)
			UIToast.show('Pasted $placed notes');
		else
			UIToast.show('Clipboard is empty');
	}

	// ---- Transport / undo / save ----

	function togglePlayback():Void {
		if (audio.playing)
			audio.pause();
		else {
			nextHitIndex = model.firstNoteIndex(noteField.viewTime + 0.01);
			lastMetroKey = -1;
			audio.play(noteField.viewTime);
		}
		playBtn.label = audio.playing ? 'PAUSE' : 'PLAY';
		playBtn.accent = !audio.playing;
	}

	/** Playback audio feedback: a metronome tick on each beat + a hitsound as the playhead crosses notes. **/
	function tickMetronomeAndHits(t:Float):Void {
		var sec:Int = model.sectionAt(t);
		var spb:Int = backend.Conductor.stepsPerBeat(model.denominatorAt(sec));
		var beatIn:Int = Std.int((noteField.stepsOf(t) - noteField.stepsOf(model.sectionStart(sec))) / spb);
		var key:Int = sec * 10000 + beatIn;
		if (key != lastMetroKey) {
			var wasFresh:Bool = (lastMetroKey == -1);
			lastMetroKey = key;
			if (EditorPrefs.metronome && !wasFresh) {
				var snd = FlxG.sound.play(Paths.sound('Metronome_Tick'), 0.6);
				#if FLX_PITCH
				if (snd != null && beatIn == 0 && EditorPrefs.metroAccent)
					snd.pitch = 1.5;
				#end
			}
		}

		if (!EditorPrefs.hitsounds)
			return;
		var list:Array<SongNote> = model.chart.noteList;
		var lines = model.chart.strumLines;
		var playedP:Bool = false, playedO:Bool = false;
		while (nextHitIndex < list.length && list[nextHitIndex].time <= t) {
			var note:SongNote = list[nextHitIndex];
			nextHitIndex++;
			var isPlayer:Bool = (note.strumLine >= 0 && note.strumLine < lines.length) && lines[note.strumLine].isPlayer;
			if (isPlayer) {
				if (!playedP && EditorPrefs.hitsoundP > 0) {
					FlxG.sound.play(Paths.sound('hitsound'), EditorPrefs.hitsoundP);
					playedP = true;
				}
			} else if (!playedO && EditorPrefs.hitsoundO > 0) {
				FlxG.sound.play(Paths.sound('hitsound'), EditorPrefs.hitsoundO);
				playedO = true;
			}
		}
	}

	/** Launches the edited chart in gameplay (charting mode), like the desktop editor's playtest. **/
	function playtest():Void {
		if (audio.playing)
			audio.pause();
		PlayState.chartingMode = true;
		FlxG.mouse.visible = false;
		backend.StageData.loadDirectory(PlayState.SONG);
		states.LoadingState.loadAndSwitchState(new PlayState());
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
			tickMetronomeAndHits(audio.time);
			if (audio.time >= audio.length)
				togglePlayback();
		}
		// Gestures FIRST: a pan/drag re-times the field and a note drag re-lays it out (releasing every
		// drawable). Running them after updateHot would leave the notes released at render time -- i.e.
		// invisible for the whole drag -- and pan a frame stale.
		gestures.update(elapsed);
		noteField.updateHot(elapsed);

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
