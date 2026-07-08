package editors.content;

import smidr.UITheme;
import smidr.widgets.UIButton;
import smidr.widgets.UIModal;

// Exit confirmation prompt used on all editors, for convenience
class ExitConfirmationPrompt extends Prompt {
	public function new(?finishCallback:Void->Void) {
		super('There\'s unsaved progress,\nare you sure you want to exit?', function() {
			FlxG.mouse.visible = false;
			MusicBeatState.switchState(new editors.MasterEditorMenu());
			FlxG.sound.playMusic(Paths.music('freakyMenu'));
			if (finishCallback != null)
				finishCallback();
		}, 'Exit');
		yesDanger = true;
	}
}

// A Simple Prompt with "OK" and "Cancel" that covers most case usages
class Prompt extends BasePrompt {
	/** Renders the confirm button as the destructive variant (exit/delete prompts). **/
	public var yesDanger:Bool = false;

	var yesFunction:Void->Void;
	var noFunction:Void->Void;
	var _yesTxt:String = 'OK';
	var _noTxt:String = 'Cancel';

	public function new(title:String, yesFunction:Void->Void, ?noFunction:Void->Void, ?_yesTxt:String, ?_noTxt:String) {
		if (_yesTxt != null)
			this._yesTxt = _yesTxt;
		if (_noTxt != null)
			this._noTxt = _noTxt;
		this.yesFunction = yesFunction;
		this.noFunction = noFunction;
		super(420, 170, title, promptCreate);
	}

	function promptCreate(_) {
		var bw:Float = 130;
		var bh:Float = 30;
		var gap:Float = 24;
		var btnY:Float = modal.h - UITheme.px(40) - bh - 16;

		var yes:UIButton = new UIButton(_yesTxt, bw, bh, function() {
			yesFunction();
			close();
		}, !yesDanger);
		yes.danger = yesDanger;
		yes.x = modal.w / 2 - bw - gap / 2;
		yes.y = btnY;
		modal.body.addChild(yes);

		var no:UIButton = new UIButton(_noTxt, bw, bh, close);
		no.x = modal.w / 2 + gap / 2;
		no.y = btnY;
		modal.body.addChild(no);
	}

	override function close() {
		if (noFunction != null)
			noFunction();
		super.close();
	}
}

/**
	Base for editor dialogs on the SmidrUI overlay: a `UIModal` opened on the active root, with
	the substate providing modality to the flixel state underneath. Builders add widgets to
	`modal.body` (panel-local coordinates, origin below the title). Escape / backdrop clicks
	close both the modal and this substate. (The legacy chart editor keeps its own PsychUI
	version at `legacy.editors.content.Prompt`.)
**/
class BasePrompt extends MusicBeatSubstate {
	var _sizeX:Float = 0;
	var _sizeY:Float = 0;
	var _title:String;

	public var onCreate:BasePrompt->Void;
	public var onUpdate:BasePrompt->Float->Void;

	/** The dialog panel; builders parent their widgets into `modal.body`. **/
	public var modal:UIModal;

	var _closed:Bool = false;
	var _pendingClose:Bool = false;

	public function new(?sizeX:Float = 420, ?sizeY:Float = 160, title:String, ?onCreate:BasePrompt->Void, ?onUpdate:BasePrompt->Float->Void) {
		this._sizeX = sizeX;
		this._sizeY = sizeY;
		this._title = title;
		this.onCreate = onCreate;
		this.onUpdate = onUpdate;
		super();
	}

	override function create() {
		modal = new UIModal(_title, _sizeX, _sizeY);
		modal.onClosed = function() {
			// Escape / backdrop path: the modal is already gone, take the substate with it.
			modal = null;
			if (!_closed) {
				_closed = true;
				close();
			}
		};
		modal.open();

		if (modal.parent == null) {
			// No SmidrUI root attached in this state: nothing can render the dialog, bail out.
			modal = null;
			_pendingClose = true;
		} else if (onCreate != null)
			onCreate(this);
		super.create();
	}

	override function update(elapsed:Float) {
		super.update(elapsed);
		if (_pendingClose) {
			_pendingClose = false;
			close();
			return;
		}
		if (onUpdate != null)
			onUpdate(this, elapsed);
	}

	override function close() {
		if (!_closed) {
			_closed = true;
			if (modal != null) {
				var m:UIModal = modal;
				modal = null;
				m.onClosed = null;
				m.close();
			}
		}
		super.close();
	}

	override function destroy() {
		if (modal != null) {
			var m:UIModal = modal;
			modal = null;
			m.onClosed = null;
			m.close();
		}
		super.destroy();
	}
}
