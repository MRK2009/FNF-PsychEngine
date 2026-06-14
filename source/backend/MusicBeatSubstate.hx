package backend;

import flixel.FlxSubState;

class MusicBeatSubstate extends FlxSubState {
	// The mod folder a scripted substate was loaded from (null for built-in ones).
	// Set by scripting.ScriptedStates; used for auto mod-scoping of asset lookups.
	public var scriptOwnerMod:String = null;

	public function new() {
		super();
	}

	private var curSection:Int = 0;
	private var stepsToDo:Int = 0;

	private var lastBeat:Float = 0;
	private var lastStep:Float = 0;

	private var curStep:Int = 0;
	private var curBeat:Int = 0;

	private var curDecStep:Float = 0;
	private var curDecBeat:Float = 0;

	// See MusicBeatState: meter-aware beat tracking, reduces to curStep/4 for 4/4.
	private var sectionStartStep:Int = 0;
	private var beatsBeforeSection:Int = 0;
	private var stepsPerBeatCur:Int = 4;

	private var controls(get, never):Controls;

	inline function get_controls():Controls
		return Controls.instance;

	override function update(elapsed:Float) {
		// everyStep();
		if (!persistentUpdate)
			MusicBeatState.timePassedOnState += elapsed;
		var oldStep:Int = curStep;

		updateCurStep();
		updateBeat();

		if (oldStep != curStep) {
			if (curStep > 0)
				stepHit();

			if (PlayState.SONG != null) {
				if (oldStep < curStep)
					updateSection();
				else
					rollbackSection();
			}
		}

		super.update(elapsed);
	}

	private function updateSection():Void {
		if (stepsToDo < 1) {
			sectionStartStep = 0;
			beatsBeforeSection = 0;
			stepsPerBeatCur = Conductor.stepsPerBeat(Conductor.getSectionDenominator(PlayState.SONG, curSection));
			stepsToDo = sectionStartStep + Math.round(getBeatsOnSection() * stepsPerBeatCur);
		}
		while (curStep >= stepsToDo) {
			beatsBeforeSection += (stepsPerBeatCur > 0) ? Math.ceil((stepsToDo - sectionStartStep) / stepsPerBeatCur) : 0;
			sectionStartStep = stepsToDo;
			curSection++;
			stepsPerBeatCur = Conductor.stepsPerBeat(Conductor.getSectionDenominator(PlayState.SONG, curSection));
			stepsToDo += Math.round(getBeatsOnSection() * stepsPerBeatCur);
			sectionHit();
		}
	}

	private function rollbackSection():Void {
		if (curStep < 0)
			return;

		var lastSection:Int = curSection;
		curSection = 0;
		stepsToDo = 0;
		sectionStartStep = 0;
		beatsBeforeSection = 0;
		stepsPerBeatCur = Conductor.stepsPerBeat(Conductor.getSectionDenominator(PlayState.SONG, 0));
		for (i in 0...PlayState.SONG.notes.length) {
			if (PlayState.SONG.notes[i] != null) {
				var spb:Int = Conductor.stepsPerBeat(Conductor.getSectionDenominator(PlayState.SONG, curSection));
				var secSteps:Int = Math.round(getBeatsOnSection() * spb);
				if (stepsToDo + secSteps > curStep) {
					sectionStartStep = stepsToDo;
					stepsPerBeatCur = spb;
					stepsToDo += secSteps;
					break;
				}
				stepsToDo += secSteps;
				beatsBeforeSection += (spb > 0) ? Math.ceil(secSteps / spb) : 0;
				curSection++;
			}
		}

		// rollbackSection only runs when we went backwards; the previous
		// `>` comparison meant sectionHit() never fired on rewinds and
		// substate-owned stage scripts ended up desynced.
		if (curSection != lastSection)
			sectionHit();
	}

	private function updateBeat():Void {
		var spb:Int = (stepsPerBeatCur > 0) ? stepsPerBeatCur : 4;
		curBeat = beatsBeforeSection + Math.floor((curStep - sectionStartStep) / spb);
		curDecBeat = beatsBeforeSection + (curDecStep - sectionStartStep) / spb;
	}

	private function updateCurStep():Void {
		var lastChange = Conductor.getBPMFromSeconds(Conductor.songPosition);

		var shit = ((Conductor.songPosition - ClientPrefs.data.noteOffset) - lastChange.songTime) / lastChange.stepCrochet;
		curDecStep = lastChange.stepTime + shit;
		curStep = lastChange.stepTime + Math.floor(shit);
	}

	public function stepHit():Void {
		if (stepsPerBeatCur > 0 && (curStep - sectionStartStep) % stepsPerBeatCur == 0)
			beatHit();
	}

	public function beatHit():Void {
		// do literally nothing dumbass
	}

	public function sectionHit():Void {
		// yep, you guessed it, nothing again, dumbass
	}

	function getBeatsOnSection() {
		var fallback:Float = (PlayState.SONG != null) ? Conductor.getBaseTimeSignature(PlayState.SONG)[0] : 4;
		var val:Null<Float> = fallback;
		if (PlayState.SONG != null && PlayState.SONG.notes[curSection] != null)
			val = PlayState.SONG.notes[curSection].sectionBeats;
		return val == null ? fallback : val;
	}
}
