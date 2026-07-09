package ::APP_PACKAGE::;

import android.view.InputDevice;
import android.view.KeyEvent;

/**
 * Intercepts the system Back button/gesture at the activity level.
 *
 * SDL's key-event path (SDLSurface -> native -> lime -> flixel) silently drops
 * system-injected key events on some builds, so Back is consumed here -- the
 * first stop for the key in the app process -- and exposed to Haxe as a plain
 * counter polled by mobile.backend.BackButton. Gamepad B buttons also arrive
 * as KEYCODE_BACK on some controllers; those are left to SDL's gamepad path.
 */
public class MainActivity extends org.haxe.lime.GameActivity {

	public static volatile int backCount = 0;

	// Game Mode API loading hint (API 33+): lets the OS boost CPU during load screens.
	// Called from Haxe via mobile.backend.GameModeUtil.setLoading.
	public static void setGameState (final boolean isLoading) {

		if (android.os.Build.VERSION.SDK_INT < 33) return;

		try {

			android.app.GameManager manager = (android.app.GameManager)
				org.libsdl.app.SDL.getContext ().getSystemService (android.content.Context.GAME_SERVICE);

			if (manager != null) {

				manager.setGameState (isLoading
					? new android.app.GameState (true, android.app.GameState.MODE_NONE)
					: new android.app.GameState (false, android.app.GameState.MODE_GAMEPLAY_INTERRUPTIBLE));

			}

		} catch (Throwable t) {}

	}

	// Pins the display to a refresh rate at the current resolution: the closest mode not
	// exceeding targetHz, or the highest available when targetHz <= 0 (falls back to the
	// lowest mode when nothing fits, e.g. targetHz=60 on a 90Hz-only panel). Called from
	// Haxe via mobile.backend.GameModeUtil.applyDisplayPolicy.
	public static void setDisplayRefreshRate (final int targetHz) {

		if (android.os.Build.VERSION.SDK_INT < 23) return;

		final android.app.Activity activity = org.haxe.extension.Extension.mainActivity;
		if (activity == null) return;

		activity.runOnUiThread (new Runnable () { public void run () {

			try {

				android.view.Display display = activity.getWindowManager ().getDefaultDisplay ();
				android.view.Display.Mode current = display.getMode ();
				android.view.Display.Mode best = null;
				android.view.Display.Mode lowest = null;

				for (android.view.Display.Mode mode : display.getSupportedModes ()) {

					if (mode.getPhysicalWidth () != current.getPhysicalWidth ()
						|| mode.getPhysicalHeight () != current.getPhysicalHeight ()) continue;

					if (lowest == null || mode.getRefreshRate () < lowest.getRefreshRate ()) lowest = mode;

					if (targetHz > 0) {

						if (mode.getRefreshRate () <= targetHz + 0.5f
							&& (best == null || mode.getRefreshRate () > best.getRefreshRate ())) best = mode;

					} else {

						if (best == null || mode.getRefreshRate () > best.getRefreshRate ()) best = mode;

					}

				}

				if (best == null) best = lowest;
				if (best == null) return;

				android.view.WindowManager.LayoutParams params = activity.getWindow ().getAttributes ();
				params.preferredDisplayModeId = best.getModeId ();
				activity.getWindow ().setAttributes (params);

			} catch (Throwable t) {}

		}});

	}

	@Override public boolean dispatchKeyEvent (KeyEvent event) {

		if (event.getKeyCode () == KeyEvent.KEYCODE_BACK) {

			int source = event.getSource ();
			boolean fromController = (source & InputDevice.SOURCE_GAMEPAD) == InputDevice.SOURCE_GAMEPAD
				|| (source & InputDevice.SOURCE_JOYSTICK) == InputDevice.SOURCE_JOYSTICK;

			if (!fromController) {

				if (event.getAction () == KeyEvent.ACTION_UP) {

					backCount++;

				}

				return true;

			}

		}

		return super.dispatchKeyEvent (event);

	}

}
