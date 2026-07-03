package debug.bench;

class BenchScripts {
	public static final LUA_UPDATE_STRESS:String = "
local acc = 0.0
local props = {'boyfriend.x', 'boyfriend.y', 'dad.x', 'dad.y', 'camGame.zoom', 'camHUD.zoom', 'health', 'songPercent'}

function onUpdate(elapsed)
	local a = 0.0
	for i = 1, 3000 do
		a = a + math.sqrt(i) * math.sin(i * 0.017)
	end
	acc = acc + a
	for i = 1, #props do
		local v = getProperty(props[i])
	end
	setProperty('boyfriend.alpha', 1)
	setProperty('dad.alpha', 1)
end

function onBeatHit()
	triggerEvent('Add Camera Zoom', '0.01', '0.02')
end
";

	public static final LUA_SPRITE_STORM:String = "
local COUNT = 120
local colors = {'FF6B6B', 'FFD93D', '6BCB77', '4D96FF', 'B36BFF', 'FF6BD6'}

function onCreatePost()
	for i = 0, COUNT - 1 do
		local tag = 'benchSpr' .. i
		makeLuaSprite(tag, nil, (i % 16) * 80, 60 + math.floor(i / 16) * 80)
		makeGraphic(tag, 48, 48, colors[(i % 6) + 1])
		setObjectCamera(tag, 'hud')
		setProperty(tag .. '.alpha', 0.35)
		addLuaSprite(tag, true)
	end
end

function onBeatHit()
	for i = 0, COUNT - 1 do
		local tag = 'benchSpr' .. i
		doTweenAngle('benchAng' .. i, tag, (curBeat % 2) * 180, 0.4, 'quadInOut')
		doTweenX('benchX' .. i, tag, (i % 16) * 80 + (curBeat % 2) * 40, 0.4, 'quadInOut')
	end
end

function onUpdate(elapsed)
	for i = 0, 29 do
		local tag = 'benchSpr' .. i
		setProperty(tag .. '.y', 60 + math.floor(i / 16) * 80 + math.sin(getSongPosition() * 0.002 + i) * 30)
	end
end
";

	public static final HSCRIPT_STRESS:String = "
var acc:Float = 0;

function onUpdate(elapsed:Float) {
	var arr:Array<Float> = [];
	for (i in 0...2000) {
		arr.push(Math.sqrt(i + 1) * Math.cos(i * 0.02));
	}
	var s:Float = 0;
	for (v in arr) {
		s += v;
	}
	acc += s;
}

function onBeatHit() {
	var total:Float = 0;
	for (i in 0...200) {
		total += Math.pow(1.0001, i);
	}
	acc += total;
}
";
}
