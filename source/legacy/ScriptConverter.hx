package legacy;

#if sys
import sys.FileSystem;
import sys.io.File;
#end
using StringTools;

/** One flagged spot in a script: the 1-based line, the matched snippet, and human guidance. **/
typedef ConvertIssue = {
	line:Int,
	severity:String, // 'warn' | 'info'
	match:String,
	advice:String
}

/** Result of analysing one script source. **/
typedef ConvertReport = {
	issues:Array<ConvertIssue>,
	annotated:String // original source with `COMPAT:` comment lines inserted above each issue
}

/**
	Non-destructive helper for the `compatibilityMode` story: scans old Lua/HScript mod scripts for the
	pre-v2 note API that the v2 runtime can't fully serve through the adapter layer (`NoteCompatLayer`),
	and reports/annotates them so a modder can migrate by hand. The alias-impossible cases (per
	docs/note-system-v2.md) -- chiefly whole-chart `unspawnNotes` iteration -- are flagged here rather
	than faked at runtime.

	It NEVER edits the user's files in place: `convertFolder` writes annotated `*.converted.<ext>`
	copies plus a `compat-report.txt`. Wire it to a debug-menu entry to run on a mod folder.
**/
class ScriptConverter {
	/** Outdated patterns -> guidance. Order matters only for reporting. **/
	static final RULES:Array<{re:EReg, severity:String, advice:String}> = [
		{
			re: ~/\bunspawnNotes\b/,
			severity: 'warn',
			advice: 'unspawnNotes (whole chart pre-spawned) no longer exists. Read game.playerField.notes / game.opponentField.notes (NoteData list) instead.'
		},
		{
			re: ~/\bnotes\.members\b/,
			severity: 'warn',
			advice: 'game.notes is a read-only mirror in compatibilityMode; writes to note sprites here do not affect the v2 drawables. Adjust visuals via the v2 fields or note types.'
		},
		{
			re: ~/\bplayerStrums\.|\bopponentStrums\.|\bstrumLineNotes\./,
			severity: 'warn',
			advice: 'strum groups are read-only mirrors in compatibilityMode; move/scale the real strums via the v2 receptors (playerReceptors / opponentReceptors).'
		},
		{re: ~/\.strumTime\b/, severity: 'info', advice: 'On NoteData (playerField.notes) the field is .time, not .strumTime.'},
		{re: ~/\.noteData\b/, severity: 'info', advice: 'On NoteData the column field is .column, not .noteData.'},
		{re: ~/\.wasGoodHit\b/, severity: 'info', advice: 'On NoteData the hit flag is .hit, not .wasGoodHit.'},
		{re: ~/\.sustainLength\b/, severity: 'info', advice: 'On NoteData the sustain length is .length, not .sustainLength.'},
		{re: ~/\.ignoreNote\b/, severity: 'info', advice: 'On NoteData the ignore flag is .ignore, not .ignoreNote.'}
	];

	/**
		Scans one script's source for outdated note API.
		@param src the raw script text
		@param isLua `true` for Lua (`--` comments), `false` for HScript (`//` comments)
		@return the per-line issues plus an annotated copy of the source
	**/
	public static function analyze(src:String, isLua:Bool):ConvertReport {
		var issues:Array<ConvertIssue> = [];
		var lines:Array<String> = src.split('\n');
		var commentLead:String = isLua ? '-- ' : '// ';
		var out:Array<String> = [];

		for (i in 0...lines.length) {
			var line:String = lines[i];
			var hits:Array<ConvertIssue> = [];
			for (rule in RULES) {
				if (rule.re.match(line)) {
					hits.push({line: i + 1, severity: rule.severity, match: rule.re.matched(0), advice: rule.advice});
				}
			}
			// Emit annotation comments above the offending line (preserving its indentation).
			if (hits.length > 0) {
				var indent:String = line.substr(0, line.length - line.ltrim().length);
				for (h in hits) {
					issues.push(h);
					out.push(indent + commentLead + 'COMPAT(' + h.severity + '): ' + h.advice);
				}
			}
			out.push(line);
		}
		return {issues: issues, annotated: out.join('\n')};
	}

	#if sys
	/**
		Recursively scans a mod folder, writing an annotated `*.converted.<ext>` next to each `.lua` /
		`.hx` / `.hscript` script and a `compat-report.txt` summary at the folder root. Originals are
		left untouched.
		@param dir the mod folder to scan
		@return the total number of issues found across all scripts
	**/
	public static function convertFolder(dir:String):Int {
		if (!FileSystem.exists(dir) || !FileSystem.isDirectory(dir))
			return 0;
		var report:StringBuf = new StringBuf();
		var total:Int = scanInto(dir, report);
		File.saveContent(haxe.io.Path.join([dir, 'compat-report.txt']),
			'Note API compatibility report\nTotal issues: $total\n\n' + report.toString());
		return total;
	}

	static function scanInto(dir:String, report:StringBuf):Int {
		var total:Int = 0;
		for (entry in FileSystem.readDirectory(dir)) {
			var full:String = haxe.io.Path.join([dir, entry]);
			if (FileSystem.isDirectory(full)) {
				total += scanInto(full, report);
				continue;
			}
			var ext:String = haxe.io.Path.extension(entry).toLowerCase();
			if (ext != 'lua' && ext != 'hx' && ext != 'hscript' && ext != 'hxs')
				continue;
			if (entry.indexOf('.converted.') >= 0)
				continue;
			var rep:ConvertReport = analyze(File.getContent(full), ext == 'lua');
			if (rep.issues.length == 0)
				continue;
			total += rep.issues.length;
			var outPath:String = full.substr(0, full.length - (ext.length + 1)) + '.converted.' + ext;
			File.saveContent(outPath, rep.annotated);
			report.add('$full  (${rep.issues.length} issue(s))\n');
			for (iss in rep.issues)
				report.add('  L${iss.line} [${iss.severity}] ${iss.match}: ${iss.advice}\n');
			report.add('\n');
		}
		return total;
	}
	#end
}
