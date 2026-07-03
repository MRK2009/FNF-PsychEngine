package debug.bench;

import debug.bench.BenchScenario;
import debug.bench.BenchScripts;

class BenchSuites {
	public static final SUITE_NAMES:Array<String> = ['Quick Suite', 'Full Suite', 'Gameplay Suite', 'Scripting Suite'];

	static function make(name:String, desc:String):BenchScenario {
		return {
			name: name,
			desc: desc,
			durationSec: 45,
			bpm: 120,
			keyCount: 4,
			scrollSpeed: 3.0,
			playerNps: 0,
			opponentNps: 0,
			sustainChance: 0,
			eventsPerBeat: 0,
			hitchEveryMs: 0,
			hitchLenMs: 0,
			song: 'bopeebo',
			stage: 'stage',
			scripts: []
		};
	}

	static function luaDef(fileName:String, source:String, copies:Int):BenchScriptDef
		return {fileName: fileName, lua: true, source: source, copies: copies};

	static function hxDef(fileName:String, source:String, copies:Int):BenchScriptDef
		return {fileName: fileName, lua: false, source: source, copies: copies};

	public static function baseline():BenchScenario {
		final sc:BenchScenario = make('01 Baseline', 'Near-empty chart, engine floor');
		sc.durationSec = 30;
		sc.playerNps = 1;
		return sc;
	}

	public static function light():BenchScenario {
		final sc:BenchScenario = make('02 Light 4K', '3 NPS per side, few sustains');
		sc.playerNps = 3;
		sc.opponentNps = 3;
		sc.sustainChance = 0.10;
		return sc;
	}

	public static function medium():BenchScenario {
		final sc:BenchScenario = make('03 Medium 4K', '8 NPS per side, sustains');
		sc.playerNps = 8;
		sc.opponentNps = 8;
		sc.sustainChance = 0.20;
		return sc;
	}

	public static function dense():BenchScenario {
		final sc:BenchScenario = make('04 Dense 4K', '14 NPS per side, chords + sustains');
		sc.durationSec = 60;
		sc.playerNps = 14;
		sc.opponentNps = 14;
		sc.sustainChance = 0.25;
		return sc;
	}

	public static function mania9k():BenchScenario {
		final sc:BenchScenario = make('05 Mania 9K', '18 NPS per side across 9 lanes');
		sc.durationSec = 60;
		sc.keyCount = 9;
		sc.playerNps = 18;
		sc.opponentNps = 18;
		sc.sustainChance = 0.20;
		return sc;
	}

	public static function eventFlood():BenchScenario {
		final sc:BenchScenario = make('06 Event Flood', 'Medium chart + 6 chart events per beat');
		sc.playerNps = 8;
		sc.opponentNps = 8;
		sc.sustainChance = 0.20;
		sc.eventsPerBeat = 6;
		return sc;
	}

	public static function luaUpdate():BenchScenario {
		final sc:BenchScenario = make('07 Lua Update Stress', 'Medium chart + 4 Lua scripts with heavy onUpdate');
		sc.playerNps = 8;
		sc.opponentNps = 8;
		sc.sustainChance = 0.20;
		sc.scripts = [luaDef('bench_update_stress', BenchScripts.LUA_UPDATE_STRESS, 4)];
		return sc;
	}

	public static function luaSprites():BenchScenario {
		final sc:BenchScenario = make('08 Lua Sprite Storm', 'Medium chart + 120 Lua sprites, tweens each beat');
		sc.playerNps = 8;
		sc.opponentNps = 8;
		sc.sustainChance = 0.20;
		sc.scripts = [luaDef('bench_sprite_storm', BenchScripts.LUA_SPRITE_STORM, 1)];
		return sc;
	}

	public static function hscriptStress():BenchScenario {
		final sc:BenchScenario = make('09 HScript Stress', 'Medium chart + 3 HScript files allocating per frame');
		sc.playerNps = 8;
		sc.opponentNps = 8;
		sc.sustainChance = 0.20;
		sc.scripts = [hxDef('bench_hscript_stress', BenchScripts.HSCRIPT_STRESS, 3)];
		return sc;
	}

	public static function everything():BenchScenario {
		final sc:BenchScenario = make('10 Everything', 'Dense chart + events + Lua update/sprites + HScript');
		sc.durationSec = 60;
		sc.playerNps = 14;
		sc.opponentNps = 14;
		sc.sustainChance = 0.25;
		sc.eventsPerBeat = 4;
		sc.scripts = [
			luaDef('bench_update_stress', BenchScripts.LUA_UPDATE_STRESS, 3),
			luaDef('bench_sprite_storm', BenchScripts.LUA_SPRITE_STORM, 1),
			hxDef('bench_hscript_stress', BenchScripts.HSCRIPT_STRESS, 2)
		];
		return sc;
	}

	public static function hitchClamp():BenchScenario {
		final sc:BenchScenario = make('11 Hitch Clamp', 'Medium chart + forced 150ms stall every 2s (maxElapsed clamp)');
		sc.durationSec = 30;
		sc.playerNps = 8;
		sc.opponentNps = 8;
		sc.sustainChance = 0.20;
		sc.hitchEveryMs = 2000;
		sc.hitchLenMs = 150;
		return sc;
	}

	public static function byName(name:String):Array<BenchScenario> {
		return switch (name) {
			case 'Quick Suite': [baseline(), medium(), luaUpdate(), everything()];
			case 'Gameplay Suite': [baseline(), light(), medium(), dense(), mania9k(), eventFlood(), hitchClamp()];
			case 'Scripting Suite': [medium(), luaUpdate(), luaSprites(), hscriptStress(), everything()];
			default: [
					baseline(), light(), medium(), dense(), mania9k(),
					eventFlood(), luaUpdate(), luaSprites(), hscriptStress(), everything(), hitchClamp()
				];
		}
	}
}
