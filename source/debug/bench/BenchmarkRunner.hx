package debug.bench;

import backend.Song;
import debug.bench.BenchScenario;
import haxe.Json;
import haxe.Timer;
import openfl.Lib;
import openfl.events.Event;
import states.MainMenuState;

typedef BenchResult = {
	var name:String;
	var desc:String;
	var seconds:Float;
	var frames:Int;
	var avgFps:Float;
	var low1Fps:Float;
	var low01Fps:Float;
	var p50Ms:Float;
	var p95Ms:Float;
	var p99Ms:Float;
	var maxMs:Float;
	var over16Ms:Int;
	var over33Ms:Int;
	var createMs:Float;
	var gcStartMB:Float;
	var gcEndMB:Float;
	var gcPeakMB:Float;
	var notesHit:Int;
	var syncAvgMs:Float;
	var syncP99Ms:Float;
	var syncMaxMs:Float;
	var driftMs:Float;
	var clampMaxMs:Float;
}

class BenchmarkRunner {
	public static var active(default, null):Bool = false;
	public static var lastSummary:String = '';
	public static var lastLogPath:String = '';

	static var suiteName:String = '';
	static var scenarios:Array<BenchScenario> = null;
	static var index:Int = 0;
	static var results:Array<BenchResult> = null;
	static var aborted:Bool = false;

	static var listenerOn:Bool = false;
	static var sampling:Bool = false;
	static var finishing:Bool = false;
	static var samples:Array<Float> = null;
	static var sampleCount:Int = 0;
	static var syncSamples:Array<Float> = null;
	static var syncCount:Int = 0;
	static var gameTimeSec:Float = 0;
	static var clampMaxMs:Float = 0;
	static var nextHitchMs:Float = 0;
	static var lastStamp:Float = 0;
	static var scenarioStart:Float = 0;
	static var launchStamp:Float = 0;
	static var createMs:Float = 0;
	static var gcStart:Float = 0;
	static var gcPeak:Float = 0;
	static var savedUpdateFR:Int = 0;
	static var savedDrawFR:Int = 0;
	static var uncapped:Bool = false;

	public static function start(name:String, list:Array<BenchScenario>, uncapFps:Bool = true):Void {
		if (active || list == null || list.length == 0)
			return;
		active = true;
		aborted = false;
		suiteName = name;
		scenarios = list;
		index = -1;
		results = [];
		savedUpdateFR = FlxG.updateFramerate;
		savedDrawFR = FlxG.drawFramerate;
		uncapped = uncapFps;
		if (uncapFps) {
			FlxG.updateFramerate = 1000;
			FlxG.drawFramerate = 1000;
		}
		writeScriptFiles();
		if (!listenerOn) {
			listenerOn = true;
			Lib.current.stage.addEventListener(Event.ENTER_FRAME, onEnterFrame);
		}
		lastStamp = Timer.stamp();
		nextScenario();
	}

	static function nextScenario():Void {
		index++;
		if (index >= scenarios.length) {
			finish();
			return;
		}
		final sc:BenchScenario = scenarios[index];
		finishing = false;
		sampling = false;
		PlayState.SONG = ChartSynth.build(sc);
		Song.loadedSongName = sc.song;
		Song.chartPath = null;
		Song.loadedFormat = backend.Song.ChartFormat.V1;
		Song.parsedChart = PlayState.SONG;
		PlayState.isStoryMode = false;
		PlayState.storyDifficulty = 1;
		PlayState.startOnTime = 0;
		PlayState.chartingMode = false;
		Difficulty.resetList();
		if (FlxG.sound.music != null)
			FlxG.sound.music.stop();
		launchStamp = Timer.stamp();
		LoadingState.prepareToSong();
		LoadingState.loadAndSwitchState(new PlayState());
	}

	public static function onPlayStateReady(game:PlayState):Void {
		if (!active)
			return;
		createMs = (Timer.stamp() - launchStamp) * 1000.0;
		game.cpuControlled = true;
		game.practiceMode = true;
		@:privateAccess game.canPause = false;
		game.skipCountdown = true;
		game.endCallback = onScenarioComplete;
		injectScripts(game, scenarios[index]);
	}

	public static function onSongStarted(game:PlayState):Void {
		if (!active)
			return;
		final cap:Int = Std.int(scenarios[index].durationSec * 1200) + 64;
		if (samples == null || samples.length < cap)
			samples = [for (i in 0...cap) 0.0];
		if (syncSamples == null || syncSamples.length < cap)
			syncSamples = [for (i in 0...cap) 0.0];
		sampleCount = 0;
		syncCount = 0;
		gameTimeSec = 0;
		clampMaxMs = 0;
		nextHitchMs = scenarios[index].hitchEveryMs;
		gcStart = gcMB();
		gcPeak = gcStart;
		scenarioStart = Timer.stamp();
		lastStamp = scenarioStart;
		sampling = true;
	}

	static function onEnterFrame(_:Event):Void {
		final now:Float = Timer.stamp();
		if (sampling) {
			final dt:Float = (now - lastStamp) * 1000.0;
			if (sampleCount < samples.length)
				samples[sampleCount] = dt;
			else
				samples.push(dt);
			sampleCount++;

			gameTimeSec += FlxG.elapsed;
			final clamp:Float = dt - FlxG.elapsed * 1000.0;
			if (clamp > clampMaxMs)
				clampMaxMs = clamp;

			final music:flixel.sound.FlxSound = FlxG.sound.music;
			if (music != null && music.playing) {
				final err:Float = Math.abs(Conductor.songPosition - (music.time + Conductor.offset));
				if (syncCount < syncSamples.length)
					syncSamples[syncCount] = err;
				else
					syncSamples.push(err);
				syncCount++;
			}

			final mb:Float = gcMB();
			if (mb > gcPeak)
				gcPeak = mb;

			final sc:BenchScenario = scenarios[index];
			if (!finishing && (now - scenarioStart) >= sc.durationSec) {
				finishing = true;
				final game:PlayState = PlayState.instance;
				if (game != null)
					game.finishSong(true);
			} else if (sc.hitchLenMs > 0 && (now - scenarioStart) * 1000.0 >= nextHitchMs) {
				nextHitchMs += sc.hitchEveryMs;
				Sys.sleep(sc.hitchLenMs / 1000.0);
			}
		}
		if (active && FlxG.keys.justPressed.F8)
			abortSuite();
		lastStamp = now;
	}

	static function onScenarioComplete():Void {
		if (!active)
			return;
		if (sampling) {
			sampling = false;
			results.push(computeResult(scenarios[index]));
		}
		nextScenario();
	}

	static function abortSuite():Void {
		aborted = true;
		if (sampling) {
			sampling = false;
			results.push(computeResult(scenarios[index]));
		}
		finish();
	}

	static function finish():Void {
		writeLogs();
		FlxG.drawFramerate = savedDrawFR;
		FlxG.updateFramerate = savedUpdateFR;
		active = false;
		sampling = false;
		if (listenerOn) {
			listenerOn = false;
			Lib.current.stage.removeEventListener(Event.ENTER_FRAME, onEnterFrame);
		}
		MusicBeatState.switchState(new BenchmarkState());
	}

	static function computeResult(sc:BenchScenario):BenchResult {
		final count:Int = sampleCount;
		var sum:Float = 0;
		var maxMs:Float = 0;
		var over16:Int = 0;
		var over33:Int = 0;
		final sorted:Array<Float> = [];
		sorted.resize(count);
		for (i in 0...count) {
			final v:Float = samples[i];
			sorted[i] = v;
			sum += v;
			if (v > maxMs)
				maxMs = v;
			if (v > 16.7)
				over16++;
			if (v > 33.4)
				over33++;
		}
		sorted.sort((a:Float, b:Float) -> a < b ? -1 : (a > b ? 1 : 0));

		final avgMs:Float = count > 0 ? sum / count : 0;
		final game:PlayState = PlayState.instance;

		var syncSum:Float = 0;
		var syncMax:Float = 0;
		final syncSorted:Array<Float> = [];
		syncSorted.resize(syncCount);
		for (i in 0...syncCount) {
			final v:Float = syncSamples[i];
			syncSorted[i] = v;
			syncSum += v;
			if (v > syncMax)
				syncMax = v;
		}
		syncSorted.sort((a:Float, b:Float) -> a < b ? -1 : (a > b ? 1 : 0));

		final wallMs:Float = (Timer.stamp() - scenarioStart) * 1000.0;

		var hits:Int = 0;
		if (game != null && game.noteFields != null)
			for (f in game.noteFields)
				if (f != null && f.notes != null)
					for (data in f.notes)
						if (data.hit)
							hits++;

		return {
			name: sc.name,
			desc: sc.desc,
			seconds: sum / 1000.0,
			frames: count,
			avgFps: avgMs > 0 ? 1000.0 / avgMs : 0,
			low1Fps: lowFps(sorted, 0.01),
			low01Fps: lowFps(sorted, 0.001),
			p50Ms: percentile(sorted, 0.50),
			p95Ms: percentile(sorted, 0.95),
			p99Ms: percentile(sorted, 0.99),
			maxMs: maxMs,
			over16Ms: over16,
			over33Ms: over33,
			createMs: createMs,
			gcStartMB: gcStart,
			gcEndMB: gcMB(),
			gcPeakMB: gcPeak,
			notesHit: hits,
			syncAvgMs: syncCount > 0 ? syncSum / syncCount : 0,
			syncP99Ms: percentile(syncSorted, 0.99),
			syncMaxMs: syncMax,
			driftMs: wallMs - gameTimeSec * 1000.0,
			clampMaxMs: clampMaxMs
		};
	}

	static function percentile(sorted:Array<Float>, q:Float):Float {
		if (sorted.length == 0)
			return 0;
		return sorted[Std.int(q * (sorted.length - 1))];
	}

	static function lowFps(sorted:Array<Float>, fraction:Float):Float {
		final count:Int = sorted.length;
		if (count == 0)
			return 0;
		var n:Int = Std.int(count * fraction);
		if (n < 1)
			n = 1;
		var sum:Float = 0;
		for (i in (count - n)...count)
			sum += sorted[i];
		final avg:Float = sum / n;
		return avg > 0 ? 1000.0 / avg : 0;
	}

	static inline function gcMB():Float {
		#if cpp
		return cpp.vm.Gc.memInfo64(cpp.vm.Gc.MEM_INFO_USAGE) / 1048576.0;
		#else
		return 0;
		#end
	}

	static function benchDir():String {
		var cwd:String = Sys.getCwd();
		cwd = cwd.split('\\').join('/');
		if (!cwd.endsWith('/'))
			cwd += '/';
		return cwd + 'benchmarks/';
	}

	static function scriptPath(def:BenchScriptDef, copy:Int):String {
		final ext:String = def.lua ? '.lua' : '.hx';
		final suffix:String = def.copies > 1 ? '_' + copy : '';
		return benchDir() + '_scripts/' + def.fileName + suffix + ext;
	}

	static function writeScriptFiles():Void {
		try {
			FileSystem.createDirectory(benchDir() + '_scripts');
			final written:Map<String, Bool> = new Map();
			for (sc in scenarios) {
				if (sc.scripts == null)
					continue;
				for (def in sc.scripts)
					for (i in 0...def.copies) {
						final path:String = scriptPath(def, i);
						if (written.exists(path))
							continue;
						written.set(path, true);
						File.saveContent(path, def.source);
					}
			}
		} catch (e:Dynamic) {
			trace('Benchmark: failed to write stress scripts: $e');
		}
	}

	static function injectScripts(game:PlayState, sc:BenchScenario):Void {
		if (sc.scripts == null)
			return;
		for (def in sc.scripts) {
			for (i in 0...def.copies) {
				final path:String = scriptPath(def, i);
				if (!FileSystem.exists(path))
					continue;
				if (def.lua) {
					#if LUA_ALLOWED
					new psychlua.FunkinLua(path);
					#end
				} else {
					#if HSCRIPT_ALLOWED
					game.initHScript(path);
					#end
				}
			}
		}
	}

	static function buildMeta():Dynamic {
		var gpu:String = '';
		try {
			gpu = Std.string(lime.graphics.opengl.GL.getParameter(lime.graphics.opengl.GL.RENDERER));
		} catch (e:Dynamic) {
			gpu = '';
		}
		var totalRamMB:Float = 0;
		#if HARDWARE_ALLOWED
		try {
			totalRamMB = (hxhardware.Memory.getSystemTotalPhysicalMemory() : Float) / 1048576.0;
		} catch (e:Dynamic) {}
		#end
		final cpuName:String = Sys.getEnv('PROCESSOR_IDENTIFIER');
		final cores:String = Sys.getEnv('NUMBER_OF_PROCESSORS');
		return {
			suite: suiteName,
			date: Date.now().toString(),
			aborted: aborted,
			engineVersion: MainMenuState.psychEngineVersion,
			os: Sys.systemName(),
			cpu: cpuName != null ? cpuName : '',
			cores: cores != null ? cores : '',
			gpu: gpu,
			totalRamMB: Math.round(totalRamMB),
			resolution: FlxG.stage.stageWidth + 'x' + FlxG.stage.stageHeight,
			fullscreen: FlxG.fullscreen,
			fpsCapSetting: ClientPrefs.data.framerate,
			uncappedDuringRun: uncapped,
			fixedTimestep: FlxG.fixedTimestep
		};
	}

	static function fmt(v:Float, decimals:Int):String {
		final mult:Float = Math.pow(10, decimals);
		return Std.string(Math.round(v * mult) / mult);
	}

	static function pad(s:String, width:Int):String {
		var out:String = s;
		while (out.length < width)
			out += ' ';
		return out;
	}

	static function buildText(meta:Dynamic):String {
		final buf:StringBuf = new StringBuf();
		buf.add('PSYCH ENGINE BENCHMARK -- ' + suiteName + (aborted ? ' (ABORTED)' : '') + '\n');
		buf.add(Std.string(meta.date) + ' | ' + Std.string(meta.engineVersion) + ' | ' + Std.string(meta.os) + '\n');
		if (Std.string(meta.cpu).length > 0)
			buf.add('CPU: ' + Std.string(meta.cpu) + ' (' + Std.string(meta.cores) + ' threads)\n');
		if (Std.string(meta.gpu).length > 0)
			buf.add('GPU: ' + Std.string(meta.gpu) + '\n');
		buf.add('Resolution: ' + Std.string(meta.resolution) + (meta.fullscreen == true ? ' fullscreen' : ' windowed'));
		buf.add(' | FPS cap setting: ' + Std.string(meta.fpsCapSetting) + (uncapped ? ' (uncapped during run)' : '') + '\n\n');

		buf.add(pad('Scenario', 22));
		buf.add(pad('AvgFPS', 9));
		buf.add(pad('1%Low', 9));
		buf.add(pad('0.1%Low', 9));
		buf.add(pad('p50ms', 8));
		buf.add(pad('p95ms', 8));
		buf.add(pad('p99ms', 8));
		buf.add(pad('Maxms', 9));
		buf.add(pad('>16ms', 7));
		buf.add(pad('>33ms', 7));
		buf.add(pad('GC+MB', 8));
		buf.add(pad('LoadMs', 8));
		buf.add('Frames\n');

		for (r in results) {
			buf.add(pad(r.name, 22));
			buf.add(pad(fmt(r.avgFps, 1), 9));
			buf.add(pad(fmt(r.low1Fps, 1), 9));
			buf.add(pad(fmt(r.low01Fps, 1), 9));
			buf.add(pad(fmt(r.p50Ms, 2), 8));
			buf.add(pad(fmt(r.p95Ms, 2), 8));
			buf.add(pad(fmt(r.p99Ms, 2), 8));
			buf.add(pad(fmt(r.maxMs, 1), 9));
			buf.add(pad(Std.string(r.over16Ms), 7));
			buf.add(pad(Std.string(r.over33Ms), 7));
			buf.add(pad(fmt(r.gcPeakMB - r.gcStartMB, 1), 8));
			buf.add(pad(fmt(r.createMs, 0), 8));
			buf.add(Std.string(r.frames) + '\n');
		}

		buf.add('\nSYNC / REALTIME (song position vs audio clock, game time vs wall time)\n');
		buf.add(pad('Scenario', 22));
		buf.add(pad('SyncAvg', 9));
		buf.add(pad('SyncP99', 9));
		buf.add(pad('SyncMax', 9));
		buf.add(pad('DriftMs', 9));
		buf.add(pad('ClampMax', 10));
		buf.add('Hits\n');
		for (r in results) {
			buf.add(pad(r.name, 22));
			buf.add(pad(fmt(r.syncAvgMs, 2), 9));
			buf.add(pad(fmt(r.syncP99Ms, 2), 9));
			buf.add(pad(fmt(r.syncMaxMs, 1), 9));
			buf.add(pad(fmt(r.driftMs, 1), 9));
			buf.add(pad(fmt(r.clampMaxMs, 1), 10));
			buf.add(Std.string(r.notesHit) + '\n');
		}

		buf.add('\n');
		for (r in results)
			buf.add(pad(r.name, 22) + r.desc + '\n');
		return buf.toString();
	}

	static function writeLogs():Void {
		final meta:Dynamic = buildMeta();
		final txt:String = buildText(meta);
		lastSummary = txt;
		trace('\n' + txt);
		try {
			final dir:String = benchDir();
			FileSystem.createDirectory(dir);
			final stamp:String = DateTools.format(Date.now(), '%Y-%m-%d_%H-%M-%S');
			final report:Dynamic = {meta: meta, scenarios: scenarioParams(), results: results};
			File.saveContent(dir + 'benchmark_' + stamp + '.json', Json.stringify(report, null, '\t'));
			final txtPath:String = dir + 'benchmark_' + stamp + '.txt';
			File.saveContent(txtPath, txt);
			lastLogPath = txtPath;
		} catch (e:Dynamic) {
			lastLogPath = '';
			trace('Benchmark: failed to write log: $e');
		}
	}

	static function scenarioParams():Array<Dynamic> {
		final out:Array<Dynamic> = [];
		for (sc in scenarios) {
			out.push({
				name: sc.name,
				desc: sc.desc,
				durationSec: sc.durationSec,
				bpm: sc.bpm,
				keyCount: sc.keyCount,
				scrollSpeed: sc.scrollSpeed,
				playerNps: sc.playerNps,
				opponentNps: sc.opponentNps,
				sustainChance: sc.sustainChance,
				eventsPerBeat: sc.eventsPerBeat,
				hitchEveryMs: sc.hitchEveryMs,
				hitchLenMs: sc.hitchLenMs,
				song: sc.song,
				stage: sc.stage,
				scripts: sc.scripts != null ? [for (d in sc.scripts) d.fileName + (d.lua ? '.lua' : '.hx') + ' x' + d.copies] : []
			});
		}
		return out;
	}
}
