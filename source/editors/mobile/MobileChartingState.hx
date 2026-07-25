package editors.mobile;

import flixel.FlxCamera;
import flixel.FlxG;
import flixel.math.FlxRect;
import backend.SongChart;
import backend.SongChart.SongNote;
import editors.charting.audio.FlxChartAudio;
import editors.charting.audio.IChartAudio;
import editors.charting.data.ChartEditorModel;
import editors.charting.data.ChartFiles;
import editors.charting.data.ClipboardModel;
import editors.charting.data.EditorPrefs;
import editors.charting.data.SelectionModel;
import editors.charting.data.SnapGrid;
import editors.charting.data.UndoStack;
import editors.charting.render.EditorNoteField;
import editors.content.PsychJsonPrinter;
import mobile.backend.SafeArea;
import mobile.input.EditorCanvasGestures;
import objects.notes.NoteDefaults;
import smidr.UIFonts;
import smidr.UILocale;
import smidr.UITheme;
import smidr.widgets.UIButton;
import smidr.widgets.UICheckbox;
import smidr.widgets.UIDropdown;
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
class MobileChartingState extends MobileEditorBase {
	static inline var ZOOM_MIN:Float = 1.0;
	static inline var ZOOM_MAX:Float = 3.2;

	var snap:SnapGrid;
	var model:ChartEditorModel;
	var undoStack:UndoStack;
	var selection:SelectionModel;
	var clipboard:ClipboardModel;
	// `fileDialog` is provided by MobileEditorBase (native open/save; destroyed there).
	var audio:IChartAudio;
	var noteField:EditorNoteField;

	// `shell` + `gestures` are provided by MobileEditorBase; this editor uses its own `gridCam` for the grid.
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
			chart = editors.ChartingState.makeBlankChart();
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
		noteField.typeIndexOf = function(t:String):Int return noteTypes.indexOf(t);
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

		model.onChanged = function():Void {
			markDirty();
			noteField.onModelChanged();
		};
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

	/** Same list, same ORDER as the desktop editor: badge numbers must mean the same type in both. **/
	function buildNoteTypes():Void {
		noteTypes = [];
		#if MODS_ALLOWED
		var exts:Array<String> = ['.txt'];
		#if LUA_ALLOWED
		exts.push('.lua');
		#end
		#if HSCRIPT_ALLOWED
		exts.push('.hx');
		#end
		noteTypes = editors.ChartingState.listEditorFiles('custom_notetypes/', exts);
		#end
		for (id => t in NoteDefaults.defaultNoteTypes)
			if (!noteTypes.contains(t))
				noteTypes.insert(id, t);
	}

	function buildEvents():Void {
		eventNames = [];
		for (e in legacy.editors.ChartingState.defaultEvents)
			if (e.length > 0 && e[0].length > 0 && !eventNames.contains(e[0]))
				eventNames.push(e[0]);
		// Custom mod events (custom_events/*.txt), same source the desktop editor scans -- otherwise
		// the picker only ever lists the built-ins.
		#if MODS_ALLOWED
		for (name in scanCustomEventNames())
			if (name.length > 0 && !eventNames.contains(name))
				eventNames.push(name);
		#end
		placeEvent = (eventNames.length > 0) ? eventNames[0] : '';
	}

	#if MODS_ALLOWED
	/** Names of custom event definitions (`custom_events/<name>.txt`) across the shared path and enabled mods. **/
	function scanCustomEventNames():Array<String> {
		var out:Array<String> = [];
		for (dir in Mods.directoriesWithFile(Paths.getSharedPath(), 'custom_events/')) {
			for (file in sys.FileSystem.readDirectory(dir)) {
				var path:String = haxe.io.Path.join([dir, file]);
				if (!sys.FileSystem.isDirectory(path) && file.endsWith('.txt') && !file.startsWith('readme.')) {
					var name:String = file.substr(0, file.length - 4);
					if (name.length > 0 && !out.contains(name))
						out.push(name);
				}
			}
		}
		return out;
	}
	#end

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
		shell.railGap(true);
		shell.addLeft('FILE', openFilePage, true);

		typeBtn = shell.addRight(typeLabel(), openTypePage);
		snapBtn = shell.addRight(snapLabel(), openSnapPage);
		shell.addRight('EVENTS', openEventsPage);
		shell.railGap(false);
		multiBtn = shell.addRight('MULTI: OFF', toggleMulti);
		shell.addRight('STRUMS', openStrumlinesPage);
		shell.addRight('SECTION', openSectionPage);
		shell.addRight('SETTINGS', openSettingsPage);
		shell.railGap(false);
		shell.addRight('? GUIDE', function() openGuide(false));

		shell.setActionBar([
			{label: 'COPY', cb: copySelection},
			{label: 'DELETE', cb: deleteSelection, danger: true},
			{label: 'SUS -', cb: function() bumpSelectedSustains(-1)},
			{label: 'SUS +', cb: function() bumpSelectedSustains(1)},
			{label: 'TYPE', cb: applyTypeToSelection},
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
			'DRAG A NOTE   top half moves it -- bottom half or its hold bar stretches the sustain',
			'HOLD A NOTE   delete it',
			'EVENT LANE    tap to place / edit, hold to remove',
			'MULTI         tap-add notes, then copy / delete / retype',
			'LEFT RAIL     play, TEST, sections, undo/redo, paste, file',
			'RIGHT RAIL    note type, snap, events, strumlines, section, settings'
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

	/** Scanned character jsons, sorted (empty when MODS_ALLOWED is off). Mirrors the desktop picker source. **/
	function characterList():Array<String> {
		#if MODS_ALLOWED
		var list:Array<String> = editors.ChartingState.listEditorFiles('characters/', ['.json']);
		list.sort(function(a:String, b:String):Int return (a < b) ? -1 : (a > b ? 1 : 0));
		return list;
		#else
		return [];
		#end
	}

	/** Scanned stage jsons, sorted (empty when MODS_ALLOWED is off). **/
	function stageList():Array<String> {
		#if MODS_ALLOWED
		var list:Array<String> = editors.ChartingState.listEditorFiles('stages/', ['.json']);
		list.sort(function(a:String, b:String):Int return (a < b) ? -1 : (a > b ? 1 : 0));
		return list;
		#else
		return [];
		#end
	}

	/**
	 * Full strumline editor: one block per strumline with a character picker, role, key count and
	 * gameplay visibility, plus reorder / remove and an add button. Mirrors the desktop strumline
	 * properties modal, so characters are set the same way in both editors.
	 */
	function openStrumlinesPage():Void {
		shell.openPage('STRUMLINES', function(pane:UIScrollPane):Float {
			var w:Float = shell.pageWidth();
			var y:Float = 4;
			var lines = model.chart.strumLines;
			for (li in 0...lines.length) {
				var idx:Int = li;
				var line = lines[li];

				var head:UILabel = new UILabel('Strumline ${li + 1}: ${line.id}', 15, 0);
				head.y = y;
				pane.content.addChild(head);
				y += 30;

				var curChar:String = (line.characters.length > 0) ? line.characters[0] : '';
				var chars:Array<String> = characterList();
				if (curChar != '' && chars.indexOf(curChar) < 0)
					chars.unshift(curChar);
				if (chars.length == 0)
					chars.push(curChar);
				var charDrop:UIDropdown = new UIDropdown('Character', w, function(_:Int, value:String):Void {
					undoStack.snapshot(model, 'Character');
					model.setLineCharacter(idx, value);
				});
				charDrop.fontSize = 15;
				charDrop.controlWidth = 260;
				charDrop.setItems(chars);
				charDrop.select(Std.int(Math.max(0, chars.indexOf(curChar))));
				charDrop.y = y;
				pane.content.addChild(charDrop);
				y += 44;

				var roleDrop:UIDropdown = new UIDropdown('Role', w, function(index:Int, _:String):Void {
					undoStack.snapshot(model, 'Strumline Role');
					model.setLineRole(idx, (index == 0) ? 1 : ((index == 1) ? 0 : 2));
				});
				roleDrop.fontSize = 15;
				roleDrop.controlWidth = 220;
				roleDrop.setItems(['Player', 'CPU (Opponent)', 'Extra']);
				roleDrop.select(line.type == 1 ? 0 : (line.type == 0 ? 1 : 2));
				roleDrop.y = y;
				pane.content.addChild(roleDrop);
				y += 44;

				var kc:UIStepper = new UIStepper('Key Count', w, line.keyCount, 1, function(v:Float):Void {
					undoStack.snapshot(model, 'Key Count');
					var removed:Int = model.setLineKeyCount(idx, Std.int(v));
					noteField.onModelChanged();
					refitGrid();
					if (removed > 0)
						UIToast.show('$removed out-of-range notes removed');
				});
				kc.min = 1;
				kc.max = 9;
				kc.y = y;
				pane.content.addChild(kc);
				y += 54;

				var vis:UICheckbox = new UICheckbox('Render arrows in gameplay', w, line.visible, function(checked:Bool):Void {
					if (checked && !line.visible && model.visibleLineCount() >= editors.ChartingState.MAX_VISIBLE_LINES) {
						UIToast.show('At most ${editors.ChartingState.MAX_VISIBLE_LINES} strumlines can be visible');
						openStrumlinesPage();
						return;
					}
					undoStack.snapshot(model, 'Lane Visibility');
					model.setLineVisible(idx, checked);
					noteField.onModelChanged();
					refitGrid();
				});
				vis.y = y;
				pane.content.addChild(vis);
				y += 58;

				var third:Float = (w - 20) / 3;
				var up:UIButton = new UIButton('UP', third, 50, function() {
					if (idx > 0) {
						undoStack.snapshot(model, 'Reorder Strumlines');
						model.swapStrumLines(idx, idx - 1);
						noteField.onModelChanged();
						openStrumlinesPage();
					}
				});
				up.fontSize = 14;
				up.y = y;
				pane.content.addChild(up);
				var down:UIButton = new UIButton('DOWN', third, 50, function() {
					if (idx < model.chart.strumLines.length - 1) {
						undoStack.snapshot(model, 'Reorder Strumlines');
						model.swapStrumLines(idx, idx + 1);
						noteField.onModelChanged();
						openStrumlinesPage();
					}
				});
				down.fontSize = 14;
				down.x = third + 10;
				down.y = y;
				pane.content.addChild(down);
				var rem:UIButton = new UIButton('REMOVE', third, 50, function() {
					if (model.chart.strumLines.length <= 1) {
						UIToast.show("Can't remove the last strumline");
						return;
					}
					undoStack.snapshot(model, 'Remove Strumline');
					selection.clear();
					model.removeStrumLine(idx);
					noteField.onModelChanged();
					refitGrid();
					openStrumlinesPage();
				}, false);
				rem.danger = true;
				rem.fontSize = 14;
				rem.x = third * 2 + 20;
				rem.y = y;
				pane.content.addChild(rem);
				y += 88; // breathing room before the next strumline block
			}

			var add:UIButton = new UIButton('+ ADD STRUMLINE', w, 60, function() {
				undoStack.snapshot(model, 'Add Strumline');
				model.addStrumLine('extra${model.chart.strumLines.length}', 'bf', model.chart.keyCount);
				noteField.onModelChanged();
				refitGrid();
				openStrumlinesPage();
			}, true);
			add.fontSize = 16;
			add.y = y;
			pane.content.addChild(add);
			y += 70;

			return y + 8;
		});
	}

	/** Re-fits and re-clamps the magnifying grid camera after the lane layout changes. **/
	function refitGrid():Void {
		gridCam.zoom = fitZoom();
		clampScrollX();
		updateStatus();
	}

	/** The division matching one drawn grid row (free grid snapping quantizes to it). **/
	function gridSnapDiv():Int {
		var div:Int = Math.round(16 * ((noteField != null) ? noteField.zoom : 1));
		return (div < 1) ? 1 : div;
	}

	/** The division every placement/drag op uses: the drawn grid row, or the fixed snap when picked. **/
	inline function activeSnap():Int {
		return EditorPrefs.gridSnap ? gridSnapDiv() : snap.value;
	}

	inline function snapLabel():String {
		return EditorPrefs.gridSnap ? 'SNAP GRID' : 'SNAP ${snap.label()}';
	}

	function updateSnapButton():Void {
		if (snapBtn != null)
			snapBtn.label = snapLabel();
	}

	function openSnapPage():Void {
		shell.openPage('SNAP', function(pane:UIScrollPane):Float {
			var w:Float = shell.pageWidth();
			var chipW:Float = (w - 20) / 3;
			var x:Float = 0;
			var y:Float = 4;
			var col:Int = 0;
			var gridChip:UIButton = new UIButton('GRID', w, 56, function() {
				EditorPrefs.gridSnap = true;
				updateSnapButton();
				shell.closeDrawer();
			}, EditorPrefs.gridSnap);
			gridChip.fontSize = 16;
			gridChip.x = 0;
			gridChip.y = y;
			pane.content.addChild(gridChip);
			y += 68;
			for (i in 0...SnapGrid.SNAPS.length) {
				var idx:Int = i;
				var chip:UIButton = new UIButton('1/${SnapGrid.SNAPS[i]}', chipW, 56, function() {
					snap.select(idx);
					EditorPrefs.snapIndex = snap.index;
					EditorPrefs.gridSnap = false;
					updateSnapButton();
					shell.closeDrawer();
				}, !EditorPrefs.gridSnap && i == snap.index);
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
				var db:UIButton = new UIButton('/$dv', dw, 52, function() {
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
			y += 62;

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
				var b:UIButton = new UIButton(label, w, 54, function() {
					undoStack.snapshot(model, 'Camera Target');
					model.setCameraTarget(sec, idx);
					shell.closeDrawer();
				}, li == cur);
				b.fontSize = 15;
				b.y = y;
				pane.content.addChild(b);
				y += 60;
			}
			y += 14;

			var toolsHead:UILabel = new UILabel('Section Tools', 14, 0);
			toolsHead.y = y;
			pane.content.addChild(toolsHead);
			y += 30;

			var selBtn:UIButton = new UIButton('Select Section Notes', w, 54, function() {
				selectCurrentSection();
				shell.closeDrawer();
			}, true);
			selBtn.fontSize = 15;
			selBtn.y = y;
			pane.content.addChild(selBtn);
			y += 60;

			function tool(label:String, snapshot:String, act:Void->Void, danger:Bool):Void {
				var b:UIButton = new UIButton(label, w, 54, function() {
					undoStack.snapshot(model, snapshot);
					act();
					shell.closeDrawer();
				}, false);
				if (danger)
					b.danger = true;
				b.fontSize = 15;
				b.y = y;
				pane.content.addChild(b);
				y += 60;
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

			var songHead:UILabel = new UILabel('Song', 14, 0);
			songHead.y = y;
			pane.content.addChild(songHead);
			y += 30;

			var songName:UITextInput = new UITextInput('Song Name', w, model.chart.song, function(v:String):Void {
				undoStack.snapshotCoalesced(model, 'Song Name');
				model.chart.song = v;
				model.markDirty();
			});
			songName.controlWidth = 240;
			songName.y = y;
			pane.content.addChild(songName);
			y += 54;

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

			var vel:UIStepper = new UIStepper('Scroll Velocity', w, model.velocityAt(0), 0.1, function(v:Float):Void {
				undoStack.snapshotCoalesced(model, 'Scroll Velocity');
				model.setVelocity(0, v);
			});
			vel.min = -10;
			vel.max = 10;
			vel.decimals = 2;
			vel.y = y;
			pane.content.addChild(vel);
			y += 52;

			var offset:UIStepper = new UIStepper('Offset (ms)', w, model.chart.offset, 1, function(v:Float):Void {
				undoStack.snapshotCoalesced(model, 'Offset');
				model.chart.offset = v;
				model.markDirty();
			});
			offset.min = -5000;
			offset.max = 5000;
			offset.y = y;
			pane.content.addChild(offset);
			y += 52;

			var voices:UICheckbox = new UICheckbox('Needs Voices', w, model.chart.needsVoices, function(checked:Bool):Void {
				undoStack.snapshot(model, 'Needs Voices');
				model.chart.needsVoices = checked;
				model.markDirty();
			});
			voices.y = y;
			pane.content.addChild(voices);
			y += 60;

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

			var rate:UIStepper = new UIStepper('Playback Rate', w, playRate, 0.25, function(v:Float):Void {
				playRate = v;
				audio.setRate(playRate);
			});
			rate.min = 0.25;
			rate.max = 2;
			rate.y = y;
			pane.content.addChild(rate);
			y += 60;

			var mInst:UICheckbox = new UICheckbox('Mute Instrumental', w, muteInst, function(checked:Bool):Void {
				muteInst = checked;
				applyVolumes();
			});
			mInst.y = y;
			pane.content.addChild(mInst);
			y += 60;

			var mVox:UICheckbox = new UICheckbox('Mute Vocals', w, muteVox, function(checked:Bool):Void {
				muteVox = checked;
				applyVolumes();
			});
			mVox.y = y;
			pane.content.addChild(mVox);
			y += 60;

			// Characters & stage: strumlines/characters live on their own page (matches desktop);
			// here we keep the song-level stage, GF and game-over character pickers.
			var charsHead:UILabel = new UILabel('Characters & Stage', 14, 0);
			charsHead.y = y;
			pane.content.addChild(charsHead);
			y += 30;

			var strumBtn:UIButton = new UIButton('EDIT STRUMLINES / CHARACTERS', w, 56, function() {
				openStrumlinesPage();
			});
			strumBtn.fontSize = 15;
			strumBtn.y = y;
			pane.content.addChild(strumBtn);
			y += 64;

			var stages:Array<String> = stageList();
			var curStage:String = (model.chart.stage != null) ? model.chart.stage : '';
			if (stages.length > 0) {
				if (curStage != '' && stages.indexOf(curStage) < 0)
					stages.unshift(curStage);
				var stageDrop:UIDropdown = new UIDropdown('Stage', w, function(_:Int, value:String):Void {
					undoStack.snapshot(model, 'Stage');
					model.chart.stage = value;
					model.markDirty();
				});
				stageDrop.fontSize = 15;
				stageDrop.controlWidth = 240;
				stageDrop.setItems(stages);
				stageDrop.select(Std.int(Math.max(0, stages.indexOf(curStage))));
				stageDrop.y = y;
				pane.content.addChild(stageDrop);
				y += 44;
			} else {
				var stageInput:UITextInput = new UITextInput('Stage', w, curStage, function(v:String):Void {
					undoStack.snapshotCoalesced(model, 'Stage');
					model.chart.stage = v;
					model.markDirty();
				});
				stageInput.controlWidth = 240;
				stageInput.y = y;
				pane.content.addChild(stageInput);
				y += 54;
			}

			// The gf character lives on the gf STRUMLINE (psych_v2 stores it nowhere else); this is the
			// shortcut for it, the strumlines page edits every line's character.
			var gfLine:backend.SongChart.StrumLineData = model.chart.gfLine();
			var gfInput:UITextInput = new UITextInput('GF Version', w, backend.SongChart.lineCharacter(gfLine, ''), function(v:String):Void {
				if (gfLine == null)
					return;
				undoStack.snapshotCoalesced(model, 'GF Version');
				model.setLineCharacter(gfLine.index, v);
			});
			gfInput.controlWidth = 240;
			gfInput.y = y;
			pane.content.addChild(gfInput);
			y += 54;

			var goInput:UITextInput = new UITextInput('Game Over Char', w, (model.chart.gameOverChar != null) ? model.chart.gameOverChar : '', function(v:String):Void {
				undoStack.snapshotCoalesced(model, 'Game Over Char');
				model.chart.gameOverChar = v;
				model.markDirty();
			});
			goInput.controlWidth = 240;
			goInput.y = y;
			pane.content.addChild(goInput);
			y += 58;

			var reload:UIButton = new UIButton('RELOAD AUDIO', w, 56, function() {
				backend.Song.loadedSongName = model.chart.songKey();
				audio.load(backend.Song.loadedSongName, model.chart.needsVoices);
				applyVolumes();
				audio.setRate(playRate);
				noteField.maxTime = audio.loaded ? audio.length : -1;
				if (audio.loaded && noteField.waveSource == null)
					noteField.waveSource = audio.waveformSound(0);
				UIToast.show(audio.loaded ? 'Audio loaded' : 'No audio found in "${backend.Song.loadedSongName}"');
			});
			reload.fontSize = 15;
			reload.y = y;
			pane.content.addChild(reload);
			y += 70;

			return y + 8;
		});
	}

	/** Save / open / new: everything that touches the chart file, off the rail's FILE button. **/
	function openFilePage():Void {
		shell.openPage('FILE', function(pane:UIScrollPane):Float {
			var w:Float = shell.pageWidth();
			var y:Float = 6;

			var state:UILabel = new UILabel(unsavedProgress ? 'Unsaved changes' : 'All changes saved', 14, unsavedProgress ? 0 : 2);
			state.y = y;
			pane.content.addChild(state);
			y += 34;

			var save:UIButton = new UIButton('SAVE CHART', w, 60, saveChart, true);
			save.fontSize = 16;
			save.y = y;
			pane.content.addChild(save);
			y += 70;

			var saveAs:UIButton = new UIButton('SAVE AS... (file browser)', w, 60, saveChartAs);
			saveAs.fontSize = 16;
			saveAs.y = y;
			pane.content.addChild(saveAs);
			y += 70;

			var openBtn:UIButton = new UIButton('OPEN CHART... (file browser)', w, 60, function() confirmDiscard('Open another chart', openChart));
			openBtn.fontSize = 16;
			openBtn.y = y;
			pane.content.addChild(openBtn);
			y += 70;

			var fresh:UIButton = new UIButton('NEW CHART (clears everything)', w, 60, function() confirmDiscard('Start a new chart', newChart));
			fresh.danger = true;
			fresh.fontSize = 16;
			fresh.y = y;
			pane.content.addChild(fresh);
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
		var usable:Float = FlxG.width - SafeArea.left - SafeArea.right - MobileEditorShell.RAIL_W * 2 - 30;
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
			tapEventLane(wx, wy);
			return;
		}
		var t:Float = model.floorTime(noteField.timeAtY(wy), activeSnap());
		if (t < 0)
			t = 0;
		undoStack.snapshot(model, 'Place Note');
		var n:SongNote = model.addNote(t, line, noteField.laneColumn(lane), 0, placeType);
		selection.setAll([n]);
	}

	/** Event lane: tap an existing event to edit it, or place the chosen event type on an empty spot. **/
	function tapEventLane(wx:Float, wy:Float):Void {
		// existing events are picked where their mark is drawn, so off-grid ones stay tappable
		var hit:Array<Dynamic> = noteField.eventUnder(wx, wy);
		if (hit != null) {
			openEventEditorPage(hit);
			return;
		}
		if (placeEvent == '') {
			UIToast.show('Pick an event type (EVENTS)');
			return;
		}
		var t:Float = model.floorTime(noteField.timeAtY(wy), activeSnap());
		if (t < 0)
			t = 0;
		undoStack.snapshot(model, 'Place Event');
		model.addEvent(t, placeEvent, '', '');
		var found:Array<Dynamic> = [];
		model.eventsBetween(t - 1, t + 1, found);
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
			var found:Array<Dynamic> = noteField.eventUnder(worldX(x), worldY(y));
			if (found != null) {
				undoStack.snapshot(model, 'Remove Event');
				model.chart.events.remove(found);
				model.markDirty();
				UIToast.show('Event removed');
			}
		}
	}

	// ---- Playback audio ----

	var playRate:Float = 1;
	var muteInst:Bool = false;
	var muteVox:Bool = false;

	function applyVolumes():Void {
		audio.setVolumes(muteInst ? 0 : 1, muteVox ? 0 : 1, muteVox ? 0 : 1);
	}

	// ---- Note drag (move / set sustain) ----

	var dragNote:SongNote = null;
	var dragSustain:Bool = false; // grabbed near the tail -> resize the hold instead of moving the note

	/**
	 * A press that lands on a note is claimed as a drag. The grip decides the mode: the tail-side
	 * half of the head (or anywhere on the hold bar) stretches the sustain, the rest moves the note.
	 */
	function onDragStart(x:Float, y:Float):Bool {
		if (audio.playing)
			return false;
		var hit:SongNote = noteField.grabUnder(worldX(x), worldY(y));
		if (hit == null)
			return false;
		if (!selection.notes.contains(hit))
			selection.setAll([hit]);
		dragNote = hit;
		dragSustain = noteField.grabbedTail;
		undoStack.snapshot(model, dragSustain ? 'Sustain' : 'Move Note');
		return true;
	}

	function onDragMove(dx:Float, dy:Float, x:Float, y:Float):Void {
		if (dragNote == null)
			return;
		var t:Float = model.floorTime(noteField.timeAtY(worldY(y)), activeSnap());
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

	/** Selects every note in the section under the playhead, for bulk action-bar edits. **/
	function selectCurrentSection():Void {
		var sec:Int = model.sectionAt(noteField.viewTime);
		var start:Float = model.sectionStart(sec);
		var end:Float = model.sectionEnd(sec);
		var picked:Array<SongNote> = [];
		var list:Array<SongNote> = model.chart.noteList;
		var i:Int = model.firstNoteIndex(start);
		var n:Int = list.length;
		while (i < n) {
			var note:SongNote = list[i];
			if (note.time >= end)
				break;
			picked.push(note);
			i++;
		}
		selection.setAll(picked);
		refreshActionBar();
		UIToast.show(picked.length > 0 ? 'Selected ${picked.length} notes' : 'Section is empty');
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
			var unit:Float = model.snapMs(model.sectionAt(n.time), activeSnap());
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
	/**
	 * Asks for the new song's identity, grid and strumlines, then blanks the chart onto it (the drawer-page
	 * form of the desktop New Chart dialog).
	 */
	function newChart():Void {
		var opts:editors.ChartingState.NewChartOptions = editors.ChartingState.defaultNewOptions();
		if (Difficulty.list.length < 1)
			Difficulty.resetList();
		var diffIndex:Int = Std.int(Math.min(Math.max(0, PlayState.storyDifficulty), Difficulty.list.length - 1));
		var folderEdited:Bool = false;

		var build:Void->Void = null;
		build = function():Void {
			shell.openPage('NEW CHART', function(pane:UIScrollPane):Float {
				var w:Float = shell.pageWidth();
				var y:Float = 4;

				var folderInput:UITextInput = new UITextInput('Folder', w, opts.folder, function(v:String):Void {
					folderEdited = true;
					opts.folder = Paths.formatToSongPath(v);
				});
				var nameInput:UITextInput = new UITextInput('Song Name', w, opts.song, function(v:String):Void {
					opts.song = v;
					if (!folderEdited) {
						opts.folder = Paths.formatToSongPath(v);
						folderInput.text = opts.folder;
					}
				});
				nameInput.controlWidth = 260;
				nameInput.y = y;
				pane.content.addChild(nameInput);
				y += 54;

				folderInput.controlWidth = 260;
				folderInput.y = y;
				pane.content.addChild(folderInput);
				y += 54;

				var diffDrop:UIDropdown = new UIDropdown('Difficulty', w, function(i:Int, _:String):Void diffIndex = i);
				diffDrop.fontSize = 15;
				diffDrop.controlWidth = 220;
				diffDrop.setItems(Difficulty.list.copy());
				diffDrop.select(diffIndex);
				diffDrop.y = y;
				pane.content.addChild(diffDrop);
				y += 44;

				var keyStepper:UIStepper = new UIStepper('Key Count', w, opts.keyCount, 1, function(v:Float):Void opts.keyCount = Std.int(v));
				keyStepper.min = 1;
				keyStepper.max = 9;
				keyStepper.y = y;
				pane.content.addChild(keyStepper);
				y += 54;

				var bpmStepper:UIStepper = new UIStepper('BPM', w, opts.bpm, 1, function(v:Float):Void opts.bpm = v);
				bpmStepper.min = 1;
				bpmStepper.max = 999;
				bpmStepper.decimals = 2;
				bpmStepper.y = y;
				pane.content.addChild(bpmStepper);
				y += 54;

				// Time signature reads as one row: "Time Signature: [beats] / [note value]".
				var ctrl:Float = 104;
				var beatsStepper:UIStepper = new UIStepper('Time Signature', w - ctrl - 22, opts.beats, 1, function(v:Float):Void opts.beats = v);
				beatsStepper.min = 1;
				beatsStepper.max = 32;
				beatsStepper.controlWidth = ctrl;
				beatsStepper.y = y;
				pane.content.addChild(beatsStepper);

				var slash:UILabel = new UILabel('/', 15, 1);
				slash.x = w - ctrl - 14;
				slash.y = y + 6;
				pane.content.addChild(slash);

				var denomStepper:UIStepper = new UIStepper('', ctrl, opts.denominator, 1, function(v:Float):Void opts.denominator = Std.int(v));
				denomStepper.min = 1;
				denomStepper.max = 16;
				denomStepper.controlWidth = ctrl;
				denomStepper.x = w - ctrl;
				denomStepper.y = y;
				pane.content.addChild(denomStepper);
				y += 62;

				var header:UILabel = new UILabel('Strumlines', 15, 0);
				header.y = y;
				pane.content.addChild(header);
				y += 30;

				var chars:Array<String> = characterList();
				for (i in 0...opts.lines.length) {
					var line = opts.lines[i];
					if (line.character != null && line.character.length > 0 && chars.indexOf(line.character) < 0)
						chars.unshift(line.character);

					var idInput:UITextInput = new UITextInput('ID', w, line.id, function(v:String):Void line.id = v);
					idInput.controlWidth = 200;
					idInput.y = y;
					pane.content.addChild(idInput);
					y += 54;

					var charDrop:UIDropdown = new UIDropdown('Character', w, function(_:Int, value:String):Void line.character = value);
					charDrop.fontSize = 15;
					charDrop.controlWidth = 260;
					charDrop.setItems(chars.copy());
					charDrop.select(Std.int(Math.max(0, chars.indexOf(line.character))));
					charDrop.y = y;
					pane.content.addChild(charDrop);
					y += 44;

					var roleDrop:UIDropdown = new UIDropdown('Role', w, function(index:Int, _:String):Void line.type = (index == 0) ? 1 : ((index == 1) ? 0 : 2));
					roleDrop.fontSize = 15;
					roleDrop.controlWidth = 220;
					roleDrop.setItems(['Player', 'CPU (Opponent)', 'Extra']);
					roleDrop.select(line.type == 1 ? 0 : (line.type == 0 ? 1 : 2));
					roleDrop.y = y;
					pane.content.addChild(roleDrop);
					y += 44;

					var vis:UICheckbox = new UICheckbox('Render arrows in gameplay', w, line.visible, function(checked:Bool):Void line.visible = checked);
					vis.y = y;
					pane.content.addChild(vis);
					y += 46;

					var idx:Int = i;
					var del:UIButton = new UIButton('REMOVE STRUMLINE', w, 48, function() {
						opts.lines.splice(idx, 1);
						build();
					});
					del.fontSize = 14;
					del.y = y;
					pane.content.addChild(del);
					y += 62;
				}

				var add:UIButton = new UIButton('ADD STRUMLINE', w, 52, function() {
					opts.lines.push({id: 'line${opts.lines.length}', character: 'bf', type: 2, visible: true});
					build();
				});
				add.y = y;
				pane.content.addChild(add);
				y += 64;

				var create:UIButton = new UIButton('CREATE CHART', w, 56, function() {
					shell.closeDrawer();
					PlayState.storyDifficulty = diffIndex;
					backend.Song.chartPath = null;
					backend.Song.loadedSongName = opts.folder;
					adoptChart(editors.ChartingState.makeBlankChart(opts));
					UIToast.show('New chart: ${opts.song}');
				});
				create.y = y;
				pane.content.addChild(create);
				return y + 68;
			});
		};
		build();
	}

	/** Swaps the whole editor onto a different chart (new/open), reloading its song's audio. **/
	function adoptChart(chart:SongChart):Void {
		if (audio.playing)
			audio.pause();
		undoStack.reset();
		selection.clear();
		PlayState.SONG = chart;
		// A package that keeps its events in their own file: edit them here, write them back there.
		eventsSidecar = ChartFiles.adoptEvents(chart, backend.Song.chartPath, Difficulty.getString(false));
		model.load(chart);
		model.ensureSectionCount(16);
		audio.load(backend.Song.loadedSongName, chart.needsVoices);
		audio.setVolumes(EditorPrefs.instVol, EditorPrefs.mainVol, EditorPrefs.oppVol);
		audio.setRate(playRate);
		if (audio.loaded) {
			var guard:Int = 0;
			while (model.endTime < audio.length && guard++ < 4000)
				model.ensureSectionCount(model.sectionCount() + 1);
			noteField.waveSource = audio.waveformSound(0);
		}
		noteField.maxTime = audio.loaded ? audio.length : -1;
		noteField.onModelChanged();
		noteField.setViewTime(0);
		refreshActionBar();
		updateStatus();
		unsavedProgress = false;
		shell.closeDrawer();
	}

	/** Opens a chart through the system file picker (any browsable location). **/
	function openChart():Void {
		fileDialog.open('chart.json', 'Open a chart', null, function():Void {
			try {
				var loaded:SongChart = backend.Song.parseJSON(fileDialog.data, fileDialog.path);
				if (loaded == null || loaded.sections.length == 0) {
					UIToast.show('Not a valid chart file');
					return;
				}
				// A picked document has no filesystem path; the rail SAVE keeps writing charts/<song>.json.
				backend.Song.chartPath = null;
				if (loaded.folder == null || loaded.folder.length == 0)
					loaded.folder = backend.SongPaths.packageOfPath(fileDialog.path);
				backend.Song.loadedSongName = loaded.songKey();
				adoptChart(loaded);
				UIToast.show('Loaded: ${loaded.song}');
			} catch (e:Dynamic)
				UIToast.show('Error loading chart: $e');
		});
	}

	/** Saves the chart through the system file picker (Downloads, Drive, anywhere browsable). **/
	function saveChartAs():Void {
		var data:String = ChartFiles.chartJson(model.chart, eventsSidecar != null);
		fileDialog.save('chart-${Paths.formatToSongPath(Difficulty.getString(false))}.json', data, function():Void {
			unsavedProgress = false;
			UIToast.show('Saved: ${fileDialog.path}');
		}, null, function():Void UIToast.show('Save failed'));
	}

	function playtest():Void {
		if (audio.playing)
			audio.pause();
		PlayState.chartingMode = true;
		PlayState.chartingFromMobile = true;
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

	/** The package's events file when it keeps them out of the chart, folded in on load. Null = in the chart. **/
	var eventsSidecar:String = null;

	function saveChart():Void {
		#if sys
		try {
			var data:String = ChartFiles.chartJson(model.chart, eventsSidecar != null);
			// Written as a song package (`charts/<folder>/chart-<difficulty>.json`) so the result can be
			// dropped straight into a mod's `songs/` beside the audio.
			var name:String = model.chart.songKey();
			if (!sys.FileSystem.exists('charts'))
				sys.FileSystem.createDirectory('charts');
			if (!sys.FileSystem.exists('charts/$name'))
				sys.FileSystem.createDirectory('charts/$name');
			var path:String = 'charts/$name/chart-${Paths.formatToSongPath(Difficulty.getString(false))}.json';
			sys.io.File.saveContent(path, data);
			if (eventsSidecar != null) {
				eventsSidecar = ChartFiles.beside(eventsSidecar, path);
				ChartFiles.writeEvents(eventsSidecar, model.chart);
			}
			unsavedProgress = false;
			UIToast.show('Saved to $path');
		} catch (e:Dynamic) {
			UIToast.show('Save failed: ${Std.string(e)}');
		}
		#end
	}

	// The unsaved-changes exit prompt lives in MobileEditorBase; it saves through this hook.
	override function saveDocument(?onSaved:Void->Void):Void {
		saveChart();
		if (onSaved != null)
			onSaved();
	}

	// Android back: dismiss a live selection before the base exits (prompt/guide/drawer are handled by the base).
	override function onBackButtonExtra():Bool {
		if (selection.count > 0) {
			selection.clear();
			return true;
		}
		return false;
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

		// The Android back button (guide -> drawer -> selection -> exit) is routed by MobileEditorBase.update.
		super.update(elapsed);
	}

	override function destroy():Void {
		// fileDialog.destroy() is handled by MobileEditorBase.destroy.
		if (gestures != null)
			gestures.enabled = false;
		if (audio != null)
			audio.destroy();
		if (noteField != null)
			noteField.dispose();
		if (gridCam != null)
			FlxG.cameras.remove(gridCam);
		// shell.dispose() is handled by MobileEditorBase.destroy.
		super.destroy();
	}
}
