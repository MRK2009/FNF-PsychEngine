package backend.tools.scriptconvert;

import backend.tools.scriptconvert.ScriptRule;
#if sys
import sys.FileSystem;
import sys.io.File;
#end

using StringTools;

/** One flagged spot in a script: the 1-based line, the rule that fired, and the guidance. **/
typedef ScanIssue = {
	line:Int,
	kind:RuleKind,
	severity:String,
	match:String,
	message:String,
	?suggestion:String
};

/** Result of scanning one script source: the per-line issues plus an annotated copy of the source. **/
typedef ScanReport = {
	issues:Array<ScanIssue>,
	annotated:String
};

/** One scanned file within a folder scan. **/
typedef FileReport = {
	fullPath:String,
	relPath:String,
	report:ScanReport
};

/** Aggregate of a folder scan: every file that had at least one issue, plus the running total. **/
typedef FolderReport = {
	root:String,
	files:Array<FileReport>,
	total:Int
};

/**
	The Script Converter engine. Non-destructive: `analyze` and `scanFolder` only read; only the
	explicit `exportFolder` writes, and it writes *new* `*.converted.<ext>` siblings plus a report
	-- never the modder's originals.

	`analyze` is platform-agnostic (used by the UI on the already-loaded source of a file); the
	folder walk and the export are guarded behind `#if sys`.
**/
class ScriptScanner {
	/**
		Maps a script file extension to its language.
		@param ext the lower-case extension without the dot
		@return `LUA`/`HSCRIPT`, or `null` when the file is not a script
	**/
	public static function kindForExt(ext:String):Null<ScriptKind> {
		return switch (ext.toLowerCase()) {
			case 'lua': LUA;
			case 'hx' | 'hscript' | 'hxs' | 'hxc': HSCRIPT;
			default: null;
		}
	}

	/**
		Scans one script's source for outdated idioms.
		@param src the raw script text
		@param kind the source language (`LUA` or `HSCRIPT`)
		@return the per-line issues plus an annotated copy of the source
	**/
	public static function analyze(src:String, kind:ScriptKind):ScanReport {
		var rules:Array<ScriptRule> = ScriptRules.forKind(kind);
		var issues:Array<ScanIssue> = [];
		var lines:Array<String> = src.split('\n');
		var commentLead:String = (kind == LUA) ? '-- ' : '// ';
		var out:Array<String> = [];
		var inLong:Bool = false; // inside a Lua [[ ]] long string / --[[ ]] long comment (LUA only)

		for (i in 0...lines.length) {
			var line:String = lines[i];
			// State at the START of the line: a line whose flagged token lives inside an open long string
			// (e.g. the embedded Haxe of a `runHaxeCode([[ ... ]])`) must NOT get a Lua `--` comment
			// inserted above it -- that lands inside the string and corrupts the embedded code.
			var startedInside:Bool = inLong;
			if (kind == LUA)
				inLong = advanceLongString(line, inLong);

			var hits:Array<ScanIssue> = [];
			for (rule in rules) {
				if (rule.re.match(line)) {
					hits.push({
						line: i + 1,
						kind: rule.kind,
						severity: rule.kind.severity(),
						match: rule.re.matched(0),
						message: rule.message,
						suggestion: rule.suggestion
					});
				}
			}
			if (hits.length > 0) {
				var annotate:Bool = !startedInside;
				var indent:String = line.substr(0, line.length - line.ltrim().length);
				for (h in hits) {
					issues.push(h);
					if (annotate)
						out.push(indent + commentLead + 'COMPAT(' + h.severity + '): ' + annotationText(h));
				}
			}
			out.push(line);
		}
		return {issues: issues, annotated: out.join('\n')};
	}

	/** The one-line advice written above a flagged line (message, plus the suggestion when present). **/
	static inline function annotationText(issue:ScanIssue):String {
		return (issue.suggestion != null && issue.suggestion.length > 0) ? issue.message + ' ' + issue.suggestion : issue.message;
	}

	/**
		Tracks Lua long-bracket regions (`[[ ]]` strings and `--[[ ]]` comments) across a line so the
		annotator can tell whether a flagged token sits inside embedded text (e.g. a `runHaxeCode` block).
		A best-effort single-level scan -- it does not model `[=[`/`]=]` levels or brackets that appear
		inside quoted strings, which Psych scripts effectively never mix with a `runHaxeCode` payload.
		@param line the source line
		@param inside whether a long-bracket region was already open at the line's start
		@return whether a long-bracket region is still open at the line's end
	**/
	static function advanceLongString(line:String, inside:Bool):Bool {
		var i:Int = 0;
		var len:Int = line.length;
		while (i < len) {
			if (inside) {
				if (line.charCodeAt(i) == ']'.code && i + 1 < len && line.charCodeAt(i + 1) == ']'.code) {
					inside = false;
					i += 2;
					continue;
				}
			} else {
				if (line.charCodeAt(i) == '['.code && i + 1 < len && line.charCodeAt(i + 1) == '['.code) {
					inside = true;
					i += 2;
					continue;
				}
				// A `--` starts either a `--[[` long comment (opens a region) or a line comment (rest ignored).
				if (line.charCodeAt(i) == '-'.code && i + 1 < len && line.charCodeAt(i + 1) == '-'.code) {
					if (i + 3 < len && line.charCodeAt(i + 2) == '['.code && line.charCodeAt(i + 3) == '['.code) {
						inside = true;
						i += 4;
						continue;
					}
					break; // line comment -- nothing after it can open a long string
				}
			}
			i++;
		}
		return inside;
	}

	#if sys
	/**
		Recursively scans a folder, keeping the per-file issues in memory (the UI renders them).
		Never writes anything.
		@param dir the mod folder to scan
		@return the files that had issues plus the total issue count
	**/
	public static function scanFolder(dir:String):FolderReport {
		var files:Array<FileReport> = [];
		var total:Int = 0;
		if (FileSystem.exists(dir) && FileSystem.isDirectory(dir))
			total = scanInto(dir, dir, files);
		return {root: dir, files: files, total: total};
	}

	static function scanInto(root:String, dir:String, files:Array<FileReport>):Int {
		var total:Int = 0;
		for (entry in FileSystem.readDirectory(dir)) {
			var full:String = haxe.io.Path.join([dir, entry]);
			if (FileSystem.isDirectory(full)) {
				total += scanInto(root, full, files);
				continue;
			}
			if (entry.indexOf('.converted.') >= 0)
				continue;
			var kind:Null<ScriptKind> = kindForExt(haxe.io.Path.extension(entry));
			if (kind == null)
				continue;
			var report:ScanReport = analyze(File.getContent(full), kind);
			if (report.issues.length == 0)
				continue;
			total += report.issues.length;
			files.push({fullPath: full, relPath: relativePath(root, full), report: report});
		}
		return total;
	}

	static inline function relativePath(root:String, full:String):String {
		var r:String = full.substr(root.length);
		while (r.startsWith('/') || r.startsWith('\\'))
			r = r.substr(1);
		return r;
	}

	/**
		Writes the migration artefacts for an already-computed folder scan: an annotated
		`*.converted.<ext>` beside each flagged script plus a `script-convert-report.txt` at the
		folder root. Originals are left untouched.
		@param report a `FolderReport` from `scanFolder`
		@param mode how much the rewrite is allowed to change; renames and paths only unless told otherwise
		@return the number of annotated copies written
	**/
	public static function exportFolder(report:FolderReport, mode:ScriptRewriter.RewriteMode = RENAMES_ONLY):Int {
		if (report == null || report.files.length == 0)
			return 0;
		var summary:StringBuf = new StringBuf();
		var written:Int = 0;
		var totalRenames:Int = 0;
		var totalResidual:Int = 0;
		for (file in report.files) {
			var ext:String = haxe.io.Path.extension(file.fullPath);
			var kind:Null<ScriptKind> = kindForExt(ext);
			if (kind == null)
				continue;

			// Auto-fix what this mode allows, then annotate ONLY what is left (whatever the mode
			// declined, plus compat-only mirrors, removed APIs and patterns) on the rewritten source.
			var src:String = File.getContent(file.fullPath);
			var rewritten:ScriptRewriter.RewriteResult = ScriptRewriter.rewrite(src, kind, mode);
			var residual:ScanReport = analyze(rewritten.text, kind);

			var outPath:String = file.fullPath.substr(0, file.fullPath.length - (ext.length + 1)) + '.converted.' + ext;
			File.saveContent(outPath, residual.annotated);
			written++;
			totalRenames += rewritten.changes;
			totalResidual += residual.issues.length;

			summary.add('${file.relPath}  (${rewritten.changes} auto-fixed, ${residual.issues.length} left)\n');
			for (issue in residual.issues)
				summary.add('  L${issue.line} [${issue.severity}/${issue.kind.label()}] ${issue.match}: ${annotationText(issue)}\n');
			summary.add('\n');
		}
		File.saveContent(haxe.io.Path.join([report.root, 'script-convert-report.txt']),
			'Script conversion report\nMode: ${mode.label()} (${mode.describe()})\n'
			+ 'Files processed: ${report.files.length}\n'
			+ 'Auto-fixed substitutions: $totalRenames\nIssues left to migrate by hand: $totalResidual\n\n'
			+ 'The .converted.* copies have this mode\'s substitutions applied; remaining lines are commented with\n'
			+ 'COMPAT(...) advice. Legacy support runs when a pack sets "legacyMode": true (or\n'
			+ '"compatibilityMode": true) in pack.json; the strum groups + note fields work there.\n\n'
			+ summary.toString());
		return written;
	}
	#end
}
