// HScript template: every hook the engine calls, with the arguments it actually passes.
// Delete what you do not need -- a hook you do not declare costs nothing.
//
// Naming: every hook here is written `onX`. Eight of them are dispatched by the engine under older
// names without the prefix (goodNoteHit, noteMiss, eventEarlyTrigger and friends); the `onX` spelling
// is bound to those at load, so it works everywhere. Declare one spelling or the other, never both.


// ---------------------------------------------------------------------------
// Lifecycle -- these fire in menus and editors too, not only in a song
// ---------------------------------------------------------------------------

function onCreate()
{
	// The script just started. Most of the state around it does not exist yet.
}

function onCreatePost()
{
	// End of "create". Everything the state builds is up.
}

function onDestroy()
{
	// The script is going away.
}

function onStateChange(className:String)
{
	// The game switched state. "className" is the full path, e.g. 'states.PlayState'.
}


// ---------------------------------------------------------------------------
// Song lifecycle
// ---------------------------------------------------------------------------

function onSectionHit()
{
	// Triggered after it goes to the next section
}

function onBeatHit()
{
	// Triggered 4 times per section
}

function onStepHit()
{
	// Triggered 16 times per section
}

function onUpdate(elapsed:Float)
{
	// Start of "update", some variables weren't updated yet
	// Also gets called while in the game over screen
}

function onUpdatePost(elapsed:Float)
{
	// End of "update"
	// Also gets called while in the game over screen
}

function onStartCountdown()
{
	// Countdown started, duh
	// return Function_Stop if you want to stop the countdown from happening (Can be used to trigger
	// dialogues and stuff! You can trigger the countdown with startCountdown())
	return Function_Continue;
}

function onCountdownStarted()
{
	// Called AFTER countdown started. To stop it, use onStartCountdown above.
}

function onCountdownTick(tick:Countdown, counter:Int)
{
	switch(tick)
	{
		case Countdown.THREE:
			// Counter equals to 0
		case Countdown.TWO:
			// Counter equals to 1
		case Countdown.ONE:
			// Counter equals to 2
		case Countdown.GO:
			// Counter equals to 3
		case Countdown.START:
			// Counter equals to 4. No visual indication -- this is nearly the exact moment the song starts.
	}
}

function onSongStart()
{
	// Inst and Vocals start playing, songPosition = 0
}

function onEndSong()
{
	// Song ended/starting transition (Will be delayed if you're unlocking an achievement)
	// return Function_Stop to stop the song from ending for playing a cutscene or something.
	return Function_Continue;
}

function onSongRetry()
{
	// The song is restarting. Pause menu and game over both route here.
}

function onSongExit()
{
	// The player is leaving the song for a menu.
}

function onResults(result:Dynamic)
{
	// The results screen is about to open. "result" is the finished ScoreRecord.
}


// ---------------------------------------------------------------------------
// Notes and strumlines
// ---------------------------------------------------------------------------
// A note is data plus a pooled drawable. The drawable you get here is on loan: once the note leaves
// play it goes back in the pool and is handed out for a different note, so key anything you track by
// `note.data`, never by the sprite.

function onNotesGenerated(notes:Array<NoteData>)
{
	// The decoded chart, before the strumlines bucket it. The window for adding, removing or
	// retiming notes wholesale.
}

function onSpawnNote(note:NoteSprite)
{
	// A note entered play. `note.data` is its NoteData:
	//   note.data.time      when it must be hit
	//   note.data.column    its lane
	//   note.data.type      the note type name
	//   note.data.length    hold length, 0 for a tap
	//   note.data.mustPress true when it is the player's
	// Reskin it here with setNoteTexture / setNoteTexturePart / setNoteColorable.
}

function onDespawnNote(note:NoteSprite)
{
	// The note left play, however it left -- hit, missed, or simply scrolled past. Its drawables are
	// already back in the pool, so this is where you drop whatever you were tracking for it.
}

function onSustainRelease(note:SustainSprite)
{
	// A hold was dropped early. onNoteMiss fires too; this exists so you can tell a dropped hold from a
	// note that was never pressed.
}

function onStrumsCreated(strumlineCount:Int)
{
	// Receptors and note fields all exist. The earliest point you can safely move or restyle them.
}

function onKeyCountChange(totalColumns:Int)
{
	// A strumline's key count changed.
}

function onNoteSkinLoaded(skinName:String)
{
	// The note skin this song resolved to.
}

function onUISkinLoaded(skinName:String)
{
	// The judgement-UI skin this song resolved to.
}


// ---------------------------------------------------------------------------
// Judgement
// ---------------------------------------------------------------------------
// These four plus onNoteMiss/onNoteMissPress are dispatched as goodNoteHit, noteMiss and so on; the
// onX names below are aliases bound at load. Either spelling works, so pick one.

function onGoodNoteHitPre(note:NoteSprite)
{
	// You hit a note, BEFORE the hit is scored.
	// return Function_Stop to cancel the hit entirely.
	return Function_Continue;
}

function onOpponentNoteHitPre(note:NoteSprite)
{
	// Same, for the opponent's notes.
	return Function_Continue;
}

function onGoodNoteHit(note:NoteSprite)
{
	// You hit a note, AFTER the hit is scored.
}

function onOpponentNoteHit(note:NoteSprite)
{
	// Same, for the opponent's notes.
}

function onNoteMiss(note:NoteSprite)
{
	// A note was missed by letting it go past.
}

function onNoteMissPress(direction:Int)
{
	// You pressed a key with no note under it (ghost miss).
}

function onGhostTap(key:Int)
{
	// You pressed a key with no note under it while Ghost Tapping is ON, so it was not a miss.
}


// ---------------------------------------------------------------------------
// Input
// ---------------------------------------------------------------------------
// "key" is the lane index: 0 - left, 1 - down, 2 - up, 3 - right on a 4-key chart.

function onKeyPressPre(key:Int)
{
	// Before the note key press calculations
}

function onKeyPress(key:Int)
{
	// After the note key press calculations
}

function onKeyReleasePre(key:Int)
{
	// Before the note key release calculations
}

function onKeyRelease(key:Int)
{
	// After the note key release calculations
}


// ---------------------------------------------------------------------------
// Pausing and dying
// ---------------------------------------------------------------------------

function onPause()
{
	// Called when you press Pause while not on a cutscene/etc
	// return Function_Stop if you want to stop the player from pausing the game
	return Function_Continue;
}

function onResume()
{
	// The game resumed (WARNING: not necessarily from the pause screen, but most likely is!!!)
}

function onGameOver()
{
	// You died! Called every single frame your health is at or below zero.
	// return Function_Stop to stop the player from going into the game over screen (extra lives, shields).
	return Function_Continue;
}

function onGameOverStart()
{
	// You entered the game over screen and "onGameOver" wasn't stopped
}

function onGameOverConfirm(retry:Bool)
{
	// You pressed Enter/Esc on Game Over. "retry" is false if you pressed Esc.
}


// ---------------------------------------------------------------------------
// Dialogue (when a dialogue finishes it calls startCountdown again)
// ---------------------------------------------------------------------------

function onNextDialogue(line:Int)
{
	// The next dialogue line started. Lines start at 0, and line 0 does not trigger this.
}

function onSkipDialogue(line:Int)
{
	// You pressed Enter and skipped a line that was still being typed. Lines start at 0.
}


// ---------------------------------------------------------------------------
// Score, camera, characters
// ---------------------------------------------------------------------------

function onUpdateScorePre(miss:Bool)
{
	// Before the score text updates. "miss" is true if you missed.
	// return Function_Stop to stop the score text from updating.
	// The engine dispatches this as preUpdateScore; onUpdateScorePre is the alias.
	return Function_Continue;
}

function onUpdateScore(miss:Bool)
{
	// After the score text updates. "miss" is true if you missed.
}

function onRecalculateRating()
{
	// return Function_Stop to do your own rating calculation, then use setRatingPercent() for the
	// number and setRatingString() for the funny rating name.
	// NOTE: THIS IS CALLED BEFORE THE CALCULATION!!!
	return Function_Continue;
}

function onMoveCamera(focus:String)
{
	// The camera focused on a character: 'boyfriend', 'dad' or 'gf'.
}

function onStageChanged(stageName:String)
{
	// The `Change Stage` event swapped the stage. Anything you cached from the old one -- a prop out
	// of getVar/variables, a sprite you held on to -- is destroyed by now, so re-fetch it here.
}

function onCharacterChange(line:Int, oldCharacter:String, newCharacter:String)
{
	// A Change Character swap FINISHED, so the new character is loaded and on stage.
}

function onHealthChange(previous:Float, current:Float)
{
	// Health changed. Beats polling it in onUpdatePost.
}


// ---------------------------------------------------------------------------
// Chart events
// ---------------------------------------------------------------------------

function onEvent(name:String, value1:String, value2:String, strumTime:Float)
{
	// Event note triggered.
}

function onEventPushed(name:String, value1:String, value2:String, strumTime:Float)
{
	// Called once for every event note in the chart. The place to precache its assets.
}

function onEventEarlyTrigger(name:String, value1:String, value2:String, strumTime:Float)
{
	/*
	Return how many milliseconds early the event should fire. A port of the Kill Henchmen trigger:

	if (name == 'Kill Henchmen')
		return 280;

	which fires it 280ms early so the kill sound lands with the song.
	*/

	// Write yours under this line. The return value overrides the ones hardcoded in the engine.
	// The engine dispatches this as eventEarlyTrigger; onEventEarlyTrigger is the alias.
}

function onChartParsed(chart:Dynamic)
{
	// The chart is parsed but not yet turned into notes -- the window to rewrite its metadata,
	// events or strumlines before anything is built from it.
}


// ---------------------------------------------------------------------------
// Menus (Freeplay and Story)
// ---------------------------------------------------------------------------

function onSelectionChange(index:Int, total:Int)
{
	// The highlighted entry changed.
}

function onDifficultyChange(index:Int, name:String)
{
	// The chosen difficulty changed.
}

function onSongSelected(songKey:String, difficulty:Int)
{
	// A song is about to load. return Function_Stop to cancel it.
	return Function_Continue;
}

function onWeekSelected(weekName:String, difficulty:Int)
{
	// A week is about to load. return Function_Stop to cancel it.
	return Function_Continue;
}


// ---------------------------------------------------------------------------
// Engine services -- these reach whichever script host is current, menus included
// ---------------------------------------------------------------------------

function onTweenCompleted(tag:String)
{
	// A tween you started with a tag finished.
}

function onTimerCompleted(tag:String, loops:Int, loopsLeft:Int)
{
	// A timer you started with a tag ticked.
}

function onSoundFinished(tag:String)
{
	// A sound you started with a tag finished.
}

function onAchievementUnlocked(name:String)
{
	// An achievement unlocked, whether a script or the engine did it.
}

function onModSwitched(folder:String)
{
	// The active mod changed.
}


// ---------------------------------------------------------------------------
// Custom substates -- one you opened yourself with openCustomSubstate(name)
// ---------------------------------------------------------------------------

function onCustomSubstateCreate(name:String)
{
}

function onCustomSubstateCreatePost(name:String)
{
}

function onCustomSubstateUpdate(name:String, elapsed:Float)
{
}

function onCustomSubstateUpdatePost(name:String, elapsed:Float)
{
}

function onCustomSubstateDestroy(name:String)
{
	// Called when you use closeCustomSubstate()
}
