package ui.widgets;

/** One `UIIconRail` tab definition: a short caption (<=4 chars reads best) + optional tooltip. **/
typedef UIRailTab = {
	var caption:String;
	@:optional var tooltipKey:String;
	@:optional var tooltipFallback:String;
}
