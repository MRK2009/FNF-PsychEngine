package stages.objects;

/**
	The train that crosses Philly, dragging gf's hair with it. Ported from the compiled version.

	Extends `FlxSprite` and does inline what `BGSprite`'s constructor would, rather than extending
	`BGSprite` like the compiled one did. Through the bridge that constructor threw "Null Function
	Pointer" here, the same way it did for `BackgroundTank`, and neither reproduces against a stand-in
	base: a scripted subclass calling `super` with a subset of its arguments, a nested static chain in
	the constructor and a typed field with no initialiser all behave correctly in isolation. Whatever
	it is needs the real bridge over `FlxSprite`'s hierarchy. The behaviour below is identical.
**/
class PhillyTrain extends FlxSprite {
	public var sound:FlxSound;

	public var moving:Bool = false;
	public var finishing:Bool = false;
	public var startedMoving:Bool = false;

	/** Simulates a 24fps cap. **/
	public var frameTiming:Float = 0;

	public var cars:Int = 8;
	public var cooldown:Int = 0;

	public function new(x:Float = 0, y:Float = 0, image:String = 'philly/train', soundName:String = 'train_passes') {
		super(x, y);

		loadGraphic(Paths.image(image));
		scrollFactor.set(1, 1);
		active = true; // Allow update
		antialiasing = ClientPrefs.data.antialiasing;

		sound = new FlxSound();
		sound.loadEmbedded(Paths.sound(soundName));
		FlxG.sound.list.add(sound);
	}

	override function update(elapsed:Float):Void {
		if (moving) {
			frameTiming += elapsed;
			if (frameTiming >= 1 / 24) {
				if (sound.time >= 4700) {
					startedMoving = true;
					if (PlayState.instance.gf != null) {
						PlayState.instance.gf.playAnim('hairBlow');
						PlayState.instance.gf.specialAnim = true;
					}
				}

				if (startedMoving) {
					x -= 400;
					if (x < -2000 && !finishing) {
						x = -1150;
						cars -= 1;

						if (cars <= 0) {
							finishing = true;
						}
					}

					if (x < -4000 && finishing) {
						restart();
					}
				}
				frameTiming = 0;
			}
		}
		super.update(elapsed);
	}

	public function beatHit(curBeat:Int):Void {
		if (!moving) {
			cooldown += 1;
		}

		if (curBeat % 8 == 4 && FlxG.random.bool(30) && !moving && cooldown > 8) {
			cooldown = FlxG.random.int(-4, 0);
			start();
		}
	}

	public function start():Void {
		moving = true;
		if (!sound.playing) {
			sound.play(true);
		}
	}

	public function restart():Void {
		if (PlayState.instance.gf != null) {
			// Makes her bop her head to the correct side once the animation ends.
			PlayState.instance.gf.danced = false;
			PlayState.instance.gf.playAnim('hairFall');
			PlayState.instance.gf.specialAnim = true;
		}
		x = FlxG.width + 200;
		moving = false;
		cars = 8;
		finishing = false;
		startedMoving = false;
	}
}
