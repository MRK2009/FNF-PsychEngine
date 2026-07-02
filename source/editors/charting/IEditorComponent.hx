package editors.charting;

/**
	Lifecycle contract for every decoupled editor component (data views, audio, panels).
	`editors.ChartingState` holds a typed list and drives these;
	components never reference each other directly - they read/write the data models.
**/
interface IEditorComponent {
	/** Wires into the editor state (called once, after the models exist). **/
	function attach(state:editors.ChartingState):Void;

	/** Release everything (called from the state's `destroy`). **/
	function detach():Void;

	/** A different chart was loaded (or the whole chart was rebuilt). **/
	function onChartChanged():Void;
}
