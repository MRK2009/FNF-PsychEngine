<#
.SYNOPSIS
    Builds Psych Engine for an x86_64 Android emulator, installs it and launches it.

.DESCRIPTION
    Boots the AVD if it is not already running, builds with -Demulator (which swaps
    the shipping arm64 slice for x86_64 in project.xml), installs the APK, grants
    All Files Access so mods/ and saves on shared storage work without the in-app
    prompt, then starts the game.

    Builds the release variant by default, signed with the keystore in signing.local.xml.
    Pass -DebugBuild for the debug variant (unsigned, with the flixel debug overlay).

.EXAMPLE
    .\setup\android-emulator.ps1
    .\setup\android-emulator.ps1 -DebugBuild -Logcat
    .\setup\android-emulator.ps1 -SkipBuild -Logcat
    .\setup\android-emulator.ps1 -PushMods "mods\MyPack"
#>
[CmdletBinding()]
param(
	[string]   $Avd       = "Pixel_3a_API_34_extension_level_7_x86_64",
	[string]   $Sdk       = $(if ($env:ANDROID_HOME) { $env:ANDROID_HOME } elseif ($env:ANDROID_SDK_ROOT) { $env:ANDROID_SDK_ROOT } else { "Q:\Android\Sdk" }),
	[string]   $Package   = "com.lulu.psychengine",
	[string]   $Skin      = "720x1480",
	[int]      $Memory    = 4096,
	[int]      $Cores     = 8,
	[string[]] $PushMods  = @(),
	[switch]   $SkipEmulator,
	[switch]   $SkipBuild,
	[switch]   $SkipInstall,
	[switch]   $DebugBuild,
	[switch]   $Logcat
)

# Deliberately NOT "Stop": under Windows PowerShell 5.1 anything a native exe writes to stderr
# becomes an ErrorRecord, so "Stop" aborts on benign notes (javac deprecation warnings, adb
# chatter). Failures are detected from $LASTEXITCODE and raised with throw instead.
$ErrorActionPreference = "Continue"
$repo = Split-Path -Parent $PSScriptRoot
$adb  = Join-Path $Sdk "platform-tools\adb.exe"
$emu  = Join-Path $Sdk "emulator\emulator.exe"

foreach ($tool in @($adb, $emu)) {
	if (-not (Test-Path $tool)) { throw "Not found: $tool (set -Sdk or ANDROID_HOME)" }
}

function Get-Emulator {
	$lines = & $adb devices
	foreach ($line in $lines) {
		if ($line -match '^(emulator-\d+)\s+device$') { return $Matches[1] }
	}
	return $null
}

function Initialize-Device {
	$found = Get-Emulator
	if (-not $SkipEmulator -and -not $found) {
		$avds = & $emu -list-avds
		if ($avds -notcontains $Avd) { throw "AVD '$Avd' not found. Available: $($avds -join ', ')" }

		Write-Host "Booting $Avd ..." -ForegroundColor Cyan
		$emuArgs = @(
			"-avd", $Avd,
			"-gpu", "host",
			"-accel", "on",
			"-memory", $Memory,
			"-cores", $Cores,
			"-no-boot-anim",
			"-netdelay", "none",
			"-netspeed", "full"
		)
		if ($Skin) { $emuArgs += @("-skin", $Skin) }
		Start-Process -FilePath $emu -ArgumentList $emuArgs -WorkingDirectory (Split-Path $emu)

		& $adb wait-for-device
		# boot_completed can flip before package manager is serving, which fails the install.
		& $adb shell 'while [ "$(getprop sys.boot_completed)" != "1" ] || ! pm path android >/dev/null 2>&1; do sleep 2; done'
		$found = Get-Emulator
	}

	if ($found) {
		$abi = (& $adb -s $found shell getprop ro.product.cpu.abi).Trim()
		$api = (& $adb -s $found shell getprop ro.build.version.sdk).Trim()
		Write-Host "Device $found ready ($abi, API $api)" -ForegroundColor Green
		if ($abi -ne "x86_64") {
			Write-Warning "Device ABI is $abi but -Demulator builds x86_64. The install will fail."
		}
	}
	return $found
}

$serial = Initialize-Device
if (-not $serial -and -not $SkipInstall) { throw "No emulator is running." }

$variant = if ($DebugBuild) { "debug" } else { "release" }

if (-not $SkipBuild) {
	Write-Host "Building android x86_64 ($variant) ..." -ForegroundColor Cyan
	Push-Location $repo
	$noCwdExe = $env:NoDefaultCurrentDirectoryInExePath
	try {
		# lime runs a bare "gradlew" from the export dir; PowerShell sets this variable for
		# child processes, which makes cmd refuse to resolve it and kills the packaging step.
		$env:NoDefaultCurrentDirectoryInExePath = $null

		$buildArgs = @("run", "lime", "build", "android", "-Demulator")
		if ($DebugBuild) { $buildArgs += "-debug" }
		& haxelib @buildArgs
		if ($LASTEXITCODE -ne 0) { throw "lime build failed with exit code $LASTEXITCODE" }
	} finally {
		$env:NoDefaultCurrentDirectoryInExePath = $noCwdExe
		Pop-Location
	}
}

if ($SkipInstall) { return }

# A long build outlives emulator sessions, so make sure one is still attached.
$serial = Initialize-Device
if (-not $serial) { throw "No emulator is running." }

$apkGlob = Join-Path $repo "export\$variant\android\bin\app\build\outputs\apk\$variant\*.apk"
$apk = Get-ChildItem $apkGlob -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1
if (-not $apk) { throw "No APK found under $apkGlob" }

Write-Host "Installing $($apk.Name) ..." -ForegroundColor Cyan
$installLog = & $adb -s $serial install -r --no-streaming $apk.FullName 2>&1
$installLog | Write-Host
if ($LASTEXITCODE -ne 0) {
	# Debug and release APKs are signed with different keys, so swapping variants needs a
	# clean uninstall. This drops the app's saves and mods on shared storage with it.
	if ($installLog -match "SIGNATURE|UPDATE_INCOMPATIBLE") {
		Write-Warning "Signing key differs from the installed build; uninstalling and retrying."
		& $adb -s $serial uninstall $Package | Out-Null
		& $adb -s $serial install --no-streaming $apk.FullName
	}
	if ($LASTEXITCODE -ne 0) { throw "adb install failed with exit code $LASTEXITCODE" }
}

& $adb -s $serial shell appops set --uid $Package MANAGE_EXTERNAL_STORAGE allow

foreach ($mod in $PushMods) {
	$full = if ([System.IO.Path]::IsPathRooted($mod)) { $mod } else { Join-Path $repo $mod }
	if (-not (Test-Path $full)) { Write-Warning "Skipping missing mod path: $full"; continue }
	Write-Host "Pushing $full ..." -ForegroundColor Cyan
	& $adb -s $serial shell mkdir -p /storage/emulated/0/PsychEngine/mods
	& $adb -s $serial push $full /storage/emulated/0/PsychEngine/mods/
}

Write-Host "Launching $Package ..." -ForegroundColor Cyan
& $adb -s $serial shell monkey -p $Package -c android.intent.category.LAUNCHER 1 | Out-Null

if ($Logcat) {
	& $adb -s $serial logcat -c
	& $adb -s $serial logcat -s SDL:V SDL/APP:V HXCPP:V AndroidRuntime:E libc:F DEBUG:V
}
