package ui.widgets;

/** One menu entry (`UIContextMenu`/`UIMenuBar`). `separator` renders a divider (other fields ignored). **/
typedef UIMenuItem = {
	@:optional var label:String;
	@:optional var key:String;
	@:optional var fallback:String;
	@:optional var shortcut:String;
	@:optional var onSelect:Void->Void;
	@:optional var separator:Bool;
	@:optional var disabled:Bool;
	@:optional var checked:Null<Bool>;
}
