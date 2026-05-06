$sentinelCtl = Get-ChildItem 'C:\Program Files\SentinelOne' -Recurse -Filter 'sentinelctl.exe' -ErrorAction SilentlyContinue | Select-Object -First 1

if (-not $sentinelCtl) {
    Write-Output 'sentinelctl.exe not found'
    exit 1
}

Write-Output "Found sentinelctl.exe at $($sentinelCtl.FullName)"

$output = & $sentinelCtl.FullName configure 2>&1
$match = $output | Select-String 'server\.mgmtServer\s+(\S+)'
$mgmtServer = if ($match) { $match.Matches[0].Groups[1].Value.Trim() } else { $null }

if (-not $mgmtServer) {
    Write-Output 'server.mgmtServer value not found in sentinelctl output'
    exit 1
}

Write-Output "Extracted mgmtServer: $mgmtServer"

$ninjaCli = 'C:\ProgramData\NinjaRMMAgent\ninjarmm-cli.exe'
$useCliDirect = ($PSVersionTable.PSVersion.Major -lt 3) -or (-not (Get-Command 'Ninja-Property-Get' -ErrorAction SilentlyContinue))

if ($useCliDirect) {
    # PS 2.0 or module not available - use CLI directly
    $currentValue = & $ninjaCli get s1server 2>&1
    if ($currentValue -ne $mgmtServer) {
        Write-Host "Updating s1server: '$currentValue' -> '$mgmtServer'"
        & $ninjaCli set s1server $mgmtServer
    } else {
        Write-Host "s1server already correct: $mgmtServer"
    }
} else {
    # PS 3.0+ - use PowerShell module with readiness check
$maxAttempts = 10
$attempt = 0
$moduleReady = $false

while ($attempt -lt $maxAttempts -and -not $moduleReady) {
    $attempt++
    try {
        $currentValue = Ninja-Property-Get s1server 2>&1
        Write-Output "Current Value: $currentValue"
        $moduleReady = $true
    } catch {
        Write-Output "Attempt $attempt - Ninja property module not ready, waiting 30 seconds..."
        Start-Sleep -Seconds 30
    }
}

if (-not $moduleReady) {
    Write-Output 'Ninja property module never became ready after $maxAttempts attempts'
    exit 1
}

Write-Output "Ninja property module is ready"

# Only write if blank or different
if ($currentValue -ne $mgmtServer) {
    Write-Output "Updating s1server: '$currentValue' -> '$mgmtServer'"
    Ninja-Property-Set s1server $mgmtServer
} else {
    Write-Output "s1server already correct: $mgmtServer"
}

Write-Output "Checking server URL for exit code"
switch ($mgmtServer.TrimEnd('/')) {
    'https://usea1-amrose.sentinelone.net'    { exit 0 }
    'https://usea1-ninjaone2.sentinelone.net' { exit 99 }
    default                                   { exit 1 }
}