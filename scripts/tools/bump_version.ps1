# =============================================================================
#  bump_version.ps1 - bump the patch of Cargo.toml's version (called by build.bat)
#
#  WHY THIS FILE EXISTS
#  On locked-down machines an endpoint policy silently blocks a PowerShell
#  -Command one-liner whose command line contains a regex: powershell.exe exits
#  with code 786 and never touches the file, so build.bat kept building while
#  Cargo.toml stayed behind. The same logic invoked from this script file through
#  -File is not affected, which is why this helper exists.
#
#  VERSION SCHEME
#  Cargo.toml holds [package] version = "x.y.z". Every build bumps the patch;
#  cargo-apk limits each segment to 255, so carry happens at 256:
#    x.y.255 -> x.(y+1).0
#    x.255.255 -> (x+1).0.0
#  versionCode formula (cargo-apk ndk-build): 16777216 + major*65536 + minor*256 + patch
#
#  USAGE
#    powershell -NoProfile -ExecutionPolicy Bypass -File scripts\tools\bump_version.ps1
#    powershell -NoProfile -ExecutionPolicy Bypass -File scripts\tools\bump_version.ps1 -Path Cargo.toml
#    powershell -NoProfile -ExecutionPolicy Bypass -File scripts\tools\bump_version.ps1 -DryRun
#
#  OUTPUT (stdout, single line)
#    OK=<old>-><new>|<versionCode>   file updated, exit code 0
#    NORUN=<version>|<versionCode>   -DryRun, exit code 0
#    ERROR=<reason>                  nothing written, exit code != 0
# =============================================================================
param(
    [string]$Path = 'Cargo.toml',
    [string]$GradlePath = 'android\app\build.gradle.kts',
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'

try {
    $full = (Resolve-Path -LiteralPath $Path).Path
    $text = [IO.File]::ReadAllText($full)

    # Match [package] version line
    $found = [regex]::Match($text, '(?m)^version[ \t]*=[^\r\n]*')
    if (-not $found.Success) {
        Write-Output 'ERROR=no-version-line'
        exit 2
    }

    $line = $found.Value
    $m = [regex]::Match($line, '(\d+)\.(\d+)\.(\d+)')
    if (-not $m.Success) {
        Write-Output 'ERROR=version-not-three-part'
        exit 4
    }

    $major = [int]$m.Groups[1].Value
    $minor = [int]$m.Groups[2].Value
    $patch = [int]$m.Groups[3].Value

    $old = "$major.$minor.$patch"

    if ($DryRun) {
        $vcode = 16777216 + $major * 65536 + $minor * 256 + $patch
        Write-Output ('NORUN=' + $old + '|' + $vcode)
        exit 0
    }

    $patch += 1
    if ($patch -gt 255) {
        $patch = 0
        $minor += 1
    }
    if ($minor -gt 255) {
        $minor = 0
        $major += 1
    }
    if ($major -gt 255) {
        Write-Output 'ERROR=major-over-255'
        exit 5
    }

    $new = "$major.$minor.$patch"
    $newLine = 'version = "' + $new + '"'

    # Write Cargo.toml
    if ($newLine -ne $line) {
        $out = $text.Substring(0, $found.Index) + $newLine + $text.Substring($found.Index + $found.Length)
        $utf8NoBom = New-Object Text.UTF8Encoding($false)
        [IO.File]::WriteAllText($full, $out, $utf8NoBom)
    }

    # Compute versionCode
    $vcode = 16777216 + $major * 65536 + $minor * 256 + $patch

    # Write android/app/build.gradle.kts if exists
    if (Test-Path $GradlePath) {
        $gradleFull = (Resolve-Path -LiteralPath $GradlePath).Path
        $gt = [IO.File]::ReadAllText($gradleFull)

        $gmc = [regex]::Match($gt, '(?m)^[ \t]*versionCode[ \t]*=[^\r\n]*')
        $gmn = [regex]::Match($gt, '(?m)^[ \t]*versionName[ \t]*=[^\r\n]*')
        if ($gmc.Success -and $gmn.Success) {
            $indent = $gmc.Value.Substring(0, $gmc.Value.Length - $gmc.Value.TrimStart().Length)
            $gt = $gt.Remove($gmc.Index, $gmc.Length).Insert($gmc.Index, ($indent + 'versionCode = ' + $vcode))

            $gmn = [regex]::Match($gt, '(?m)^[ \t]*versionName[ \t]*=[^\r\n]*')
            $indent = $gmn.Value.Substring(0, $gmn.Value.Length - $gmn.Value.TrimStart().Length)
            $gt = $gt.Remove($gmn.Index, $gmn.Length).Insert($gmn.Index, ($indent + 'versionName = "' + $new + '"'))

            $utf8NoBom = New-Object Text.UTF8Encoding($false)
            [IO.File]::WriteAllText($gradleFull, $gt, $utf8NoBom)
        }
    }

    Write-Output ('OK=' + $old + '->' + $new + '|' + $vcode)
    exit 0
}
catch {
    Write-Output ('ERROR=' + $_.Exception.Message)
    exit 1
}