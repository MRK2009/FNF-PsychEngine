package mobile.backend;

#if android
import extension.androidtools.jni.JNICache;
import lime.system.JNI.JNIStaticField;
#end

/**
 * Android's system file picker (Storage Access Framework), for opening and saving TEXT documents
 * anywhere the user can browse -- Downloads, Drive, other apps' storage.
 *
 * The picker runs in the activity (art/android/MainActivity.java) because documents arrive as
 * content:// URIs only the ContentResolver can read; results come back through polled statics,
 * like `BackButton`. `poll()` is wired to `FlxG.signals.preUpdate` in Main. One operation at a
 * time; a second request while `busy` is refused.
 */
class DocumentPicker {
	public static var busy(default, null):Bool = false;

	#if android
	static var onDone:Null<(name:String, data:String) -> Void>;
	static var onFail:Null<Void->Void>;

	static var fieldCounter:Null<JNIStaticField>;
	static var fieldStatus:Null<JNIStaticField>;
	static var fieldName:Null<JNIStaticField>;
	static var fieldData:Null<JNIStaticField>;
	static var callOpen:Null<Dynamic>;
	static var callCreate:Null<Dynamic>;
	static var lastCounter:Int = 0;
	static var resolved:Bool = false;

	static function resolve():Bool {
		if (!resolved) {
			resolved = true;
			try {
				final packageName:String = lime.app.Application.current.meta.get('packageName');
				final activity:String = '$packageName.MainActivity';
				fieldCounter = JNICache.createStaticField(activity, 'safCounter', 'I');
				fieldStatus = JNICache.createStaticField(activity, 'safStatus', 'I');
				fieldName = JNICache.createStaticField(activity, 'safName', 'Ljava/lang/String;');
				fieldData = JNICache.createStaticField(activity, 'safData', 'Ljava/lang/String;');
				callOpen = JNICache.createStaticMethod(activity, 'openDocument', '(Ljava/lang/String;)V');
				callCreate = JNICache.createStaticMethod(activity, 'createDocument', '(Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;)V');
				lastCounter = fieldCounter.get();
			} catch (e:Dynamic) {
				trace('DocumentPicker: failed to resolve MainActivity SAF bridge: $e');
				fieldCounter = null;
			}
		}
		return fieldCounter != null;
	}

	/** Shows the system open dialog; `done(displayName, contents)` on success, `fail()` otherwise. **/
	public static function openText(mimeType:String, done:(name:String, data:String) -> Void, ?fail:Void->Void):Void {
		if (busy || !resolve()) {
			if (fail != null)
				fail();
			return;
		}
		busy = true;
		onDone = done;
		onFail = fail;
		callOpen(mimeType);
	}

	/** Shows the system save dialog and writes `data`; `done(displayName, "")` on success. **/
	public static function saveText(suggestedName:String, mimeType:String, data:String, done:(name:String, data:String) -> Void,
			?fail:Void->Void):Void {
		if (busy || !resolve()) {
			if (fail != null)
				fail();
			return;
		}
		busy = true;
		onDone = done;
		onFail = fail;
		callCreate(suggestedName, mimeType, data);
	}

	/** Delivers a finished operation's callbacks. Wired to `FlxG.signals.preUpdate` in Main. **/
	public static function poll():Void {
		if (!busy || fieldCounter == null)
			return;
		final counter:Int = fieldCounter.get();
		if (counter == lastCounter)
			return;
		lastCounter = counter;
		busy = false;

		final done = onDone;
		final fail = onFail;
		onDone = null;
		onFail = null;

		if (fieldStatus.get() == 1) {
			if (done != null)
				done(Std.string(fieldName.get()), Std.string(fieldData.get()));
		} else if (fail != null)
			fail();
	}
	#else
	public static inline function poll():Void {}
	#end
}
