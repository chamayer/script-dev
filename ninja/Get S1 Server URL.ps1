$sentinelCtl = Get-ChildItem 'C:\Program Files\SentinelOne' -Recurse -Filter 'sentinelctl.exe' -ErrorAction SilentlyContinue | Select-Object -First 1

if (-not $sentinelCtl) {
    Write-Host 'sentinelctl.exe not found'
    exit 1
}

$output = & $sentinelCtl.FullName configure 2>&1
$mgmtServer = ($output | Select-String 'server\.mgmtServer\s+(\S+)').Matches.Groups[1].Value.Trim()

if (-not $mgmtServer) {
    Write-Host 'server.mgmtServer value not found in sentinelctl output'
    exit 1
}

# Wait for Ninja property module to be ready
$maxAttempts = 10
$attempt = 0
$moduleReady = $false

while ($attempt -lt $maxAttempts -and -not $moduleReady) {
    $attempt++
    try {
        $currentValue = Ninja-Property-Get s1server 2>&1
        $moduleReady = $true
    } catch {
        Write-Host "Attempt $attempt - Ninja property module not ready, waiting 30 seconds..."
        Start-Sleep -Seconds 30
    }
}

if (-not $moduleReady) {
    Write-Host 'Ninja property module never became ready after $maxAttempts attempts'
    exit 1
}

# Only write if blank or different
if ($currentValue -ne $mgmtServer) {
    Write-Host "Updating s1server: '$currentValue' -> '$mgmtServer'"
    Ninja-Property-Set s1server $mgmtServer
} else {
    Write-Host "s1server already correct: $mgmtServer"
}

switch ($mgmtServer.TrimEnd('/')) {
    'https://usea1-amrose.sentinelone.net'    { exit 0 }
    'https://usea1-ninjaone2.sentinelone.net' { exit 99 }
    default                                   { exit 1 }
}