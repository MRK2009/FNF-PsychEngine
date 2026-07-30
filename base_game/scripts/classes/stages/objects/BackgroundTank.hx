package stages.objects;

/**
	The tank rolling along the horizon. Ported from the compiled version.

	Extends `FlxSprite` and does inline what `BGSprite`'s constructor would, rather than extending
	`BGSprite` like the compiled one did: through the bridge, that constructor threw
	"Null Function Pointer" here for reasons I could not reproduce in isolation -- a zero-argument
	scripted constructor passing all seven of `BGSprite`'s arguments works fine against a shallow
	stand-in base, and `MallCrowd`/`PhillyTrain` extend `BGSprite` happily. Worth another look; the
	behaviour below is identical either way.
**/
class BackgroundTank extends FlxSprite {
	public var offsetX:Float = 400;
	public var offsetY:Float = 1300;
	public var tankSpeed:Float = 0;
	public var tankAngle:Float = 0;

	var idleAnim:String = 'BG tank w lighting';

	public function new() {
		super(0, 0);

		frames = Paths.getSparrowAtlas('tankRolling');
		animation.addByPrefix(idleAnim, idleAnim, 24, true);
		animation.play(idleAnim);
		scrollFactor.set(0.5, 0.5);

		tankSpeed = FlxG.random.float(5, 7);
		tankAngle = FlxG.random.int(-90, 45);
		antialiasing = ClientPrefs.data.antialiasing;
	}

	/** Matches `BGSprite.dance`, which the compiled version inherited. **/
	public function dance(forceplay:Bool = false):Void {
		animation.play(idleAnim, forceplay);
	}

	override function update(elapsed:Float):Void {
		super.update(elapsed);

		tankAngle += elapsed * tankSpeed;
		angle = tankAngle - 90 + 15;
		x = offsetX + 1500 * Math.cos(Math.PI / 180 * (tankAngle + 180));
		y = offsetY + 1100 * Math.sin(Math.PI / 180 * (tankAngle + 180));
	}
}
