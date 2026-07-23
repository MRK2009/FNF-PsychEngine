package backend;

/**
	Detection strategies for the "Detect Hardware" audio-delay button in the offset calibrator.

	- `BufferEstimate`: derive the output latency from the live OpenAL-Soft buffering config. Cheap,
	  always safe, but only an estimate of the buffered-output delay (see `ALSoftConfig.outputLatencyMs`).
	- `MicLoopback`: play a click and time when it returns through the microphone for a true round-trip
	  measurement. Not implemented yet -- the engine has no capture path -- but the front door is shaped
	  so it can be added without touching the menu callers.
**/
enum LatencyMethod {
	BufferEstimate;
	MicLoopback;
}

/**
	Single entry point for estimating the system's audio delay, so callers ask for a number without
	caring which strategy produced it. Today only `BufferEstimate` yields a value.
**/
class LatencyProbe {
	/** Whether `method` can currently produce an estimate on this platform/build. **/
	public static function available(method:LatencyMethod = BufferEstimate):Bool {
		return estimateMs(method) != null;
	}

	/**
		Estimated audio output delay in milliseconds, or `null` if the chosen `method` can't measure on
		this platform/build (the caller should then disable / grey out the button).
	**/
	public static function estimateMs(method:LatencyMethod = BufferEstimate):Null<Int> {
		return switch (method) {
			case BufferEstimate: ALSoftConfig.outputLatencyMs();
			case MicLoopback: measureMicLoopback();
		}
	}

	/**
		Future: click-and-capture round-trip measurement. Returns `null` until a capture path exists so
		`available(MicLoopback)` reports false and the buffer estimate stays the shipping default.
	**/
	static function measureMicLoopback():Null<Int> {
		return null;
	}
}
