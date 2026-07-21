package states.freeplay;

import flixel.FlxBasic;
import flixel.FlxG;
import flixel.util.FlxStringUtil;
import smidr.UIRoot;
import smidr.widgets.UIPanel;
import smidr.widgets.UILabel;
import smidr.widgets.UIButton;
import smidr.widgets.UISlider;
import smidr.widgets.UIStepper;

/**
 * The persistent Freeplay music-preview bar, rebuilt on SmidrUI (replaces the old Flixel `MusicPlayer`
 * overlay). It is a thin VIEW: it shows the selected song, playback time and a draggable seek slider,
 * with Play/Pause + Reset buttons and a playback-rate stepper. All transport actions call back into
 * `FreeplayState`, which owns the preview audio (inst + vocals) — the bar never touches sound directly
 * except to read `FlxG.sound.music` for the time/progress readout.
 *
 * It extends `FlxBasic` only so `add()` ticks its `update` while the widgets live on the Smidr `uiRoot`
 * (the same hybrid used by `mobile.input.TouchPad`).
 */
class FreeplayMusicBar extends FlxBasic {
	public var onTogglePlay:Void->Void = null;
	public var onSeek:Float->Void = null;
	public var onReset:Void->Void = null;
	public var onRate:Float->Void = null;

	var root:UIRoot;
	var panel:UIPanel;
	var songLbl:UILabel;
	var timeLbl:UILabel;
	var seek:UISlider;
	var playBtn:UIButton;
	var resetBtn:UIButton;
	var rateStepper:UIStepper;

	var scrubHold:Float = 0;
	var previewing:Bool = false;
	var playing:Bool = false;

	static inline final PAD:Float = 12;
	static inline final GAP:Float = 8;
	static inline final BTN_H:Float = 30;

	public function new(root:UIRoot) {
		super();
		this.root = root;

		panel = new UIPanel(400, 96);
		panel.alpha = 0.5;
		root.content.addChild(panel);

		songLbl = new UILabel('', 15, 0);
		root.content.addChild(songLbl);

		timeLbl = new UILabel('', 12, 1, RIGHT);
		root.content.addChild(timeLbl);

		seek = new UISlider('', 100, 0, 1, 0, function(v:Float):Void {
			scrubHold = 0.2;
			if (previewing && onSeek != null)
				onSeek(v);
		});
		root.content.addChild(seek);

		playBtn = new UIButton('Play', 66, BTN_H, function():Void {
			if (onTogglePlay != null)
				onTogglePlay();
		}, true);
		root.content.addChild(playBtn);

		resetBtn = new UIButton('Reset', 66, BTN_H, function():Void {
			if (onReset != null)
				onReset();
		});
		root.content.addChild(resetBtn);

		rateStepper = new UIStepper('Rate', 150, 1.0, 0.05, function(v:Float):Void {
			if (onRate != null)
				onRate(v);
		});
		rateStepper.min = 0.25;
		rateStepper.max = 3.0;
		rateStepper.decimals = 2;
		root.content.addChild(rateStepper);
	}

	public function setArea(x:Float, y:Float, w:Float, h:Float):Void {
		panel.x = x;
		panel.y = y;
		panel.resize(w, h);

		var innerW:Float = w - PAD * 2;
		var timeW:Float = innerW * 0.42;

		songLbl.wrapWidth = innerW - timeW - GAP;
		songLbl.x = x + PAD;
		songLbl.y = y + PAD;

		timeLbl.wrapWidth = timeW;
		timeLbl.x = x + w - PAD - timeW;
		timeLbl.y = y + PAD;

		seek.resize(innerW, 16);
		seek.x = x + PAD;
		seek.y = y + PAD + 28;

		var by:Float = y + h - PAD - BTN_H;
		playBtn.resize(70, BTN_H);
		playBtn.x = x + PAD;
		playBtn.y = by;

		resetBtn.resize(70, BTN_H);
		resetBtn.x = playBtn.x + 70 + GAP;
		resetBtn.y = by;

		var rateW:Float = Math.min(160, innerW - 140 - GAP * 2);
		rateStepper.resize(rateW, BTN_H);
		rateStepper.x = x + w - PAD - rateW;
		rateStepper.y = by;
	}

	public function setSong(name:String):Void {
		songLbl.text = (name != null && name.length > 0) ? name : '—';
	}

	public function setPreviewing(v:Bool):Void {
		previewing = v;
		if (!v) {
			playing = false;
			playBtn.label = 'Play';
			seek.value = 0;
		}
	}

	public function setPlaying(v:Bool):Void {
		playing = v;
		playBtn.label = v ? 'Pause' : 'Play';
	}

	public function setRate(v:Float):Void {
		rateStepper.value = v;
	}

	override function update(elapsed:Float):Void {
		super.update(elapsed);

		if (scrubHold > 0)
			scrubHold -= elapsed;

		if (!previewing) {
			timeLbl.text = '';
			return;
		}

		var music = FlxG.sound.music;
		var len:Float = (music != null && music.length > 0) ? music.length : 0;
		var t:Float = (music != null) ? music.time : 0;

		timeLbl.text = fmt(t) + ' / ' + fmt(len);

		if (len > 0) {
			seek.max = len;
			if (scrubHold <= 0)
				seek.value = t;
		}
	}

	inline function fmt(ms:Float):String
		return FlxStringUtil.formatTime(ms / 1000, false);

	public function setWidgetsVisible(v:Bool):Void {
		panel.visible = v;
		songLbl.visible = v;
		timeLbl.visible = v;
		seek.visible = v;
		playBtn.visible = v;
		resetBtn.visible = v;
		rateStepper.visible = v;
	}
}
