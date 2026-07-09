package mobile.options;

import options.Option;
import options.BaseOptionsMenu;

/**
 * Mobile-only settings: on-screen control opacity and vibration. Registered in
 * OptionsState under `#if mobile`.
 */
class MobileOptionsSubState extends BaseOptionsMenu
{
	public function new()
	{
		title = Language.getPhrase('mobile_menu', 'Mobile Settings');
		rpcTitle = 'Mobile Settings Menu';

		var option:Option = new Option('Controls Opacity', 'How visible the on-screen buttons are.', 'controlsAlpha', PERCENT);
		option.minValue = 0.1;
		option.maxValue = 1;
		option.onChange = onChangeControlsAlpha;
		addOption(option);

		var option:Option = new Option('Vibration', 'Vibrate on note hits and misses.', 'vibration', BOOL);
		addOption(option);

		#if android
		var option:Option = new Option('Pause Button',
			'Show an on-screen Pause button during gameplay.\nWhen off, pause with the system Back button/gesture.', 'pauseButton', BOOL);
		addOption(option);
		#end

		super();
	}

	function onChangeControlsAlpha():Void
	{
		if (touchPad != null)
			for (btn in touchPad.buttons)
				btn.idleAlpha = ClientPrefs.data.controlsAlpha;
	}
}
