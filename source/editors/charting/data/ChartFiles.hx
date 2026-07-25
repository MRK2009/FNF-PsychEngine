package editors.charting.data;

import backend.Song;
import backend.SongChart;
import backend.SongMeta.SongMetaInfo;
import backend.SongPaths;
import editors.content.PsychJsonPrinter;
#if sys
import sys.FileSystem;
import sys.io.File;
#end

/**
	The song package files that sit around a chart file: the chart itself, plus the events and metadata
	sidecars beside it. Both chart editors go through this, so a package round-trips the same way on
	desktop and on mobile.

	Events are normally carried inside the chart. A package that keeps them in their own
	`events[-difficulty].json` keeps doing so: the sidecar is folded into the chart on load (marking the
	chart so the runtime doesn't load it a second time) and written back out on save, with the chart file
	itself left free of them so nothing double-fires.
**/
class ChartFiles {
	/**
		The folder a chart file lives in.
		@param chartPath the chart file path
		@return the directory, or null when the path has none
	**/
	public static function folderOf(chartPath:String):Null<String> {
		if (chartPath == null || chartPath.length == 0)
			return null;
		var clean:String = chartPath.replace('\\', '/');
		var slash:Int = clean.lastIndexOf('/');
		return (slash > 0) ? clean.substr(0, slash) : null;
	}

	/**
		An existing sidecar for a role beside a chart file, the difficulty's own file first.
		@param chartPath the chart file path
		@param role the file role (`SongPaths.EVENTS`, `SongPaths.METADATA`, ...)
		@param diffName the difficulty in scope
		@return the sidecar path, or null when the package has none
	**/
	public static function sidecar(chartPath:String, role:String, diffName:String):Null<String> {
		#if sys
		var dir:String = folderOf(chartPath);
		if (dir == null)
			return null;
		var specific:String = '$dir/$role${SongPaths.difficultySuffix(diffName)}.json';
		if (FileSystem.exists(specific))
			return specific;
		var wide:String = '$dir/$role.json';
		return FileSystem.exists(wide) ? wide : null;
		#else
		return null;
		#end
	}

	/**
		The metadata file a save should write beside a chart: the difficulty's own when it already has one,
		else the package-wide file.
		@param chartPath the chart file path
		@param diffName the difficulty in scope
		@return the metadata path, or null when the chart has no folder
	**/
	public static function metadataTarget(chartPath:String, diffName:String):Null<String> {
		var existing:String = sidecar(chartPath, SongPaths.METADATA, diffName);
		if (existing != null)
			return existing;
		var dir:String = folderOf(chartPath);
		return (dir != null) ? '$dir/${SongPaths.METADATA}.json' : null;
	}

	/**
		Folds a package's standalone events into a chart so the editor can edit them, marking the chart so
		the runtime doesn't load the same file again on top.
		@param chart the loaded chart
		@param chartPath the file it came from
		@param diffName the difficulty in scope
		@return the sidecar the events came from, or null when the package keeps them in the chart
	**/
	public static function adoptEvents(chart:SongChart, chartPath:String, diffName:String):Null<String> {
		#if sys
		if (chart == null || chart.eventsMerged)
			return null;
		var path:String = sidecar(chartPath, SongPaths.EVENTS, diffName);
		if (path == null)
			return null;

		try {
			var loaded:SongChart = Song.parseJSON(File.getContent(path), path);
			if (loaded != null && loaded.events != null) {
				if (chart.events == null)
					chart.events = [];
				for (event in loaded.events)
					chart.events.push(event);
			}
			chart.eventsMerged = true;
			return path;
		} catch (e:Dynamic) {
			trace('ChartFiles.adoptEvents failed for "$path": $e');
			return null;
		}
		#else
		return null;
		#end
	}

	/**
		Serializes a chart as psych_v2.
		@param chart the chart to write
		@param eventsInSidecar true when the package keeps events in their own file, which drops them from
			the chart so they can't be loaded twice
		@return the json text
	**/
	public static function chartJson(chart:SongChart, eventsInSidecar:Bool):String {
		var obj:Dynamic = Song.buildPsychV2(cast chart, chart);
		if (eventsInSidecar)
			Reflect.deleteField(obj, 'events');
		return PsychJsonPrinter.print(obj, Song.PSYCH_V2_INLINE, Song.PSYCH_V2_KEY_ORDER);
	}

	/**
		Writes a chart's events to their sidecar, in the psych_v2 object form the loader reads back.
		@param path the sidecar path
		@param chart the chart holding the events
	**/
	public static function writeEvents(path:String, chart:SongChart):Void {
		#if sys
		var obj:Dynamic = {format: 'psych_v2', events: Song.eventsToV2(chart.events)};
		File.saveContent(path, PsychJsonPrinter.print(obj, Song.PSYCH_V2_INLINE, Song.PSYCH_V2_KEY_ORDER));
		#end
	}

	/**
		Writes song metadata, dropping the fields left empty so the file stays minimal.
		@param path the metadata path
		@param meta the metadata to write
	**/
	public static function writeMetadata(path:String, meta:SongMetaInfo):Void {
		#if sys
		for (field in ['songName', 'artist', 'charter', 'source']) {
			var value:Dynamic = Reflect.field(meta, field);
			if (value == null || Std.string(value).length < 1)
				Reflect.deleteField(meta, field);
		}
		if (meta.tags != null && meta.tags.length < 1)
			Reflect.deleteField(meta, 'tags');
		File.saveContent(path, haxe.Json.stringify(meta, null, '\t'));
		#end
	}

	/**
		Re-points a sidecar at the folder a chart was just saved into, so a Save As carries the package's
		files along with it.
		@param sidecarPath the sidecar's previous path
		@param chartPath the chart's new path
		@return the sidecar path beside the chart
	**/
	public static function beside(sidecarPath:String, chartPath:String):String {
		var dir:String = folderOf(chartPath);
		if (dir == null || sidecarPath == null)
			return sidecarPath;
		var clean:String = sidecarPath.replace('\\', '/');
		var slash:Int = clean.lastIndexOf('/');
		return '$dir/' + ((slash >= 0) ? clean.substr(slash + 1) : clean);
	}
}
