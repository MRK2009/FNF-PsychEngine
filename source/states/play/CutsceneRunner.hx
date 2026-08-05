package states.play;

import backend.Song;
import backend.Highscore;
import backend.UISkinConfig;
import cutscenes.DialogueBoxPsych;
import cutscenes.DialogueBoxPsych.DialogueFile;
import objects.Note;
import objects.VideoSprite;
import substates.GameOverSubstate;
import scripting.ScriptHooks;
#if sys
import sys.FileSystem;
#end
import openfl.utils.Assets as OpenFlAssets;

/**
	The things that happen around a song rather than during it: a video, a dialogue box, the
	countdown before the first note.

	None of this runs per frame. Each is a one-shot with a long tail of setup -- `startVideo` alone
	juggles precached players, mid-song versus cutscene mode, skip callbacks and the song resync
	afterwards -- which is why it reads badly next to the input loop it used to sit beside.

	State stays on `PlayState` (`videoCutscene`, `precachedVideos` and the countdown sprites are all
	read by scripts), reached here through `game` under `@:allow(states.play)`.
**/
class CutsceneRunner {
	final game:PlayState;

	public function new(game:PlayState) {
		this.game = game;
	}

	public function startVideo(name:String, forMidSong:Bool = false, canSkip:Bool = true, loop:Bool = false, playOnLoad:Bool = true) {
		#if VIDEOS_ALLOWED
		game.inCutscene = !forMidSong;
		game.canPause = forMidSong;

		var foundFile:Bool = false;
		var fileName:String = Paths.video(name);

		#if sys
		if (FileSystem.exists(fileName))
		#else
		if (OpenFlAssets.exists(fileName))
		#end
		foundFile = true;

		if (foundFile) {
			// Only one video plays at a time, and `videoCutscene` is the only handle to it. Starting a
			// second while one runs used to overwrite that handle, leaving the first added to the state
			// and still decoding with nothing able to reach, skip or free it. Two Video Player events
			// close together is all it takes.
			if (game.videoCutscene != null) {
				game.videoCutscene.destroy();
				game.videoCutscene = null;
			}

			var reused:VideoSprite = game.precachedVideos.get(name);
			if (reused != null) {
				game.precachedVideos.remove(name);
				// The warmed copy is only valid if the load-time options match; otherwise rebuild.
				if (reused.waiting != forMidSong || reused.looping != loop) {
					reused.destroy();
					reused = null;
				}
			}

			game.videoCutscene = reused != null ? reused : new VideoSprite(fileName, forMidSong, canSkip, loop);
			game.videoCutscene.canSkip = canSkip;
			if (forMidSong)
				game.videoCutscene.videoSprite.bitmap.rate = game.playbackRate;

			// Finish callback
			if (!forMidSong) {
				function onVideoEnd() {
					if (!game.isDead
						&& game.generatedMusic
						&& PlayState.SONG.notes[Std.int(game.curStep / 16)] != null
						&& !game.endingSong
						&& !game.isCameraOnForcedPos) {
						game.moveCameraSection();
						FlxG.camera.snapToTarget();
					}
					game.videoCutscene = null;
					game.canPause = true;
					game.inCutscene = false;
					startAndEnd();
				}
				game.videoCutscene.finishCallback = onVideoEnd;
				game.videoCutscene.onSkip = onVideoEnd;
			}
			if (GameOverSubstate.instance != null && game.isDead)
				GameOverSubstate.instance.add(game.videoCutscene);
			else
				game.add(game.videoCutscene);

			if (playOnLoad)
				game.videoCutscene.play();
			return game.videoCutscene;
		}
		#if (LUA_ALLOWED || HSCRIPT_ALLOWED)
		else
			game.addTextToDebug("Video not found: " + fileName, FlxColor.RED);
		#else
		else
			FlxG.log.error("Video not found: " + fileName);
		#end
		#else
		FlxG.log.warn('Platform not supported!');
		startAndEnd();
		#end
		return null;
	}

	/**
	 * Warms a video ahead of time so the matching `startVideo` starts without the open/decode hitch.
	 * Pass the same `forMidSong`/`canSkip`/`loop` you'll later hand to `startVideo`; a mismatch on
	 * `forMidSong` or `loop` (which are baked in at load time) discards the warmed copy and rebuilds.
	 */
	public function precacheVideo(name:String, forMidSong:Bool = false, canSkip:Bool = true, loop:Bool = false):Void {
		#if VIDEOS_ALLOWED
		if (game.precachedVideos.exists(name))
			return;

		final fileName:String = Paths.video(name);
		#if sys
		if (!FileSystem.exists(fileName))
		#else
		if (!OpenFlAssets.exists(fileName))
		#end
			return;

		game.precachedVideos.set(name, new VideoSprite(fileName, forMidSong, canSkip, loop, true));
		#end
	}

	public function startAndEnd() {
		if (game.endingSong)
			game.endSong();
		else
			game.startCountdown();
	}

	// You don't have to add a song, just saying. You can just do "startDialogue(DialogueBoxPsych.parseDialogue(Paths.json(songName + '/dialogue')))" and it should load dialogue.json
	public function startDialogue(dialogueFile:DialogueFile, ?song:String = null):Void {
		// TO DO: Make this more flexible, maybe?
		if (game.psychDialogue != null)
			return;

		if (dialogueFile.dialogue.length > 0) {
			game.inCutscene = true;
			game.psychDialogue = new DialogueBoxPsych(dialogueFile, song);
			game.psychDialogue.scrollFactor.set();
			if (game.endingSong) {
				game.psychDialogue.finishThing = function() {
					game.psychDialogue = null;
					game.endSong();
				}
			} else {
				game.psychDialogue.finishThing = function() {
					game.psychDialogue = null;
					game.startCountdown();
				}
			}
			game.psychDialogue.nextDialogueThing = startNextDialogue;
			game.psychDialogue.skipDialogueThing = skipDialogue;
			game.psychDialogue.cameras = [game.camHUD];
			game.add(game.psychDialogue);
		} else {
			FlxG.log.warn('Your dialogue file is badly formatted!');
			startAndEnd();
		}
	}

	public function startNextDialogue() {
		game.dialogueCount++;
		game.callOnScripts(ScriptHooks.NEXT_DIALOGUE, [game.dialogueCount]);
	}

	public function skipDialogue() {
		game.callOnScripts(ScriptHooks.SKIP_DIALOGUE, [game.dialogueCount]);
	}

	/**
		The countdown itself: the five ticks, the ready/set/go art, the sounds and the note fade-in.

		Presentation only. Everything around it -- building the note fields, arming the replay
		recorder, starting the conductor -- is song lifecycle and stays on `PlayState`, which calls
		this once it has decided a countdown should actually be shown.
	**/
	public function runCountdown():Void {
		var swagCounter:Int = 0;
		game.startTimer = new FlxTimer().start(Conductor.crochet / 1000 / game.playbackRate, function(tmr:FlxTimer) {
			game.characterBopper(tmr.loopsLeft);

			var introAssets:Map<String, Array<String>> = new Map<String, Array<String>>();
			var introImagesArray:Array<String> = switch (PlayState.stageUI) {
				// The engine's pixel countdown art moved into the Default skin's `pixel/` folder; these
				// are only the last resort for when the skin chain resolves nothing.
				case "pixel": ['uiSkins/Default/pixel/ready', 'uiSkins/Default/pixel/set', 'uiSkins/Default/pixel/go'];
				case "normal": ["ready", "set", "go"];
				default: [
						'${PlayState.uiPrefix}UI/ready${PlayState.uiPostfix}',
						'${PlayState.uiPrefix}UI/set${PlayState.uiPostfix}',
						'${PlayState.uiPrefix}UI/go${PlayState.uiPostfix}'
					];
			}
			introAssets.set(PlayState.stageUI, introImagesArray);

			var introAlts:Array<String> = introAssets.get(PlayState.stageUI);
			var antialias:Bool = (ClientPrefs.data.antialiasing && !PlayState.isPixelStage);
			var tick:Countdown = THREE;

			switch (swagCounter) {
				case 0:
					FlxG.sound.play(Paths.sound('intro3' + game.introSoundsSuffix), 0.6);
					tick = THREE;
				case 1:
					game.countdownReady = createCountdownSprite(introAlts[0], antialias, 'ready');
					FlxG.sound.play(Paths.sound('intro2' + game.introSoundsSuffix), 0.6);
					tick = TWO;
				case 2:
					game.countdownSet = createCountdownSprite(introAlts[1], antialias, 'set');
					FlxG.sound.play(Paths.sound('intro1' + game.introSoundsSuffix), 0.6);
					tick = ONE;
				case 3:
					game.countdownGo = createCountdownSprite(introAlts[2], antialias, 'go');
					FlxG.sound.play(Paths.sound('introGo' + game.introSoundsSuffix), 0.6);
					tick = GO;
				case 4:
					tick = START;
			}

			if (!game.skipArrowStartTween) {
				game.notes.forEachAlive(function(note:Note) {
					if (ClientPrefs.data.opponentStrums || note.mustPress) {
						note.copyAlpha = false;
						note.alpha = note.multAlpha;
						if (ClientPrefs.data.middleScroll && !note.mustPress)
							note.alpha *= 0.35;
					}
				});
			}

			game.stagesFunc(function(stage:BaseStage) stage.countdownTick(tick, swagCounter));
			game.callOnLuas(ScriptHooks.COUNTDOWN_TICK, [swagCounter]);
			game.callOnHScript(ScriptHooks.COUNTDOWN_TICK, [tick, swagCounter]);

			swagCounter += 1;
		}, 5);
	}

	public function cacheCountdown() {
		var introAssets:Map<String, Array<String>> = new Map<String, Array<String>>();
		var introImagesArray:Array<String> = switch (PlayState.stageUI) {
			// The engine's pixel countdown art moved into the Default skin's `pixel/` folder; these are
			// only the last resort for when the skin chain resolves nothing.
			case "pixel": ['uiSkins/Default/pixel/ready', 'uiSkins/Default/pixel/set', 'uiSkins/Default/pixel/go'];
			case "normal": ["ready", "set", "go"];
			default: [
					'${PlayState.uiPrefix}UI/ready${PlayState.uiPostfix}',
					'${PlayState.uiPrefix}UI/set${PlayState.uiPostfix}',
					'${PlayState.uiPrefix}UI/go${PlayState.uiPostfix}'
				];
		}
		introAssets.set(PlayState.stageUI, introImagesArray);
		var introAlts:Array<String> = introAssets.get(PlayState.stageUI);
		for (asset in introAlts)
			Paths.image(asset);

		// UI Skin: warm the active skin's countdown images (no-op when the pref has no folder skin).
		for (logical in ['ready', 'set', 'go'])
			UISkinConfig.image(logical);

		Paths.sound('intro3' + game.introSoundsSuffix);
		Paths.sound('intro2' + game.introSoundsSuffix);
		Paths.sound('intro1' + game.introSoundsSuffix);
		Paths.sound('introGo' + game.introSoundsSuffix);
	}

	inline private function createCountdownSprite(image:String, antialias:Bool, ?logical:String):FlxSprite {
		var spr:FlxSprite = new FlxSprite();
		// The skin provider picks the tier: a folder or classic skin's ready/set/go if it ships one,
		// otherwise the base stageUI asset. `image` stays the path for a caller that named one directly.
		var look:backend.uiskin.UIVisual = null;
		if (logical != null)
			look = backend.uiskin.UISkinService.current().applyCountdown(spr, logical);
		if (look == null || !look.ok)
			spr.loadGraphic(Paths.image(image));
		spr.cameras = [game.camHUD];
		spr.scrollFactor.set();
		spr.updateHitbox();

		if (PlayState.isPixelStage)
			spr.setGraphicSize(Std.int(spr.width * PlayState.daPixelZoom));
		else if (look != null && look.ok && look.factor != 1)
			spr.setGraphicSize(Std.int(spr.width * look.factor));

		spr.screenCenter();
		spr.antialiasing = antialias;
		game.insert(game.members.indexOf(game.noteGroup), spr);
		FlxTween.tween(spr, {/*y: spr.y + 100,*/ alpha: 0}, Conductor.crochet / 1000, {
			ease: FlxEase.cubeInOut,
			onComplete: function(twn:FlxTween) {
				game.remove(spr);

				// Or a script reaching it later gets a destroyed sprite instead of nothing.
				switch (logical) {
					case 'ready':
						if (game.countdownReady == spr)
							game.countdownReady = null;
					case 'set':
						if (game.countdownSet == spr)
							game.countdownSet = null;
					case 'go':
						if (game.countdownGo == spr)
							game.countdownGo = null;
					default:
				}

				spr.destroy();
			}
		});
		return spr;
	}
}
