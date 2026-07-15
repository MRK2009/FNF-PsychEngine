package editors.content;

import openfl.net.FileReference;
import openfl.events.Event;
import openfl.events.IOErrorEvent;
import flash.net.FileFilter;
import haxe.Exception;
import sys.io.File;
import lime.ui.*;
import flixel.FlxBasic;

// Currently only supports OPEN and SAVE, might change that in the future, who knows
class FileDialogHandler extends FlxBasic {
	var _fileRef:FileReferenceCustom;
	var _dialogMode:FileDialogType = OPEN;

	public function new() {
		_fileRef = new FileReferenceCustom();
		_fileRef.addEventListener(Event.CANCEL, onCancelFn);
		_fileRef.addEventListener(IOErrorEvent.IO_ERROR, onErrorFn);

		super();
	}

	// callbacks
	public var onComplete:Void->Void;
	public var onCancel:Void->Void;
	public var onError:Void->Void;

	var _currentEvent:openfl.events.Event->Void;

	#if (mobile && !android)
	// lime has no mobile FileDialog backend and FileReference.save is a no-op there;
	// bail before _startUp so `completed` stays true and the editor never locks up.
	function unsupported(onCancel:Void->Void):Void {
		flixel.FlxG.log.warn('File dialogs are not supported on mobile.');
		if (onCancel != null)
			onCancel();
	}
	#end

	public function save(?fileName:String = '', ?dataToSave:String = '', ?onComplete:Void->Void, ?onCancel:Void->Void, ?onError:Void->Void) {
		#if android
		// SAF: the system picker writes through the ContentResolver. `path` carries only the
		// document's display name -- content:// documents have no filesystem path.
		if (!completed)
			throw new Exception('You must finish previous operation before starting a new one.');
		_startUp(onComplete, onCancel, onError);
		mobile.backend.DocumentPicker.saveText(fileName, mimeFor(fileName), dataToSave, function(name:String, _:String):Void {
			this.path = name;
			this.completed = true;
			if (this.onComplete != null)
				this.onComplete();
		}, function():Void {
			this.completed = true;
			if (this.onCancel != null)
				this.onCancel();
		});
		return;
		#elseif mobile
		unsupported(onCancel);
		return;
		#end
		if (!completed) {
			throw new Exception('You must finish previous operation before starting a new one.');
		}

		this._dialogMode = SAVE;
		_startUp(onComplete, onCancel, onError);

		removeEvents();
		_currentEvent = onSaveComplete;
		_fileRef.addEventListener(#if desktop Event.SELECT #else Event.COMPLETE #end, _currentEvent);
		_fileRef.save(dataToSave, fileName);
	}

	#if android
	static function mimeFor(fileName:String):String {
		return (fileName != null && fileName.endsWith('.json')) ? 'application/json' : 'application/octet-stream';
	}
	#end

	public function open(?defaultName:String = null, ?title:String = null, ?filter:Array<FileFilter> = null, ?onComplete:Void->Void, ?onCancel:Void->Void,
			?onError:Void->Void) {
		#if android
		if (!completed)
			throw new Exception('You must finish previous operation before starting a new one.');
		_startUp(onComplete, onCancel, onError);
		// */* rather than application/json: many file managers tag .json as text/plain or octet-stream,
		// and a strict filter would grey those files out entirely.
		mobile.backend.DocumentPicker.openText('*/*', function(name:String, contents:String):Void {
			this.path = name;
			this.data = contents;
			this.completed = true;
			if (this.onComplete != null)
				this.onComplete();
		}, function():Void {
			this.completed = true;
			if (this.onCancel != null)
				this.onCancel();
		});
		return;
		#elseif mobile
		unsupported(onCancel);
		return;
		#end
		if (!completed) {
			throw new Exception('You must finish previous operation before starting a new one.');
		}

		this._dialogMode = OPEN;
		_startUp(onComplete, onCancel, onError);
		if (filter == null)
			filter = [new FileFilter('JSON', 'json')];
		#if mac
		filter = [];
		#end

		removeEvents();
		_currentEvent = onLoadComplete;
		_fileRef.addEventListener(#if desktop Event.SELECT #else Event.COMPLETE #end, _currentEvent);
		_fileRef.browseEx(OPEN, defaultName, title, filter);
	}

	public function openDirectory(?title:String = null, ?onComplete:Void->Void, ?onCancel:Void->Void, ?onError:Void->Void) {
		#if android
		// SAF tree access (persistable directory grants) is a different beast; not worth it yet.
		flixel.FlxG.log.warn('Directory dialogs are not supported on Android.');
		if (onCancel != null)
			onCancel();
		return;
		#elseif mobile
		unsupported(onCancel);
		return;
		#end
		if (!completed) {
			throw new Exception('You must finish previous operation before starting a new one.');
		}

		this._dialogMode = OPEN_DIRECTORY;
		_startUp(onComplete, onCancel, onError);

		removeEvents();
		_currentEvent = onLoadDirectoryComplete;
		_fileRef.addEventListener(#if desktop Event.SELECT #else Event.COMPLETE #end, _currentEvent);
		_fileRef.browseEx(OPEN_DIRECTORY, null, title);
	}

	public var data:String;
	public var path:String;
	public var completed:Bool = true;

	function onSaveComplete(_) {
		@:privateAccess
		this.path = _fileRef._trackSavedPath;
		this.completed = true;
		trace('Saved file to: $path');

		removeEvents();
		this.completed = true;
		if (onComplete != null)
			onComplete();
	}

	function onLoadComplete(_) {
		@:privateAccess
		this.path = _fileRef.__path;
		this.data = File.getContent(this.path);
		this.completed = true;
		trace('Loaded file from: $path');

		removeEvents();
		this.completed = true;
		if (onComplete != null)
			onComplete();
	}

	function onLoadDirectoryComplete(_) {
		@:privateAccess
		this.path = _fileRef.__path;
		this.completed = true;
		trace('Loaded directory: $path');

		removeEvents();
		this.completed = true;
		if (onComplete != null)
			onComplete();
	}

	function onCancelFn(_) {
		removeEvents();
		this.completed = true;
		if (onCancel != null)
			onCancel();
	}

	function onErrorFn(_) {
		removeEvents();
		this.completed = true;
		if (onError != null)
			onError();
	}

	function _startUp(onComplete:Void->Void, onCancel:Void->Void, onError:Void->Void) {
		this.onComplete = onComplete;
		this.onCancel = onCancel;
		this.onError = onError;
		this.completed = false;

		this.data = null;
		this.path = null;
	}

	function removeEvents() {
		if (_currentEvent == null)
			return;

		_fileRef.removeEventListener(#if desktop Event.SELECT #else Event.COMPLETE #end, _currentEvent);
		_currentEvent = null;
	}

	override function destroy() {
		removeEvents();
		_fileRef = null;
		_currentEvent = null;
		onComplete = null;
		onCancel = null;
		onError = null;
		data = null;
		path = null;
		completed = true;
		super.destroy();
	}
}

// Only way I could find to keep the path after saving a file
class FileReferenceCustom extends FileReference {
	@:allow(backend.FileDialogHandler)
	var _trackSavedPath:String;

	override function saveFileDialog_onSelect(path:String):Void {
		_trackSavedPath = path;
		super.saveFileDialog_onSelect(path);
	}

	public function browseEx(browseType:FileDialogType = OPEN, ?defaultName:String, ?title:String = null, ?typeFilter:Array<FileFilter> = null):Bool {
		__data = null;
		__path = null;

		#if desktop
		var filter = null;

		if (typeFilter != null) {
			var filters = [];

			for (type in typeFilter) {
				filters.push(StringTools.replace(StringTools.replace(type.extension, "*.", ""), ";", ","));
			}

			filter = filters.join(";");
		}

		var openFileDialog = new FileDialog();
		openFileDialog.onCancel.add(openFileDialog_onCancel);
		openFileDialog.onSelect.add(openFileDialog_onSelect);
		openFileDialog.browse(browseType, filter, defaultName, title);
		return true;
		#elseif (js && html5)
		var filter = null;
		if (typeFilter != null) {
			var filters = [];
			for (type in typeFilter) {
				filters.push(StringTools.replace(StringTools.replace(type.extension, "*.", "."), ";", ","));
			}
			filter = filters.join(",");
		}
		if (filter != null) {
			__inputControl.setAttribute("accept", filter);
		}
		__inputControl.onchange = function() {
			var file = __inputControl.files[0];
			modificationDate = Date.fromTime(file.lastModified);
			creationDate = modificationDate;
			size = file.size;
			type = "." + Path.extension(file.name);
			name = Path.withoutDirectory(file.name);
			__path = file.name;
			dispatchEvent(new Event(Event.SELECT));
		}
		__inputControl.click();
		return true;
		#end

		return false;
	}
}
