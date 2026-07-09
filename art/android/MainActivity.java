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
