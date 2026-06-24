package backend;

using StringTools;

typedef CreditLink = {
	label:String,
	url:String
};

typedef CreditPerson = {
	name:String,
	?icon:String,
	?role:String,
	?color:String,
	?background:String,
	links:Array<CreditLink>,
	?modFolder:String
};

typedef CreditSection = {
	name:String,
	people:Array<CreditPerson>,
	?modFolder:String,
	?background:String,
	?color:String
};

class CreditsData {
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

	static function engineSections():Array<CreditSection> {
		return [
			section('PE Continued', [
				person('Lulu', 'lulu', 'Maintainer', 'https://github.com/MeguminBOT', '8A6FB0'),
				person('Picsel', 'picsel', 'Freeplay Star Icon\nLulu icon', 'https://twitter.com/Picsel326', '50346B'),
			]),
			section('Special Thanks', [
				person('Vortex2Oblivion', '', 'hxhardware and multikey code inspiration', '', '888888'),
				person('Inky03', '', 'HScript Insanity', '', '888888'),
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

	static inline function section(name:String, people:Array<CreditPerson>, ?color:String):CreditSection {
		return {
			name: name,
			people: people,
			modFolder: null,
			background: null,
			color: color
		};
	}

	static function person(name:String, icon:String, role:String, link:String, color:String, ?modFolder:String):CreditPerson {
		var links:Array<CreditLink> = [];
		if (link != null && link.length > 4)
			links.push({label: linkLabel(link), url: link});
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

	static function firstExisting(paths:Array<String>):String {
		#if sys
		for (p in paths)
			if (p != null && FileSystem.exists(p))
				return p;
		#end
		return null;
	}

	static inline function strField(obj:Dynamic, field:String):String {
		var v:Dynamic = Reflect.field(obj, field);
		return (v != null) ? Std.string(v) : null;
	}

	static function normalizeAsset(name:String):String {
		if (name == null || name.length == 0)
			return null;
		return (name.indexOf('/') < 0) ? 'credits/' + name : name;
	}

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
