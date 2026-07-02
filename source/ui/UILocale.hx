package ui;

/**
	Pluggable translation hook. The host application assigns `translate` to its own
	localization lookup; the library itself stays dependency-free and falls back to the
	supplied default string. Call `refresh()` after a locale switch to re-render live widgets.
**/
final class UILocale {
	/** `(key, fallback) -> localized`. `null` = identity (fallback returned). **/
	public static var translate:(key:String, fallback:String) -> String = null;

	/** Fired by `refresh()`; `UIRoot` assigns this to re-render every widget. **/
	public static var onChanged:Void->Void = null;

	/**
		Resolves a localized string through the host's `translate` hook.
		@param key the translation key
		@param fallback returned verbatim when no hook is assigned (also the source string)
		@return the localized text
	**/
	public static inline function t(key:String, fallback:String):String {
		return (translate != null) ? translate(key, fallback) : fallback;
	}

	/** Notifies live widgets that the locale changed (re-renders every `UIComponent`). **/
	public static function refresh():Void {
		if (onChanged != null)
			onChanged();
	}
}
