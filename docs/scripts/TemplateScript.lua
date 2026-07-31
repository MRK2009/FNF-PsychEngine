-- Lua template: every hook the engine calls, with the arguments it actually passes.
-- Delete what you do not need -- a hook you do not declare costs nothing.
--
-- Naming: every hook here is written "onX". Eight of them are dispatched by the engine under older
-- names without the prefix (goodNoteHit, noteMiss, eventEarlyTrigger and friends); the "onX" spelling
-- is bound to those at load, so it works everywhere. Declare one spelling or the other, never both.


---------------------------------------------------------------------------
-- Lifecycle -- these fire in menus and editors too, not only in a song
---------------------------------------------------------------------------

function onCreate()
	-- The script just started. Most of the state around it does not exist yet.
end

function onCreatePost()
	-- End of "create". Everything the state builds is up.
end

function onDestroy()
	-- The script is going away.
end

function onStateChange(className)
	-- The game switched state. "className" is the full path, e.g. 'states.PlayState'.
end


---------------------------------------------------------------------------
-- Song lifecycle
---------------------------------------------------------------------------

function onSectionHit()
	-- Triggered after it goes to the next section
end

function onBeatHit()
	-- Triggered 4 times per section
end

function onStepHit()
	-- Triggered 16 times per section
end

function onUpdate(elapsed)
	-- Start of "update", some variables weren't updated yet
	-- Also gets called while in the game over screen
end

function onUpdatePost(elapsed)
	-- End of "update"
	-- Also gets called while in the game over screen
end

function onStartCountdown()
	-- Countdown started, duh
	-- return Function_Stop if you want to stop the countdown from happening (Can be used to trigger
	-- dialogues and stuff! You can trigger the countdown with startCountdown())
	return Function_Continue;
end

function onCountdownStarted()
	-- Called AFTER countdown started. To stop it, use onStartCountdown above.
end

function onCountdownTick(counter)
	-- counter = 0 -> "Three"
	-- counter = 1 -> "Two"
	-- counter = 2 -> "One"
	-- counter = 3 -> "Go!"
	-- counter = 4 -> no visual indication, this is nearly the exact moment the song starts
end

function onSongStart()
	-- Inst and Vocals start playing, songPosition = 0
end

function onEndSong()
	-- Song ended/starting transition (Will be delayed if you're unlocking an achievement)
	-- return Function_Stop to stop the song from ending for playing a cutscene or something.
	return Function_Continue;
end

function onSongRetry()
	-- The song is restarting. Pause menu and game over both route here.
end

function onSongExit()
	-- The player is leaving the song for a menu.
end

function onResults()
	-- The results screen is about to open. Read the finished score off game.playResult.
end


---------------------------------------------------------------------------
-- Notes and strumlines
---------------------------------------------------------------------------
-- A note is data plus a pooled drawable. "id" is the note's index in its field, so it is only valid
-- while the callback runs -- the slot is reused for a different note afterwards.
--
-- Reach a note's fields with the field group and that id:
--   getPropertyFromGroup('game.playerField.notes', id, 'x')
--   setPropertyFromGroup('game.opponentField.notes', id, 'alpha', 0.5)
-- and pick the group with mustPress: 'game.playerField' when true, 'game.opponentField' when false.

function onNotesGenerated(notes)
	-- The decoded chart, before the strumlines bucket it. The window for adding, removing or
	-- retiming notes wholesale.
	--
	-- "notes" is a real 1-based table of live NoteData, so notes[1].time reads and writes through to
	-- the chart. Unlike the id above, these are the data objects and outlive the callback.
end

function onSpawnNote(id, column, noteType, isSustain, time, mustPress)
	-- A note entered play. Reskin it here with setNoteTexture / setNoteTexturePart / setNoteColorable.
end

function onDespawnNote(id, column, noteType, isSustain, time, mustPress)
	-- The note left play, however it left -- hit, missed, or simply scrolled past. "id" is -1: its
	-- drawables are already back in the pool, so there is nothing left to point at. This is where you
	-- drop whatever you were tracking for it.
end

function onSustainRelease(id, column, noteType, time)
	-- A hold was dropped early. onNoteMiss fires too; this exists so you can tell a dropped hold from a
	-- note that was never pressed. "id" is -1.
end

function onStrumsCreated(strumlineCount)
	-- Receptors and note fields all exist. The earliest point you can safely move or restyle them.
end

function onKeyCountChange(totalColumns)
	-- A strumline's key count changed.
end

function onNoteSkinLoaded(skinName)
	-- The note skin this song resolved to.
end

function onUISkinLoaded(skinName)
	-- The judgement-UI skin this song resolved to.
end


---------------------------------------------------------------------------
-- Judgement
---------------------------------------------------------------------------
-- These four plus onNoteMiss/onNoteMissPress are dispatched as goodNoteHit, noteMiss and so on; the
-- onX names below are aliases bound at load. Either spelling works, so pick one.
--
-- "id" is -1 in all of them: the note is being judged, not spawned, so there is no live index to
-- hand you. Read the note that was just judged off game.lastJudgedNote, e.g.
--   getProperty('lastJudgedNote.time')

function onGoodNoteHitPre(id, column, noteType, isSustain)
	-- You hit a note, BEFORE the hit is scored.
	-- return Function_Stop to cancel the hit entirely.
	return Function_Continue;
end

function onOpponentNoteHitPre(id, column, noteType, isSustain)
	-- Same, for the opponent's notes.
	return Function_Continue;
end

function onGoodNoteHit(id, column, noteType, isSustain)
	-- You hit a note, AFTER the hit is scored.
end

function onOpponentNoteHit(id, column, noteType, isSustain)
	-- Same, for the opponent's notes.
end

function onNoteMiss(id, column, noteType, isSustain)
	-- A note was missed by letting it go past.
end

function onNoteMissPress(direction)
	-- You pressed a key with no note under it (ghost miss).
end

function onGhostTap(key)
	-- You pressed a key with no note under it while Ghost Tapping is ON, so it was not a miss.
end


---------------------------------------------------------------------------
-- Input
---------------------------------------------------------------------------
-- "key" is the lane index: 0 - left, 1 - down, 2 - up, 3 - right on a 4-key chart.

function onKeyPressPre(key)
	-- Before the note key press calculations
end

function onKeyPress(key)
	-- After the note key press calculations
end

function onKeyReleasePre(key)
	-- Before the note key release calculations
end

function onKeyRelease(key)
	-- After the note key release calculations
end


---------------------------------------------------------------------------
-- Pausing and dying
---------------------------------------------------------------------------

function onPause()
	-- Called when you press Pause while not on a cutscene/etc
	-- return Function_Stop if you want to stop the player from pausing the game
	return Function_Continue;
end

function onResume()
	-- The game resumed (WARNING: not necessarily from the pause screen, but most likely is!!!)
end

function onGameOver()
	-- You died! Called every single frame your health is at or below zero.
	-- return Function_Stop to stop the player from going into the game over screen (extra lives, shields).
	return Function_Continue;
end

function onGameOverStart()
	-- You entered the game over screen and "onGameOver" wasn't stopped
end

function onGameOverConfirm(retry)
	-- You pressed Enter/Esc on Game Over. "retry" is false if you pressed Esc.
end


---------------------------------------------------------------------------
-- Dialogue (when a dialogue finishes it calls startCountdown again)
---------------------------------------------------------------------------

function onNextDialogue(line)
	-- The next dialogue line started. Lines start at 0, and line 0 does not trigger this.
end

function onSkipDialogue(line)
	-- You pressed Enter and skipped a line that was still being typed. Lines start at 0.
end


---------------------------------------------------------------------------
-- Score, camera, characters
---------------------------------------------------------------------------

function onUpdateScorePre(miss)
	-- Before the score text updates. "miss" is true if you missed.
	-- return Function_Stop to stop the score text from updating.
	-- The engine dispatches this as preUpdateScore; onUpdateScorePre is the alias.
	return Function_Continue;
end

function onUpdateScore(miss)
	-- After the score text updates. "miss" is true if you missed.
end

function onRecalculateRating()
	-- return Function_Stop to do your own rating calculation, then use setRatingPercent() for the
	-- number and setRatingString() for the funny rating name.
	-- NOTE: THIS IS CALLED BEFORE THE CALCULATION!!!
	return Function_Continue;
end

function onMoveCamera(focus)
	-- The camera focused on a character: 'boyfriend', 'dad' or 'gf'.
end

function onStageChanged(stageName)
	-- The "Change Stage" event swapped the stage. Anything you cached from the old one -- a prop out
	-- of getVar, a sprite you held on to -- is destroyed by now, so re-fetch it here.
end

function onCharacterChange(line, oldCharacter, newCharacter)
	-- A Change Character swap FINISHED, so the new character is loaded and on stage.
end

function onHealthChange(previous, current)
	-- Health changed. Beats polling it in onUpdatePost.
end


---------------------------------------------------------------------------
-- Chart events
---------------------------------------------------------------------------

function onEvent(name, value1, value2, strumTime)
	-- Event note triggered.
end

function onEventPushed(name, value1, value2, strumTime)
	-- Called once for every event note in the chart. The place to precache its assets.
end

function onEventEarlyTrigger(name, value1, value2, strumTime)
	-- Return how many milliseconds early the event should fire. A port of the Kill Henchmen trigger:
	--
	--   if name == 'Kill Henchmen' then
	--     return 280;
	--   end
	--
	-- which fires it 280ms early so the kill sound lands with the song.
	-- The engine dispatches this as eventEarlyTrigger; onEventEarlyTrigger is the alias.
end

function onChartParsed()
	-- The chart is parsed but not yet turned into notes -- the window to rewrite its metadata,
	-- events or strumlines before anything is built from it.
end


---------------------------------------------------------------------------
-- Menus (Freeplay and Story)
---------------------------------------------------------------------------

function onSelectionChange(index, total)
	-- The highlighted entry changed.
end

function onDifficultyChange(index, name)
	-- The chosen difficulty changed.
end

function onSongSelected(songKey, difficulty)
	-- A song is about to load. return Function_Stop to cancel it.
	return Function_Continue;
end

function onWeekSelected(weekName, difficulty)
	-- A week is about to load. return Function_Stop to cancel it.
	return Function_Continue;
end


---------------------------------------------------------------------------
-- Engine services -- these reach whichever script host is current, menus included
---------------------------------------------------------------------------

function onTweenCompleted(tag)
	-- A tween you started with a tag finished.
end

function onTimerCompleted(tag, loops, loopsLeft)
	-- A timer you started with a tag ticked.
end

function onSoundFinished(tag)
	-- A sound you started with a tag finished.
end

function onAchievementUnlocked(name)
	-- An achievement unlocked, whether a script or the engine did it.
end

function onModSwitched(folder)
	-- The active mod changed.
end


---------------------------------------------------------------------------
-- Custom substates -- one you opened yourself with openCustomSubstate(name)
---------------------------------------------------------------------------

function onCustomSubstateCreate(name)
end

function onCustomSubstateCreatePost(name)
end

function onCustomSubstateUpdate(name, elapsed)
end

function onCustomSubstateUpdatePost(name, elapsed)
end

function onCustomSubstateDestroy(name)
	-- Called when you use closeCustomSubstate()
end
