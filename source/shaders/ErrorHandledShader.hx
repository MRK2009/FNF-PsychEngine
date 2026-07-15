package shaders;

import flixel.graphics.tile.FlxGraphicsShader;
import flixel.system.FlxAssets.FlxShader;
import flixel.addons.display.FlxRuntimeShader;
import lime.graphics.opengl.GLProgram;
#if desktop
import lime.app.Application;
#end

/**
 * `FlxShader` that survives a failed GL compile/link instead of crashing the game.
 *
 * On failure it logs a crash file, then compiles and returns flixel's DEFAULT sprite shader in
 * place of the broken one, so the sprite renders plain. Returning `null` is not an option:
 * openfl caches a `Program3D` wrapper around the result and immediately resolves every uniform
 * against it, so a null program null-derefs on the next line of openfl code. Standard `openfl_*`
 * uniforms resolve against the fallback and custom ones come back -1, which GL ignores.
 */
class ErrorHandledShader extends FlxShader implements IErrorHandler {
	public var shaderName:String = '';

	public dynamic function onError(error:Dynamic):Void {}

	public function new(?shaderName:String) {
		this.shaderName = shaderName;
		super();
	}

	override function __createGLProgram(vertexSource:String, fragmentSource:String):GLProgram {
		#if mobile
		vertexSource = sanitizeForGLES(vertexSource);
		fragmentSource = sanitizeForGLES(fragmentSource);
		#end
		try {
			return super.__createGLProgram(vertexSource, fragmentSource);
		} catch (error) {
			crashSave(this.shaderName, error, onError);
			var fallback:Array<String> = fallbackSources();
			try {
				return super.__createGLProgram(fallback[0], fallback[1]);
			} catch (dead:Dynamic) {
				return null;
			}
		}
	}

	#if mobile
	/**
	 * GLES compatibility pass for mod shaders written against desktop GL.
	 *
	 * openfl prepends its `#ifdef GL_ES` precision block above the source, so a shader's own
	 * `#version` line ends up mid-file -- GLES requires it to be the very first statement and
	 * rejects the whole compile, where desktop drivers shrug. Desktop version pragmas mean
	 * nothing on GLES anyway (ES 100 is the closest dialect), so drop them.
	 */
	public static function sanitizeForGLES(source:String):String {
		if (source == null || source.indexOf('#version') < 0)
			return source;
		return new EReg('^[ \\t]*#version[^\\n]*', 'gm').replace(source, '');
	}
	#end

	/**
	 * Flixel's default sprite-shader sources as `[vertex, fragment]`, prefixed the way openfl
	 * prefixes what it hands `__createGLProgram`. The donor's metadata sources are macro-expanded
	 * at compile time and construction never touches GL, so this is safe mid-failure.
	 */
	public static function fallbackSources():Array<String> {
		var donor:FlxGraphicsShader = new FlxGraphicsShader();
		var prefix:String = '#ifdef GL_ES\n'
			+ '#ifdef GL_FRAGMENT_PRECISION_HIGH\n'
			+ 'precision highp float;\n'
			+ '#else\n'
			+ 'precision mediump float;\n'
			+ '#endif\n'
			+ '#endif\n\n';
		return [prefix + donor.glVertexSource, prefix + donor.glFragmentSource];
	}

	/** Shader names already reported this session, so one broken shader on many sprites logs once. **/
	static var reported:Map<String, Bool> = new Map();

	/**
	 * Reports a failed shader without killing the game. Runs on the RENDER thread (programs are
	 * created mid-draw), so everything here is guarded: the crash-file write can itself fail
	 * (denied storage on Android), and blocking message boxes are desktop-only.
	 */
	public static function crashSave(shaderName:String, error:Dynamic, onError:Dynamic) {
		if (shaderName == null)
			shaderName = 'unnamed';

		trace('Error on Shader "$shaderName": $error');

		if (!reported.exists(shaderName)) {
			reported.set(shaderName, true);

			#if !debug
			try {
				var dateNow:String = Date.now().toString().replace(' ', '_').replace(':', "'");
				if (!FileSystem.exists('./crash/'))
					FileSystem.createDirectory('./crash/');
				var crashLogPath:String = './crash/shader_${shaderName}_$dateNow.txt';
				File.saveContent(crashLogPath, Std.string(error));
				#if desktop
				Application.current.window.alert('Error log saved at: $crashLogPath', 'Error on Shader: "$shaderName"');
				#end
			} catch (e:Dynamic) {}
			#elseif desktop
			Application.current.window.alert('Error logs aren\'t created on debug builds, check the trace log instead.',
				'Error on Shader: "$shaderName"');
			#end
		}

		if (onError != null)
			onError(error);
	}
}

/** Runtime (mod-supplied) variant of `ErrorHandledShader`: same failure handling. **/
class ErrorHandledRuntimeShader extends FlxRuntimeShader implements IErrorHandler {
	public var shaderName:String = '';

	public dynamic function onError(error:Dynamic):Void {}

	public function new(?shaderName:String, ?fragmentSource:String, ?vertexSource:String) {
		this.shaderName = shaderName;
		super(fragmentSource, vertexSource);
	}

	override function __createGLProgram(vertexSource:String, fragmentSource:String):GLProgram {
		#if mobile
		vertexSource = ErrorHandledShader.sanitizeForGLES(vertexSource);
		fragmentSource = ErrorHandledShader.sanitizeForGLES(fragmentSource);
		#end
		try {
			return super.__createGLProgram(vertexSource, fragmentSource);
		} catch (error) {
			ErrorHandledShader.crashSave(this.shaderName, error, onError);
			var fallback:Array<String> = ErrorHandledShader.fallbackSources();
			try {
				return super.__createGLProgram(fallback[0], fallback[1]);
			} catch (dead:Dynamic) {
				return null;
			}
		}
	}
}

interface IErrorHandler {
	public var shaderName:String;
	public dynamic function onError(error:Dynamic):Void;
}
