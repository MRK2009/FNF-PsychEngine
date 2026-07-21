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
 * (guide -> drawer -> subclass hook -> exit). Subclasses build their content (canvas + rails + drawer
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

	/**
	 * Saves `data` through the system file picker (Android SAF "save as" / desktop save dialog). No-op
	 * while a previous dialog is still open.
	 * @param fileName the default file name (e.g. `bf.json`)
	 * @param data the file contents
	 */
	function saveFile(fileName:String, data:String):Void {
		if (!fileDialog.completed)
			return;
		fileDialog.save(fileName, data, function():Void UIToast.show('Saved: ${fileDialog.path}'), null, function():Void UIToast.show('Save failed'));
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

	/** Returns to the editors menu (restoring the menu music). **/
	function exitEditor():Void {
		MusicBeatState.switchState(new editors.MasterEditorMenu());
		FlxG.sound.playMusic(Paths.music('freakyMenu'));
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
			if (shell != null && shell.guideOpen)
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
