package backend;

using StringTools;

/**
	A single clickable link shown on a credit person's info panel.
**/
typedef CreditLink = {
	/** The text shown for the link (e.g. `Social`); defaults to the URL's domain when blank. **/
	label:String,

	/** The URL opened in the browser when the link is activated. **/
	url:String
};

/**
	One credited contributor: their display name, icon, role text, accent colour and links. Built
	either from the hard-coded engine list (`person`) or from a mod's credits file (`parsePersonObj` /
	`parseModTxt`).
**/
typedef CreditPerson = {
	/** Display name shown in the grid and info panel. **/
	name:String,

	/** Icon image key under `images/` (e.g. `credits/lulu`), or null for the default icon. **/
	?icon:String,

	/** Role/description text; may contain `\n` for line breaks. **/
	?role:String,

	/** Accent colour as a hex string (e.g. `8A6FB0`); tints the background/swatch. **/
	?color:String,

	/** Full-screen background image key shown when this person is selected, or null. **/
	?background:String,

	/** The person's links (zero or more). **/
	links:Array<CreditLink>,

	/** Owning mod folder for asset resolution, or null for engine credits. **/
	?modFolder:String
};

/**
	A named group of credited people (one row in the credits sidebar), e.g. `Special Thanks`.
**/
typedef CreditSection = {
	/** Section title shown in the sidebar/header. **/
	name:String,

	/** The people in this section. **/
	people:Array<CreditPerson>,

	/** Owning mod folder for asset resolution, or null for engine sections. **/
	?modFolder:String,

	/** Section-wide background image key (a person's own `background` overrides it), or null. **/
	?background:String,

	/** Section-wide accent colour as a hex string (a person's own `color` overrides it), or null. **/
	?color:String
};

/**
	Source of truth for the credits screen (`CreditsState`). Provides the hard-coded engine credits and
	merges in per-mod credits read from each enabled mod's `data/credits.json` or `data/credits.txt`.
**/
class CreditsData {
	/**
		Builds the full ordered credits list: the engine sections first, then one or more sections per
		enabled mod (empty mod sections are skipped).
		@return every credit section to display, in order
	**/
	public static function build():Array<CreditSection> {
		var sections:Array<CreditSection> = engineSections();
		#if MODS_ALLOWED
		for (folder in Mods.parseList().enabled) {
			for (s in loadModSections(folder))
				if (s.people.length > 0)
					sections.push(s);
		}
		#end
		return sections;
	}

	/**
		The hard-coded engine credits.
		@return the built-in credit sections
	**/
	static function engineSections():Array<CreditSection> {
		return [
			section('PE Continued', [
				person('Lulu', 'lulu', 'Maintainer', 'https://github.com/MeguminBOT', '8A6FB0'),
				person('Picsel', 'picsel', 'Freeplay Star Icon\nLulu icon', 'https://twitter.com/Picsel326', '50346B'),
			]),
			section('Special Thanks', [
				person('Vortex2Oblivion', '', 'hxhardware and multikey code inspiration', '', '888888'),
				person('Inky03', '', 'HScript Insanity', '', '888888'),
				person('MCO7', '', 'For the "fixed" note assets', [
					{
						label: 'Social',
						url: 'https://gamebanana.com/members/1945940'
					},
					{label: 'Skin download', url: 'https://gamebanana.com/mods/509970'}
				], '888888'),
			]),
			section('Psych Engine Team', [
				person('Shadow Mario', 'shadowmario', 'Main Programmer and Head of Psych Engine', 'https://ko-fi.com/shadowmario', '444444'),
				person('Riveren', 'riveren', 'Main Artist/Animator of Psych Engine', 'https://x.com/riverennn', '14967B'),
			]),
			section('Former Engine Members', [
				person('bb-panzu', 'bb', 'Ex-Programmer of Psych Engine', 'https://x.com/bbsub3', '3E813A'),
			]),
			section('Engine Contributors', [
				person('crowplexus', 'crowplexus', 'Linux Support, HScript Iris, Input System v3, and Other PRs', 'https://twitter.com/IamMorwen', 'CFCFCF'),
				person('Kamizeta', 'kamizeta', "Creator of Pessy, Psych Engine's mascot.", 'https://www.instagram.com/cewweey/', 'D21C11'),
				person('MaxNeton', 'maxneton', 'Loading Screen Easter Egg Artist/Animator.', 'https://bsky.app/profile/maxneton.bsky.social', '3C2E4E'),
				person('Keoiki', 'keoiki', 'Note Splash Animations and Latin Alphabet', 'https://x.com/Keoiki_', 'D2D2D2'),
				person('SqirraRNG', 'sqirra', "Crash Handler and Base code for\nChart Editor's Waveform", 'https://x.com/gedehari', 'E1843A'),
				person('EliteMasterEric', 'mastereric', 'Runtime Shaders support and Other PRs', 'https://x.com/EliteMasterEric', 'FFBD40'),
				person('MAJigsaw77', 'majigsaw', 'Android extensions, hxluajit, and the\n.MP4 Video Loader Library (hxvlc)', 'https://x.com/MAJigsaw77',
					'5F5F5F'),
				person('iFlicky', 'flicky', 'Composer of Psync and Tea Time\nAnd some sound effects', 'https://x.com/flicky_i', '9E29CF'),
				person('KadeDev', 'kade', 'Fixed some issues on Chart Editor and Other PRs', 'https://x.com/kade0912', '64A250'),
				person('superpowers04', 'superpowers04', 'LUA JIT Fork', 'https://x.com/superpowers04', 'B957ED'),
				person('CheemsAndFriends', 'cheems', 'Creator of FlxAnimate', 'https://x.com/CheemsnFriendos', 'E1E1E1'),
			]),
			section("Funkin' Crew", [
				person('ninjamuffin99', 'ninjamuffin99', "Programmer of Friday Night Funkin'", 'https://x.com/ninja_muffin99', 'CF2D2D'),
				person('PhantomArcade', 'phantomarcade', "Animator of Friday Night Funkin'", 'https://x.com/PhantomArcade3K', 'FADC45'),
				person('evilsk8r', 'evilsk8r', "Artist of Friday Night Funkin'", 'https://x.com/evilsk8r', '5ABD4B'),
				person('kawaisprite', 'kawaisprite', "Composer of Friday Night Funkin'", 'https://x.com/kawaisprite', '378FC7'),
			]),
			section('Psych Engine Discord', [
				person('Join the Psych Ward!', 'discord', '', 'https://discord.gg/2ka77eMXDv', '5165F6'),
			]),
		];
	}

	/**
		Builds an engine `CreditSection` (no owning mod).
		@param name the section title
		@param people the section's members
		@param color optional section-wide accent colour (hex string)
		@return the section
	**/
	static inline function section(name:String, people:Array<CreditPerson>, ?color:String):CreditSection {
		return {
			name: name,
			people: people,
			modFolder: null,
			background: null,
			color: color
		};
	}

	/**
		Builds a `CreditPerson`.
		@param name the display name
		@param icon icon image key (bare names are resolved under `credits/`), or `''`/null for none
		@param role the role/description text (`\n` allowed)
		@param link either a single URL `String` (auto-labelled from its domain) or an
			   `Array<CreditLink>` for multiple links (each `{label, url}`; a blank label falls back to
			   the URL's domain). Every existing single-URL call keeps working unchanged.
		@param color the accent colour as a hex string
		@param modFolder owning mod folder for asset resolution, or null for engine credits
		@return the person
	**/
	static function person(name:String, icon:String, role:String, link:Dynamic, color:String, ?modFolder:String):CreditPerson {
		var links:Array<CreditLink> = [];
		if (Std.isOfType(link, String)) {
			var url:String = cast link;
			if (url.length > 4)
				links.push({label: linkLabel(url), url: url});
		} else if (Std.isOfType(link, Array)) {
			var arr:Array<CreditLink> = cast link;
			for (l in arr)
				if (l != null && l.url != null && l.url.length > 0)
					links.push({label: (l.label != null && l.label.length > 0) ? l.label : linkLabel(l.url), url: l.url});
		}
		return {
			name: name,
			icon: normalizeAsset(icon),
			role: role,
			color: color,
			background: null,
			links: links,
			modFolder: modFolder
		};
	}

	#if MODS_ALLOWED
	/**
		Loads a mod's credit sections, preferring its `data/credits.json` (language-specific variant
		first) and falling back to a legacy `data/credits.txt`.
		@param folder the mod folder name
		@return the mod's sections, or an empty array when it ships no credits file
	**/
	static function loadModSections(folder:String):Array<CreditSection> {
		var modName:String = folder;
		var pack:Dynamic = Mods.getPack(folder);
		if (pack != null && Reflect.field(pack, 'name') != null)
			modName = Reflect.field(pack, 'name');

		var jsonPath:String = firstExisting([
			#if TRANSLATIONS_ALLOWED Paths.mods(folder + '/data/credits-${ClientPrefs.data.language}.json'), #end
			Paths.mods(folder + '/data/credits.json')
		]);

		if (jsonPath != null)
			return parseModJson(jsonPath, folder, modName);

		var txtPath:String = firstExisting([
			#if TRANSLATIONS_ALLOWED Paths.mods(folder + '/data/credits-${ClientPrefs.data.language}.txt'), #end
			Paths.mods(folder + '/data/credits.txt')
		]);

		if (txtPath != null)
			return [parseModTxt(txtPath, folder, modName)];

		return [];
	}

	/**
		Parses a mod's `credits.json`. Accepts either a top-level `sections` array or a single bare
		section object. Malformed JSON is logged and treated as no credits.
		@param path the file path
		@param folder the owning mod folder
		@param modName the section name to fall back to (the mod's pack name)
		@return the parsed sections, or an empty array on failure
	**/
	static function parseModJson(path:String, folder:String, modName:String):Array<CreditSection> {
		try {
			var data:Dynamic = tjson.TJSON.parse(File.getContent(path));
			if (data == null)
				return [];

			var rawSections:Array<Dynamic> = Reflect.field(data, 'sections');
			if (rawSections != null) {
				var out:Array<CreditSection> = [];
				for (s in rawSections)
					out.push(parseSectionObj(s, folder, modName));
				return out;
			}
			return [parseSectionObj(data, folder, modName)];
		} catch (e:Dynamic) {
			trace('CreditsData: failed to parse $path -- $e');
			return [];
		}
	}

	/**
		Parses one section object from mod JSON, reading its name from `section` or `name`.
		@param obj the raw JSON section object
		@param folder the owning mod folder
		@param fallbackName the name to use when the object names neither `section` nor `name`
		@return the parsed section
	**/
	static function parseSectionObj(obj:Dynamic, folder:String, fallbackName:String):CreditSection {
		var name:String = strField(obj, 'section');
		if (name == null)
			name = strField(obj, 'name');
		if (name == null)
			name = fallbackName;

		var people:Array<CreditPerson> = [];
		var rawPeople:Array<Dynamic> = Reflect.field(obj, 'people');
		if (rawPeople != null)
			for (p in rawPeople)
				people.push(parsePersonObj(p, folder));

		return {
			name: name,
			people: people,
			modFolder: folder,
			background: normalizeAsset(strField(obj, 'background')),
			color: strField(obj, 'color')
		};
	}

	/**
		Parses one person object from mod JSON. Links come from a `links` array (`{label, url}`); when
		absent, a single `link` URL is used as a fallback.
		@param p the raw JSON person object
		@param folder the owning mod folder
		@return the parsed person
	**/
	static function parsePersonObj(p:Dynamic, folder:String):CreditPerson {
		var links:Array<CreditLink> = [];
		var rawLinks:Array<Dynamic> = Reflect.field(p, 'links');
		if (rawLinks != null) {
			for (l in rawLinks) {
				var url:String = strField(l, 'url');
				if (url != null && url.length > 0) {
					var label:String = strField(l, 'label');
					links.push({label: label != null ? label : linkLabel(url), url: url});
				}
			}
		} else {
			var single:String = strField(p, 'link');
			if (single != null && single.length > 4)
				links.push({label: linkLabel(single), url: single});
		}

		return {
			name: strField(p, 'name'),
			icon: normalizeAsset(strField(p, 'icon')),
			role: strField(p, 'role'),
			color: strField(p, 'color'),
			background: normalizeAsset(strField(p, 'background')),
			links: links,
			modFolder: folder
		};
	}

	/**
		Parses a legacy `credits.txt` into a single section. Each non-blank line is one person with
		`::`-separated fields (`name::icon::role::link::color`); literal `\n` in a field becomes a line
		break.
		@param path the file path
		@param folder the owning mod folder
		@param modName the section name (the mod's pack name)
		@return the parsed section
	**/
	static function parseModTxt(path:String, folder:String, modName:String):CreditSection {
		var people:Array<CreditPerson> = [];
		for (line in File.getContent(path).split('\n')) {
			if (line.trim().length == 0)
				continue;

			var arr:Array<String> = line.replace('\\n', '\n').split('::');
			if (arr[0] == null || arr[0].trim().length == 0)
				continue;

			people.push(person(arr[0], arr.length > 1 ? arr[1] : null, arr.length > 2 ? arr[2] : null, arr.length > 3 ? arr[3] : null,
				arr.length > 4 ? arr[4] : null, folder));
		}
		return {
			name: modName,
			people: people,
			modFolder: folder,
			background: null,
			color: null
		};
	}
	#end

	/**
		@param paths candidate file paths, in priority order
		@return the first path that exists on disk, or null if none do
	**/
	static function firstExisting(paths:Array<String>):String {
		#if sys
		for (p in paths)
			if (p != null && FileSystem.exists(p))
				return p;
		#end
		return null;
	}

	/**
		Reads a field off a dynamic JSON object as a string.
		@param obj the object
		@param field the field name
		@return the field stringified, or null when absent
	**/
	static inline function strField(obj:Dynamic, field:String):String {
		var v:Dynamic = Reflect.field(obj, field);
		return (v != null) ? Std.string(v) : null;
	}

	/**
		Normalizes an icon/background asset key: a bare name is resolved under `credits/`, a name that
		already contains a `/` is left as-is.
		@param name the raw asset name
		@return the normalized key, or null when empty
	**/
	static function normalizeAsset(name:String):String {
		if (name == null || name.length == 0)
			return null;
		return (name.indexOf('/') < 0) ? 'credits/' + name : name;
	}

	/**
		Derives a short link label from a URL: its domain, with the scheme and a leading `www.` stripped.
		@param url the URL
		@return the domain (or the original URL if no domain could be extracted)
	**/
	static function linkLabel(url:String):String {
		var s:String = url;
		var p:Int = s.indexOf('://');
		if (p >= 0)
			s = s.substr(p + 3);
		if (s.startsWith('www.'))
			s = s.substr(4);

		var slash:Int = s.indexOf('/');
		if (slash >= 0)
			s = s.substr(0, slash);
		return s.length > 0 ? s : url;
	}
}
