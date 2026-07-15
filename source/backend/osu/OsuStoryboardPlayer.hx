package backend.osu;

import flixel.FlxG;
import flixel.FlxSprite;
import flixel.group.FlxGroup.FlxTypedGroup;
import flixel.graphics.FlxGraphic;
import flixel.tweens.FlxEase;
import flixel.util.FlxColor;
import openfl.display.BlendMode;
import backend.Conductor;
import backend.ClientPrefs;
import backend.osu.OsuStoryboard.OsuSbObject;
import backend.osu.OsuStoryboard.OsuSbCommand;
import backend.osu.OsuStoryboard.OsuSbSample;
#if sys
import openfl.display.BitmapData;
import openfl.media.Sound;
import openfl.media.SoundTransform;
import sys.FileSystem;
import haxe.io.Path;
#end

typedef OsuSbKey = {
	var s:Float;
	var e:Float;
	var ease:Int;
	var a:Float;
	var b:Float;
}

typedef OsuSbParam = {
	var type:String;
	var s:Float;
	var e:Float;
}

class OsuSbRuntimeSprite extends FlxSprite {
	public var boundsMin:Float = 0;
	public var boundsMax:Float = 0;
	public var baseX:Float = 0;
	public var baseY:Float = 0;
	public var originFracX:Float = 0.5;
	public var originFracY:Float = 0.5;

	public var chAlpha:Array<OsuSbKey> = [];
	public var chX:Array<OsuSbKey> = [];
	public var chY:Array<OsuSbKey> = [];
	public var chScaleX:Array<OsuSbKey> = [];
	public var chScaleY:Array<OsuSbKey> = [];
	public var chRot:Array<OsuSbKey> = [];
	public var chR:Array<OsuSbKey> = [];
	public var chG:Array<OsuSbKey> = [];
	public var chB:Array<OsuSbKey> = [];
	public var params:Array<OsuSbParam> = [];

	public var frames2:Array<FlxGraphic> = null;
	public var frameDelay:Float = 0;
	public var loopForever:Bool = true;
	public var lastFrame:Int = -1;

	public function new()
		super(0, 0);
}

@:keep // only ever reached via a generated Lua `import()` string, so DCE must not drop it
class OsuStoryboardPlayer extends FlxTypedGroup<OsuSbRuntimeSprite> {
	static inline var OSU_BASE_W:Float = 640;
	static inline var OSU_BASE_H:Float = 480;

	static inline var SAMPLE_FIRE_WINDOW:Float = 1000;

	var imageDir:String;
	var soundDir:String;
	var timeOffsetMs:Float;
	var scale:Float;
	var offsetX:Float;
	var offsetY:Float;
	var bitmapCache:Map<String, FlxGraphic> = new Map();

	public var soundsEnabled:Bool = true;

	var samples:Array<OsuSbSample> = [];
	var sampleIdx:Int = 0;
	var lastT:Float = Math.NEGATIVE_INFINITY;
	#if sys
	var sampleCache:Map<String, Sound> = new Map();
	#end

	public function new(storyboard:OsuStoryboard, imageDir:String, soundDir:String, timeOffsetMs:Float = 0) {
		super();
		this.imageDir = imageDir;
		this.soundDir = soundDir;
		this.timeOffsetMs = timeOffsetMs;
		var cam = FlxG.camera;
		var cover:Float = (cam != null && cam.zoom > 0) ? (cam.height / cam.zoom) / FlxG.height : 1;
		this.scale = (FlxG.height / OSU_BASE_H) * cover;
		this.offsetX = FlxG.width / 2 - (OSU_BASE_W / 2) * scale;
		this.offsetY = FlxG.height / 2 - (OSU_BASE_H / 2) * scale;

		if (storyboard != null)
			build(storyboard);
	}

	#if sys
	public static function fromFile(osbPath:String, imageDir:String, soundDir:String, timeOffsetMs:Float = 0):OsuStoryboardPlayer {
		var text:String = null;
		try {
			if (FileSystem.exists(osbPath))
				text = sys.io.File.getContent(osbPath);
		} catch (e:Dynamic) {}
		return new OsuStoryboardPlayer(OsuStoryboard.parse(text), imageDir, soundDir, timeOffsetMs);
	}
	#end

	function build(storyboard:OsuStoryboard) {
		samples = storyboard.samples;

		// Stable layer ordering: Background, Fail/Pass, Foreground, Overlay (file order within a layer).
		var ordered:Array<{obj:OsuSbObject, idx:Int}> = [for (i in 0...storyboard.objects.length) {obj: storyboard.objects[i], idx: i}];
		ordered.sort((a, b) -> {
			var pa:Int = layerPriority(a.obj.layer),
				pb:Int = layerPriority(b.obj.layer);
			return (pa != pb) ? pa - pb : a.idx - b.idx;
		});

		for (entry in ordered) {
			var sprite:OsuSbRuntimeSprite = makeSprite(entry.obj);
			if (sprite != null)
				add(sprite);
		}
	}

	function makeSprite(obj:OsuSbObject):OsuSbRuntimeSprite {
		var sprite:OsuSbRuntimeSprite = new OsuSbRuntimeSprite();

		if (obj.isAnimation) {
			sprite.frames2 = [];
			for (p in obj.framePaths()) {
				var g:FlxGraphic = resolveGraphic(p);
				if (g != null)
					sprite.frames2.push(g);
			}
			if (sprite.frames2.length < 1)
				return null;
			sprite.loadGraphic(sprite.frames2[0]);
			sprite.frameDelay = obj.frameDelay;
			sprite.loopForever = (obj.loopType != 'LoopOnce');
		} else {
			var g:FlxGraphic = resolveGraphic(obj.path);
			if (g == null)
				return null;
			sprite.loadGraphic(g);
		}

		sprite.antialiasing = ClientPrefs.data.antialiasing;
		sprite.scrollFactor.set(0, 0);
		sprite.moves = false;
		sprite.active = false; // we drive everything from the player's update

		var bounds = obj.timeBounds();
		if (obj.commands.length == 0 && layerPriority(obj.layer) == 0) {
			sprite.boundsMin = Math.NEGATIVE_INFINITY;
			sprite.boundsMax = Math.POSITIVE_INFINITY;
		} else {
			sprite.boundsMin = bounds.min;
			sprite.boundsMax = (obj.isAnimation && sprite.loopForever && bounds.max <= bounds.min) ? Math.POSITIVE_INFINITY : bounds.max;
		}
		sprite.baseX = obj.x;
		sprite.baseY = obj.y;

		var frac = originFrac(obj.origin);
		sprite.originFracX = frac.x;
		sprite.originFracY = frac.y;

		collectChannels(obj, sprite);
		sprite.visible = false;
		return sprite;
	}

	function collectChannels(obj:OsuSbObject, s:OsuSbRuntimeSprite) {
		for (cmd in obj.commands) {
			switch (cmd.event) {
				case 'L':
					var len:Float = cmd.loopLength();
					for (k in 0...cmd.loopCount)
						for (child in cmd.children)
							addCommand(s, child, cmd.startTime + k * len);
				case 'T':
					// TBA
				default:
					addCommand(s, cmd, 0);
			}
		}
		sortChannel(s.chAlpha);
		sortChannel(s.chX);
		sortChannel(s.chY);
		sortChannel(s.chScaleX);
		sortChannel(s.chScaleY);
		sortChannel(s.chRot);
		sortChannel(s.chR);
		sortChannel(s.chG);
		sortChannel(s.chB);
	}

	function addCommand(s:OsuSbRuntimeSprite, c:OsuSbCommand, base:Float) {
		var st:Float = c.startTime + base;
		var en:Float = c.endTime + base;
		inline function key(a:Float, b:Float):OsuSbKey
			return {
				s: st,
				e: en,
				ease: c.easing,
				a: a,
				b: b
			};

		switch (c.event) {
			case 'F':
				s.chAlpha.push(key(c.startVals[0], c.endVals[0]));
			case 'M':
				s.chX.push(key(c.startVals[0], c.endVals[0]));
				s.chY.push(key(c.startVals[1], c.endVals[1]));
			case 'MX':
				s.chX.push(key(c.startVals[0], c.endVals[0]));
			case 'MY':
				s.chY.push(key(c.startVals[0], c.endVals[0]));
			case 'S':
				s.chScaleX.push(key(c.startVals[0], c.endVals[0]));
				s.chScaleY.push(key(c.startVals[0], c.endVals[0]));
			case 'V':
				s.chScaleX.push(key(c.startVals[0], c.endVals[0]));
				s.chScaleY.push(key(c.startVals[1], c.endVals[1]));
			case 'R':
				s.chRot.push(key(c.startVals[0], c.endVals[0]));
			case 'C':
				s.chR.push(key(c.startVals[0], c.endVals[0]));
				s.chG.push(key(c.startVals[1], c.endVals[1]));
				s.chB.push(key(c.startVals[2], c.endVals[2]));
			case 'P':
				s.params.push({type: c.paramType, s: st, e: en});
		}
	}

	static inline function sortChannel(ch:Array<OsuSbKey>)
		ch.sort((a, b) -> (a.s < b.s) ? -1 : (a.s > b.s ? 1 : 0));

	override public function update(elapsed:Float) {
		var t:Float = Conductor.songPosition + timeOffsetMs;
		updateSamples(t);
		for (sprite in members) {
			if (sprite == null)
				continue;
			if (t < sprite.boundsMin || t > sprite.boundsMax) {
				sprite.visible = false;
				continue;
			}
			sprite.visible = true;
			applyAt(sprite, t);
		}
		super.update(elapsed);
	}

	function updateSamples(t:Float) {
		if (!soundsEnabled || samples.length < 1)
			return;
		if (t < lastT - 5)
			sampleIdx = 0; // backward jump (restart / seek): replay from the start
		lastT = t;
		while (sampleIdx < samples.length && samples[sampleIdx].time <= t) {
			var s:OsuSbSample = samples[sampleIdx++];
			if (t - s.time < SAMPLE_FIRE_WINDOW) // skip ones long past a forward seek
				playSample(s);
		}
	}

	function playSample(s:OsuSbSample) {
		#if sys
		var snd:Sound = resolveSound(s.path);
		if (snd == null)
			return;
		try {
			snd.play(0, 0, new SoundTransform((s.volume / 100) * ClientPrefs.data.hitsoundVolume * FlxG.sound.volume));
		} catch (e:Dynamic) {}
		#end
	}

	#if sys
	function resolveSound(osuPath:String):Sound {
		var key:String = osuPath.toLowerCase();
		if (sampleCache.exists(key))
			return sampleCache.get(key);

		var snd:Sound = null;
		var file:String = resolveFile(soundDir, osuPath);
		if (file != null) {
			try {
				// Sound.fromFile returns null for external-storage files on Android; AssetUtil decodes bytes.
				#if mobile
				snd = mobile.backend.AssetUtil.getSound(file);
				#else
				snd = Sound.fromFile(file);
				#end
			} catch (e:Dynamic) {
				snd = null;
			}
		}
		sampleCache.set(key, snd);
		return snd;
	}
	#end

	function applyAt(s:OsuSbRuntimeSprite, t:Float) {
		s.alpha = channel(s.chAlpha, t, 1);
		if (s.alpha <= 0) {
			s.visible = false;
			return;
		}

		var sx:Float = channel(s.chScaleX, t, 1) * scale;
		var sy:Float = channel(s.chScaleY, t, 1) * scale;
		s.scale.set(sx, sy);

		s.origin.set(s.originFracX * s.frameWidth, s.originFracY * s.frameHeight);
		var osuX:Float = s.chX.length > 0 ? channel(s.chX, t, s.baseX) : s.baseX;
		var osuY:Float = s.chY.length > 0 ? channel(s.chY, t, s.baseY) : s.baseY;
		s.x = osuX * scale + offsetX - s.origin.x;
		s.y = osuY * scale + offsetY - s.origin.y;

		s.angle = channel(s.chRot, t, 0) * 180 / Math.PI;

		if (s.chR.length > 0 || s.chG.length > 0 || s.chB.length > 0) {
			s.color = FlxColor.fromRGB(clampByte(channel(s.chR, t, 255)), clampByte(channel(s.chG, t, 255)), clampByte(channel(s.chB, t, 255)));
		} else
			s.color = FlxColor.WHITE;

		applyParams(s, t);

		if (s.frames2 != null)
			applyAnimationFrame(s, t);
	}

	function applyParams(s:OsuSbRuntimeSprite, t:Float) {
		var flipH:Bool = false, flipV:Bool = false, additive:Bool = false;
		for (p in s.params) {
			var active:Bool = (p.e > p.s) ? (t >= p.s && t <= p.e) : (t >= p.s);
			if (!active)
				continue;
			switch (p.type) {
				case 'H':
					flipH = true;
				case 'V':
					flipV = true;
				case 'A':
					additive = true;
			}
		}
		s.flipX = flipH;
		s.flipY = flipV;
		s.blend = additive ? BlendMode.ADD : BlendMode.NORMAL;
	}

	function applyAnimationFrame(s:OsuSbRuntimeSprite, t:Float) {
		var count:Int = s.frames2.length;
		if (count < 1 || s.frameDelay <= 0)
			return;
		var idx:Int = Std.int((t - s.boundsMin) / s.frameDelay);
		if (idx < 0)
			idx = 0;
		idx = s.loopForever ? (idx % count) : (idx >= count ? count - 1 : idx);
		if (idx != s.lastFrame) {
			s.lastFrame = idx;
			s.loadGraphic(s.frames2[idx]);
		}
	}

	function channel(ch:Array<OsuSbKey>, t:Float, def:Float):Float {
		if (ch.length < 1)
			return def;
		if (t <= ch[0].s)
			return ch[0].a;
		var result:Float = ch[0].a;
		for (k in ch) {
			if (t < k.s)
				return result;
			if (t <= k.e)
				return interp(k, t);
			result = k.b;
		}
		return result;
	}

	static inline function interp(k:OsuSbKey, t:Float):Float {
		if (k.e <= k.s)
			return k.b;
		var p:Float = ease(k.ease, (t - k.s) / (k.e - k.s));
		return k.a + (k.b - k.a) * p;
	}

	static function layerPriority(layer:String):Int {
		return switch (layer) {
			case 'Background': 0;
			case 'Fail', 'Pass': 1;
			case 'Foreground': 2;
			case 'Overlay': 3;
			default: 0;
		}
	}

	static function originFrac(origin:String):{x:Float, y:Float} {
		return switch (origin) {
			case 'TopLeft', '0': {x: 0, y: 0};
			case 'TopCentre', 'TopCenter': {x: 0.5, y: 0};
			case 'TopRight': {x: 1, y: 0};
			case 'CentreLeft', 'CenterLeft': {x: 0, y: 0.5};
			case 'CentreRight', 'CenterRight': {x: 1, y: 0.5};
			case 'BottomLeft': {x: 0, y: 1};
			case 'BottomCentre', 'BottomCenter': {x: 0.5, y: 1};
			case 'BottomRight': {x: 1, y: 1};
			default: {x: 0.5, y: 0.5}; // Centre and unknowns
		}
	}

	static function ease(id:Int, p:Float):Float {
		return switch (id) {
			case 1, 4: FlxEase.quadOut(p);
			case 2, 3: FlxEase.quadIn(p);
			case 5: FlxEase.quadInOut(p);
			case 6: FlxEase.cubeIn(p);
			case 7: FlxEase.cubeOut(p);
			case 8: FlxEase.cubeInOut(p);
			case 9: FlxEase.quartIn(p);
			case 10: FlxEase.quartOut(p);
			case 11: FlxEase.quartInOut(p);
			case 12: FlxEase.quintIn(p);
			case 13: FlxEase.quintOut(p);
			case 14: FlxEase.quintInOut(p);
			case 15: FlxEase.sineIn(p);
			case 16: FlxEase.sineOut(p);
			case 17: FlxEase.sineInOut(p);
			case 18: FlxEase.expoIn(p);
			case 19: FlxEase.expoOut(p);
			case 20: FlxEase.expoInOut(p);
			case 21: FlxEase.circIn(p);
			case 22: FlxEase.circOut(p);
			case 23: FlxEase.circInOut(p);
			case 24: FlxEase.elasticIn(p);
			case 25: FlxEase.elasticOut(p);
			case 26: FlxEase.elasticInOut(p);
			case 27: FlxEase.backIn(p);
			case 28: FlxEase.backOut(p);
			case 29: FlxEase.backInOut(p);
			case 30: FlxEase.bounceIn(p);
			case 31: FlxEase.bounceOut(p);
			case 32: FlxEase.bounceInOut(p);
			default: p; // 0 = linear
		}
	}

	static inline function clampByte(v:Float):Int {
		var i:Int = Std.int(v + 0.5);
		return (i < 0) ? 0 : (i > 255 ? 255 : i);
	}

	override public function destroy() {
		super.destroy();
		if (bitmapCache != null) {
			for (g in bitmapCache)
				if (g != null)
					g.destroy();
			bitmapCache.clear();
		}
		#if sys
		if (sampleCache != null)
			sampleCache.clear();
		#end
	}

	function resolveGraphic(osuPath:String):FlxGraphic {
		if (osuPath == null || osuPath.length < 1)
			return null;
		var key:String = osuPath.toLowerCase();
		if (bitmapCache.exists(key))
			return bitmapCache.get(key);

		var graphic:FlxGraphic = null;
		#if sys
		var file:String = resolveFile(imageDir, osuPath);
		if (file != null) {
			try {
				// BitmapData.fromFile returns null for external-storage files on Android; AssetUtil decodes bytes.
				#if mobile
				var bmp:BitmapData = mobile.backend.AssetUtil.getBitmap(file);
				#else
				var bmp:BitmapData = BitmapData.fromFile(file);
				#end
				if (bmp != null) {
					graphic = FlxGraphic.fromBitmapData(bmp, false, key, false);
					graphic.destroyOnNoUse = false;
				}
			} catch (e:Dynamic) {
				graphic = null;
			}
		}
		#end
		bitmapCache.set(key, graphic);
		return graphic;
	}

	#if sys
	function resolveFile(baseDir:String, osuPath:String):String {
		var rel:String = osuPath.split('\\').join('/');
		var direct:String = Path.join([baseDir, rel]);
		if (FileSystem.exists(direct))
			return direct;

		var dir:String = baseDir;
		var parts:Array<String> = rel.split('/');
		for (i in 0...parts.length) {
			if (!FileSystem.exists(dir) || !FileSystem.isDirectory(dir))
				return null;
			var want:String = parts[i].toLowerCase();
			var found:String = null;
			for (entry in FileSystem.readDirectory(dir))
				if (entry.toLowerCase() == want) {
					found = entry;
					break;
				}
			if (found == null)
				return null;
			dir = Path.join([dir, found]);
		}
		return FileSystem.exists(dir) ? dir : null;
	}
	#end
}
