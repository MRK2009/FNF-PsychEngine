package editors.mobile;

import flixel.FlxCamera;
import flixel.FlxG;
import flixel.math.FlxRect;
import editors.content.FileDialogHandler;
import mobile.input.EditorCanvasGestures;
import smidr.overlays.UIToast;

/**
 * Shared base for the touch-native editors. Owns the `MobileEditorShell` chrome, an optional
 * gesture-driven preview camera, the exit-to-menu flow, and the Android back-button routing
 * (prompt -> guide -> drawer -> subclass hook -> exit). Subclasses build their content (canvas + rails + drawer
 * pages) in `create()` and override the hooks below; `update`/`destroy` chain up for the common bits.
 *
 * Pure-form editors leave the canvas fields null; canvas editors call `setupCanvas()` for a full-screen
 * magnifying camera + a `EditorCanvasGestures` (they still `gestures.update()` themselves so they control
 * ordering vs their own per-frame work).
 */
class MobileEditorBase extends MusicBeatState {
	var shell:MobileEditorShell;

	/** The magnifying camera a canvas editor draws its preview on (null for pure-form editors). **/
	var previewCam:FlxCamera = null;

	/** Pan/zoom/drag on the preview canvas (null for pure-form editors). Subclass wires the callbacks. **/
	var gestures:EditorCanvasGestures = null;

	/** Native OPEN/SAVE dialog (Android SAF document picker; a real file browser on desktop). Shared by
		every mobile editor so open + save-as go through the system picker, not a fixed path. **/
	final fileDialog:FileDialogHandler = new FileDialogHandler();

	/** Set by the subclass on every edit, cleared on save/load; gates the exit confirmation. **/
	var unsavedProgress:Bool = false;

	/** Flags the document as edited (call from every mutation). **/
	inline function markDirty():Void
		unsavedProgress = true;

	/**
	 * Saves `data` through the system file picker (Android SAF "save as" / desktop save dialog). No-op
	 * while a previous dialog is still open.
	 * @param fileName the default file name (e.g. `bf.json`)
	 * @param data the file contents
	 */
	function saveFile(fileName:String, data:String, ?onSaved:Void->Void):Void {
		if (!fileDialog.completed)
			return;
		fileDialog.save(fileName, data, function():Void {
			unsavedProgress = false;
			UIToast.show('Saved: ${fileDialog.path}');
			if (onSaved != null)
				onSaved();
		}, null, function():Void UIToast.show('Save failed'));
	}

	/**
	 * Opens a file through the system picker and hands the loaded text + name to `onLoaded`. No-op while a
	 * previous dialog is still open.
	 * @param fileName default name shown in the picker
	 * @param title the picker title
	 * @param onLoaded called with (contents, name) on a successful pick
	 */
	function openFile(fileName:String, title:String, onLoaded:String->String->Void):Void {
		if (!fileDialog.completed)
			return;
		fileDialog.open(fileName, title, null, function():Void {
			if (fileDialog.data != null)
				onLoaded(fileDialog.data, fileDialog.path);
		});
	}

	/**
	 * Creates a full-screen, transparent magnifying camera plus a gesture object over the whole surface.
	 * Call once from the subclass `create()` (after `initPsychCamera`), then assign the camera to the
	 * editor's preview group and wire `gestures.onPan/onZoom/...`.
	 */
	function setupCanvas():Void {
		previewCam = new FlxCamera(0, 0, FlxG.width, FlxG.height);
		previewCam.bgColor = 0x00000000;
		FlxG.cameras.add(previewCam, false);
		gestures = new EditorCanvasGestures(FlxRect.get(0, 0, FlxG.width, FlxG.height));
	}

	/**
	 * Leaves the editor, asking first when the document has unsaved edits. SAVE & EXIT waits for the
	 * save to actually complete (the file picker is asynchronous), so a cancelled picker keeps the
	 * editor open with the edits intact.
	 */
	function exitEditor():Void {
		if (!unsavedProgress || shell == null) {
			leaveEditor();
			return;
		}
		shell.showPrompt('UNSAVED CHANGES', 'There are edits here that were never saved. Leave the editor anyway?', [
			{
				label: 'SAVE & EXIT',
				accent: true,
				cb: function():Void saveDocument(leaveEditor)
			},
			{label: 'DISCARD & EXIT', danger: true, cb: leaveEditor},
			{label: 'KEEP EDITING', cb: function():Void {}}
		]);
	}

	/** Returns to the editors menu (restoring the menu music), no questions asked. **/
	function leaveEditor():Void {
		MusicBeatState.switchState(new editors.MasterEditorMenu());
		FlxG.sound.playMusic(Paths.music('freakyMenu'));
	}

	/**
	 * Guards an action that replaces the edited document (New / Open / switching slot) behind the same
	 * unsaved-changes question. Runs `action` straight away when there is nothing to lose.
	 * @param what the action, phrased for the prompt body ("Open another chart")
	 * @param action run once the user accepts
	 */
	function confirmDiscard(what:String, action:Void->Void):Void {
		if (!unsavedProgress || shell == null) {
			action();
			return;
		}
		shell.showPrompt('UNSAVED CHANGES', '$what? The edits here were never saved.', [
			{
				label: 'SAVE FIRST',
				accent: true,
				cb: function():Void saveDocument(action)
			},
			{label: 'DISCARD', danger: true, cb: action},
			{label: 'CANCEL', cb: function():Void {}}
		]);
	}

	/**
	 * Writes the edited document (the subclass' SAVE action), calling `onSaved` once it landed. The
	 * default does nothing but report success, so an editor that never sets `unsavedProgress` needs
	 * no override.
	 * @param onSaved run after a successful save
	 */
	function saveDocument(?onSaved:Void->Void):Void {
		if (onSaved != null)
			onSaved();
	}

	/**
	 * Android back-button hook for the subclass to dismiss its own transient state (a selection, an open
	 * picker, unsaved-changes prompt, ...) BEFORE the base exits. Return `true` when handled.
	 * @return true if the back press was consumed
	 */
	function onBackButtonExtra():Bool
		return false;

	override function update(elapsed:Float):Void {
		#if android
		if (mobile.backend.BackButton.justPressed) {
			if (shell != null && shell.promptOpen)
				shell.closePrompt();
			else if (shell != null && shell.guideOpen)
				shell.closeGuide();
			else if (shell != null && shell.drawerOpen)
				shell.closeDrawer();
			else if (!onBackButtonExtra())
				exitEditor();
		}
		#end
		super.update(elapsed);
	}

	override function destroy():Void {
		if (shell != null)
			shell.dispose();
		fileDialog.destroy();
		super.destroy();
	}
}
