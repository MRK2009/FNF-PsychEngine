package;

#if mobile
import mobile.backend.StorageUtil;
#end
#if android
import extension.haptics.Haptic;
#end
import debug.FPSCounter;
import flixel.graphics.FlxGraphic;
import flixel.FlxGame;
import flixel.FlxState;
import haxe.io.Path;
import openfl.Assets;
import openfl.Lib;
import openfl.display.Sprite;
import openfl.events.Event;
import openfl.display.StageScaleMode;
import states.TitleState;
#if (linux || mac)
import lime.graphics.Image;
#end
#if desktop
import backend.ALSoftConfig;
#end
import backend.Highscore;
import backend.FullScreenScaleMode;

// NATIVE API STUFF, YOU CAN IGNORE THIS AND SCROLL //
#if (linux && !debug)
@:cppInclude('./external/gamemode_client.h')
@:cppFileCode('#define GAMEMODE_AUTO')
#end
// // // // // // // // //
class Main extends Sprite {
	public static final game = {
		width: 1280, // WINDOW width
		height: 720, // WINDOW height
		initialState: TitleState, // initial game state
		framerate: 60, // default framerate
		skipSplash: true, // if the default flixel splash screen should be skipped
		startFullscreen: false // if the game should start at fullscreen mode
	};

	public static var fpsVar:FPSCounter;

	// You can pretty much ignore everything from here on - your code should go in your states.

	public static function main():Void {
		#if (CHECK_FOR_UPDATES && sys && windows)
		backend.updater.UpdateInstaller.applyPendingOnBoot();
		#end
		Lib.current.addChild(new Main());
	}

	public function new() {
		super();

		#if (cpp && windows)
		backend.Native.fixScaling();
		// Match the title bar to the user's Windows color scheme, and keep it in sync if they change it.
		backend.Native.applyWindowTheme();
		FlxG.signals.focusGained.add(backend.Native.applyWindowTheme);
		#end

		// Mobile storage: point the engine at a public, file-manager-browsable folder
		// (/storage/emulated/0/PsychEngine) so users can add mods/read saves freely.
		// Credits to MAJigsaw77 (he's the og author for the original android code)
		#if mobile
		#if android
		StorageUtil.requestPermissions();
		Haptic.initialize();
		#end
		StorageUtil.prepareDirectories();
		if (StorageUtil.ready)
			Sys.setCwd(StorageUtil.getStorageDirectory());
		#end
		#if VIDEOS_ALLOWED
		hxvlc.util.Handle.init(#if (hxvlc >= "1.8.0") ['--no-lua'] #end);
		#end

		#if LUA_ALLOWED
		Mods.pushGlobalMods();
		#end
		Mods.loadTopMod();

		FlxG.save.bind('funkin', CoolUtil.getSavePath());
		Highscore.load();

		// Write the OpenAL-Soft latency config from the saved `audioBuffer` preference. Must run after
		// the save is bound (to read it) and before the FlxGame below opens the audio device.
		backend.ALSoftConfig.apply();

		// HScript error/warn/fatal logging is handled by psychlua.HScript's
		// static loggers (they mirror messages to the in-game debug overlay).
		#if HSCRIPT_ALLOWED
		psychlua.HScript.setupConfig();
		#end

		Controls.instance = new Controls();
		ClientPrefs.loadDefaultKeys();
		flixel.FlxSprite.defaultAntialiasing = ClientPrefs.data.antialiasing;
		#if ACHIEVEMENTS_ALLOWED Achievements.load(); #end
		addChild(new FlxGame(game.width, game.height, game.initialState, game.framerate, game.framerate, game.skipSplash, game.startFullscreen));

		#if android
		// SDL's key path drops system-injected key events on some builds, so Back is
		// consumed at the activity level (art/android/MainActivity.java) and polled
		// into a per-frame flag here instead of going through FlxG.android.
		FlxG.signals.preUpdate.add(mobile.backend.BackButton.poll);
		FlxG.signals.preUpdate.add(mobile.backend.DocumentPicker.poll);
		// All Files Access is granted in a Settings activity that returns focus here, and is the
		// only chance to set storage up without making the user restart. Storage that came up on
		// the first try makes this a no-op.
		FlxG.signals.focusGained.add(onStorageMaybeGranted);
		smidr.UIRoot.onLongPress = (_) -> if (ClientPrefs.data.vibration) Haptic.vibrateOneShot(0.03, 1, 0.4);
		// Game Mode (Battery/Performance) is flipped from the Game Dashboard while we're
		// backgrounded -- re-apply the framerate policy every time focus comes back.
		FlxG.signals.focusGained.add(ClientPrefs.applyFramerate);
		#end

		#if mobile
		// The counter lives in raw stage pixels: scale it to the game's logical 720p so it's readable
		// on high-density screens. Positioned in preGameStart, once SafeArea knows the real insets.
		final fpsScale:Float = Lib.current.stage.stageHeight / 720;
		fpsVar = new FPSCounter(0, 0, 0xFFFFFF);
		fpsVar.scaleX = fpsVar.scaleY = fpsScale;
		#else
		fpsVar = new FPSCounter(10, 3, 0xFFFFFF);
		#end
		addChild(fpsVar);
		fpsVar.visible = DebugPrefs.data.showFPS;
		#if !mobile
		Lib.current.stage.align = "tl";
		Lib.current.stage.scaleMode = StageScaleMode.NO_SCALE;
		#end

		// Widescreen ("no black bars") fill when windowed or on a display wider than 16:9. Off by
		// default on desktop (a 16:9 display renders identically either way); mobile ignores the
		// preference and fills where the device allows it -- see FullScreenScaleMode.set_enabled.
		// Deferred to preGameStart: assigning FlxG.scaleMode fires flixel's setter -> game.onResize(null)
		// -> FlxG.stage.stageWidth, and the stage is still null this early in Main's constructor.
		FlxG.signals.preGameStart.addOnce(function() {
			FlxG.scaleMode = new FullScreenScaleMode(ClientPrefs.data.widescreen);
			#if mobile
			mobile.backend.SafeArea.refresh();
			// SafeArea is in the game's 720-high space, so fpsScale maps it to the stage pixels the
			// counter is positioned in. It sits in a corner, so it clears the radius as well as the cutout.
			fpsVar.x = (Math.max(mobile.backend.SafeArea.left, mobile.backend.SafeArea.cornerRadius) + 10) * fpsScale;
			fpsVar.y = (Math.max(mobile.backend.SafeArea.top, mobile.backend.SafeArea.cornerRadius) + 4) * fpsScale;
			#end
		});

		#if (linux || mac) // fix the app icon not showing up on the Linux Panel / Mac Dock
		var icon = Image.fromFile("icon.png");
		Lib.current.stage.window.setIcon(icon);
		#end

		#if html5
		FlxG.autoPause = false;
		FlxG.mouse.visible = false;
		#end

		FlxG.fixedTimestep = false;
		FlxG.signals.postGameReset.add(() -> FlxG.fixedTimestep = false);
		FlxG.game.focusLostFramerate = 60;
		FlxG.keys.preventDefaultKeys = [TAB];

		#if CRASH_HANDLER
		backend.CrashHandler.init();
		#end

		#if DISCORD_ALLOWED
		DiscordClient.prepare();
		#end

		// shader coords fix
		FlxG.signals.gameResized.add(function(w, h) {
			if (FlxG.cameras != null) {
				for (cam in FlxG.cameras.list) {
					if (cam == null)
						continue;
					// Flixel's camera onResize only re-applies scale; it never grows the camera's logical
					// size. With the widescreen scale mode FlxG.width/height can change on a window resize,
					// so a full-screen camera created before the resize (the live state's) would keep its
					// old size and leave the game view under-filled / wrong aspect. Re-fit it here.
					if ((cam.x == 0 && cam.y == 0) && (cam.width != FlxG.width || cam.height != FlxG.height)) {
						cam.width = FlxG.width;
						cam.height = FlxG.height;
						cam.setScale(cam.scaleX, cam.scaleY);
					}
					if (cam.filters != null)
						resetSpriteCache(cam.flashSprite);
				}
			}

			if (FlxG.game != null)
				resetSpriteCache(FlxG.game);
		});

	
		// Bounds a bulk scan that threw before closing to the state that caused it.
		FlxG.signals.preStateCreate.add(function(_) Paths.resetBulkScan());

		// Scripted-state setup: runs right BEFORE a scripted state's create(), so
		// the state is mod-sandboxed and has a camera even if the script never calls
		// super.create(). A scripted state carries the mod it was loaded from in
		// `scriptOwnerMod` (set by scripting.ScriptedStates).
		FlxG.signals.preStateCreate.add(function(state:flixel.FlxState) {
			#if HSCRIPT_ALLOWED
			// Only SCRIPTED states need this prep (compiled states set up their own
			// camera in super.create()). Detect them by the scriptable bridge base
			// class -- NOT by scriptOwnerMod: a bare-root global script
			// (mods/states/X.hx) has no owning mod but STILL needs a guaranteed
			// camera. Without it, it renders/updates against whatever camera the
			// previous state left -- fine coming from a menu, but a torn-down camera
			// when returned to from gameplay -> update()/draw() null-ref.
			if (state != null && (state is scripting.ScriptedMusicBeatState)) {
				var st:backend.MusicBeatState = cast state;
				#if MODS_ALLOWED
				// Re-establish the mod context for EVERY scripted state -- including
				// bare-root global ones (scriptOwnerMod == null -> '' = no mod, just
				// global mods + shared). This must run for ALL of them, not only
				// mod-owned ones: leaving the previous (gameplay) state's mod context
				// in place left a bare-root menu's interpreter pointing at torn-down
				// global state, so its NEXT update() null-ref'd. Mod-owned states
				// additionally scope to their own folder.
				backend.Mods.currentModDirectory = (st.scriptOwnerMod != null) ? st.scriptOwnerMod : '';
				backend.Mods.pushGlobalMods();
				#end
				// Guarantee a camera before the (possibly super-less) create().
				st.initPsychCamera();
			}
			#end
		});
	}

	#if android
	/**
		Finishes mobile storage setup if the user granted All Files Access after launch.

		The grant happens in a Settings activity, so this is the first moment the engine can act on it.
		Everything downstream of storage has to be redone in the same order `create` does it, since all
		of it ran against a working directory that had no mods folder.
	**/
	static function onStorageMaybeGranted():Void {
		if (!StorageUtil.retryIfPending())
			return;

		#if LUA_ALLOWED
		Mods.pushGlobalMods();
		#end
		Mods.loadTopMod();
		FlxG.save.bind('funkin', CoolUtil.getSavePath());
		Highscore.load();
		#if ACHIEVEMENTS_ALLOWED Achievements.load(); #end
	}
	#end

	static function resetSpriteCache(sprite:Sprite):Void {
		@:privateAccess {
			sprite.__cacheBitmap = null;
			sprite.__cacheBitmapData = null;
		}
	}

}
