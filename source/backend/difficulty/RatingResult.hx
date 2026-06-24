package backend.difficulty;

/**
 * The numeric difficulty rating a `RatingProvider` produces for one chart.
 *
 * `overall` is the single headline number (osu! star value, Etterna Overall MSD, ...).
 * `label` is its pre-formatted display string (e.g. "★ 4.21" or "18.2"). `components`
 * is the optional skillset/sub-rating breakdown (Etterna's 7 skillsets); empty for
 * systems like osu! that only expose a single number.
 */
typedef RatingComponent = {
	var name:String;
	var value:Float;
}

typedef RatingResult = {
	var overall:Float;
	var label:String;
	var components:Array<RatingComponent>;
}
