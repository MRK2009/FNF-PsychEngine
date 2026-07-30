package objects;

class BGSprite extends FlxSprite {
	private var idleAnim:String;

	public function new(image:String, x:Float = 0, y:Float = 0, ?scrollX:Float = 1, ?scrollY:Float = 1, ?animArray:Array<String> = null, ?loop:Bool = false) {
		super(x, y);

		if (animArray != null) {
			frames = Paths.getSparrowAtlas(image);
			addAnims(animArray, loop);
		} else {
			if (image != null) {
				loadGraphic(Paths.image(image));
			}
			active = false;
		}
		scrollFactor.set(scrollX, scrollY);
		antialiasing = ClientPrefs.data.antialiasing;
	}

	/**
		Adds one animation per prefix, the first becoming the idle.

		Kept out of the constructor deliberately: mods subclass this through the scripted bridge, which
		re-emits the constructor from its typed form, and a loop there carries compiler temporaries that
		cannot be printed back as valid syntax. Only the constructor is re-emitted, so a loop is fine
		anywhere else.
	**/
	function addAnims(animArray:Array<String>, loop:Bool):Void {
		for (anim in animArray) {
			animation.addByPrefix(anim, anim, 24, loop);
			if (idleAnim == null) {
				idleAnim = anim;
				animation.play(anim);
			}
		}
	}

	public function dance(?forceplay:Bool = false) {
		if (idleAnim != null) {
			animation.play(idleAnim, forceplay);
		}
	}
}
