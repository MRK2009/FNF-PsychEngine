package ::APP_PACKAGE::;

import android.content.Intent;
import android.content.pm.PackageInstaller;
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

	// Display-cutout insets in device pixels, read from Haxe by mobile.backend.SafeArea. Cached here
	// because getRootWindowInsets is UI-thread-only, and the render thread is what needs them.
	public static volatile int safeLeft = 0;
	public static volatile int safeTop = 0;
	public static volatile int safeRight = 0;
	public static volatile int safeBottom = 0;

	// Largest rounded-corner radius, kept separate from the cutout: it only clips content in a
	// corner, so folding it into all four insets would cost every edge a radius it doesn't need.
	public static volatile int cornerRadius = 0;

	// Insets change with rotation and with the multi-window/cutout mode, and the first layout pass
	// may land after onAttachedToWindow, so listen rather than sample once.
	@Override public void onAttachedToWindow () {

		super.onAttachedToWindow ();

		if (android.os.Build.VERSION.SDK_INT < 28) return;

		try {

			final android.view.View decor = getWindow ().getDecorView ();

			decor.setOnApplyWindowInsetsListener (new android.view.View.OnApplyWindowInsetsListener () {

				public android.view.WindowInsets onApplyWindowInsets (android.view.View view, android.view.WindowInsets insets) {

					captureSafeInsets (insets);
					return view.onApplyWindowInsets (insets);

				}

			});

			decor.post (new Runnable () { public void run () {

				captureSafeInsets (decor.getRootWindowInsets ());

			}});

		} catch (Throwable t) {}

	}

	private static void captureSafeInsets (final android.view.WindowInsets insets) {

		if (insets == null) return;

		try {

			android.view.DisplayCutout cutout = insets.getDisplayCutout ();

			if (cutout != null) {

				safeLeft = cutout.getSafeInsetLeft ();
				safeTop = cutout.getSafeInsetTop ();
				safeRight = cutout.getSafeInsetRight ();
				safeBottom = cutout.getSafeInsetBottom ();

			} else {

				safeLeft = safeTop = safeRight = safeBottom = 0;

			}

			if (android.os.Build.VERSION.SDK_INT >= 31) {

				cornerRadius = Math.max (
					Math.max (cornerRadius (insets, android.view.RoundedCorner.POSITION_TOP_LEFT),
						cornerRadius (insets, android.view.RoundedCorner.POSITION_TOP_RIGHT)),
					Math.max (cornerRadius (insets, android.view.RoundedCorner.POSITION_BOTTOM_LEFT),
						cornerRadius (insets, android.view.RoundedCorner.POSITION_BOTTOM_RIGHT)));

			}

		} catch (Throwable t) {}

	}

	private static int cornerRadius (final android.view.WindowInsets insets, final int position) {

		android.view.RoundedCorner corner = insets.getRoundedCorner (position);
		return corner == null ? 0 : corner.getRadius ();

	}

	// Self-update: streams a downloaded release APK into a PackageInstaller session and commits it.
	// Android can't hot-swap its own running APK, so mobile.backend.UpdateInstaller downloads the
	// APK and calls this. Uses the framework PackageInstaller (no androidx/FileProvider dependency);
	// the confirm UI is launched from onNewIntent when the session reports PENDING_USER_ACTION.
	// Requires the REQUEST_INSTALL_PACKAGES permission.
	public static void installApk (final String path) {

		final android.app.Activity activity = org.haxe.extension.Extension.mainActivity;
		if (activity == null || path == null) return;

		activity.runOnUiThread (new Runnable () { public void run () {

			PackageInstaller.Session session = null;

			try {

				java.io.File apk = new java.io.File (path);
				PackageInstaller installer = activity.getPackageManager ().getPackageInstaller ();
				PackageInstaller.SessionParams params = new PackageInstaller.SessionParams (PackageInstaller.SessionParams.MODE_FULL_INSTALL);

				int sessionId = installer.createSession (params);
				session = installer.openSession (sessionId);

				java.io.OutputStream out = session.openWrite ("psych_update", 0, apk.length ());
				java.io.InputStream in = new java.io.FileInputStream (apk);
				byte[] buffer = new byte[65536];
				int read;
				while ((read = in.read (buffer)) > 0) out.write (buffer, 0, read);
				session.fsync (out);
				in.close ();
				out.close ();

				Intent statusIntent = new Intent (activity, MainActivity.class);
				int flags = android.os.Build.VERSION.SDK_INT >= 31 ? android.app.PendingIntent.FLAG_MUTABLE : 0;
				android.app.PendingIntent pending = android.app.PendingIntent.getActivity (activity, sessionId, statusIntent, flags);
				session.commit (pending.getIntentSender ());
				session.close ();

			} catch (Throwable t) {

				android.util.Log.e ("PsychEngine", "installApk failed", t);
				if (session != null) session.abandon ();

			}

		}});

	}

	// The PackageInstaller session reports its result back to this activity; when it needs the user
	// to confirm (the normal non-privileged case), launch the confirmation UI it hands us.
	@Override protected void onNewIntent (Intent intent) {

		super.onNewIntent (intent);

		if (intent != null && intent.hasExtra (PackageInstaller.EXTRA_STATUS)) {

			int status = intent.getIntExtra (PackageInstaller.EXTRA_STATUS, -1);
			if (status == PackageInstaller.STATUS_PENDING_USER_ACTION) {

				Intent confirm = (Intent) intent.getParcelableExtra (Intent.EXTRA_INTENT);
				if (confirm != null) {

					confirm.addFlags (Intent.FLAG_ACTIVITY_NEW_TASK);
					startActivity (confirm);

				}

			}

		}

	}

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
