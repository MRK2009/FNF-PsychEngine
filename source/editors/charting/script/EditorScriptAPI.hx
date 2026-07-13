package editors.charting.script;

import editors.ChartingState;
import smidr.overlays.UIToast;

/**
	The stable script-facing facade over the chart editor. Scripts also get the `editor`
	global (the `ChartingState` itself with its public `model`/`selection`/`audio`/`uiRoot`/
	`noteField` fields) for direct access; this API wraps the pieces that need registration
	or safe entry points.

	Available to both Lua (`api:...` via the LuaProxy bridge) and HScript (`api` global).
**/
final class EditorScriptAPI {
	final editor:ChartingState;
	final host:EditorScriptHost;

	/**
		@param editor the owning editor state
		@param host the script host (update-hook flag lives there)
	**/
	public function new(editor:ChartingState, host:EditorScriptHost) {
		this.editor = editor;
		this.host = host;
	}

	/** Opts this session into the per-frame `onEditorUpdate(elapsed)` hook (off by default). **/
	public function enableUpdateHook():Void {
		host.updateHookEnabled = true;
	}

	/** Shows a transient bottom-center message. **/
	public function toast(message:String):Void {
		UIToast.show(message);
	}

	/** Captures an undo step (call BEFORE mutating the chart through `editor.model`). **/
	public function snapshot(label:String):Void {
		editor.undoStack.snapshot(editor.model, label);
	}

	/** Appends an entry to a top-level menu ("File", "Edit", "View", "Playback", "Tools", "Help"). **/
	public function addMenuItem(menu:String, label:String, onSelect:Void->Void):Void {
		editor.addCustomMenuItem(menu, label, onSelect);
	}

	/** Adds a stateful chip to the Quick Toggles section. **/
	public function addQuickToggle(label:String, initial:Bool, onToggle:Bool->Void):Void {
		editor.addCustomToggle(label, initial, onToggle);
	}

	/** Adds a button row to the Options rail tab. **/
	public function addOptionButton(label:String, onClick:Void->Void):Void {
		editor.addCustomOptionButton(label, onClick);
	}

	/** Re-renders the docks after script-driven chart mutations or UI registrations. **/
	public function refreshUI():Void {
		editor.rebuildDocks();
	}

	/** Moves the playhead/section cursor. **/
	public function gotoSection(section:Int):Void {
		editor.gotoSection(section);
	}

	/** The playhead time in ms. **/
	public function getTime():Float {
		return editor.noteField.viewTime;
	}
}
