package editors.content;

import smidr.UITheme;
import smidr.widgets.UILabel;
import smidr.widgets.UIModal;

typedef HelpSection = {title:String, lines:Array<String>};

/** Builds the sectioned F1 keybind-reference modal shared by the editors. **/
class EditorHelp {
	/**
		Creates and opens a help modal sized to its content. The caller keeps the returned
		reference (and clears it from `onClosed`) so its F1 key can toggle the dialog.
		@param title the modal header
		@param sections the section headers with their keybind lines
		@param width the modal width
		@return the opened modal
	**/
	public static function open(title:String, sections:Array<HelpSection>, width:Float = 620):UIModal {
		var bodyH:Float = 6;
		for (section in sections)
			bodyH += 26 + section.lines.length * 20 + 12;

		var modal:UIModal = new UIModal(title, width, UITheme.px(40) + bodyH + 8);

		var y:Float = 6;
		for (section in sections) {
			var head:UILabel = new UILabel(section.title, 14, 0);
			head.colorOverride = UITheme.accent;
			head.x = 24;
			head.y = y;
			modal.body.addChild(head);
			y += 26;
			for (line in section.lines) {
				var lbl:UILabel = new UILabel(line, 12, 1);
				lbl.x = 36;
				lbl.y = y;
				modal.body.addChild(lbl);
				y += 20;
			}
			y += 12;
		}

		modal.open();
		return modal;
	}
}
