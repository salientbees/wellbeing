# Process-local workaround for JBR 25 Windows Unix-domain socket paths.
# Does not change persistent environment settings or accept credentials.
param(
    [Parameter(Mandatory=$true, Position=0)] [string]$Executable,
    [Parameter(ValueFromRemainingArguments=$true)] [string[]]$Arguments
)
$ErrorActionPreference = 'Stop'
$javaTemp = if ($env:WELLBEING_JAVA_TMP) { $env:WELLBEING_JAVA_TMP } else { 'C:\development\java-tmp' }
if (-not (Test-Path -LiteralPath $javaTemp -PathType Container)) {
    throw 'Set WELLBEING_JAVA_TMP to an existing short, writable local directory.'
}
if ($javaTemp -match '\s') { throw 'The Java socket directory must not contain spaces.' }
$previousJavaOptions = $env:JAVA_TOOL_OPTIONS
try {
    $env:JAVA_TOOL_OPTIONS = "$previousJavaOptions -Djava.io.tmpdir=$javaTemp -Djdk.net.unixdomain.tmpdir=$javaTemp".Trim()
    & $Executable @Arguments
    $commandExit = $LASTEXITCODE
} finally {
    $env:JAVA_TOOL_OPTIONS = $previousJavaOptions
}
exit $commandExit
