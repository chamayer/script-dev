$sentinelCtl = Get-ChildItem 'C:\Program Files\SentinelOne' -Recurse -Filter 'sentinelctl.exe' -ErrorAction SilentlyContinue | Select-Object -First 1

if (-not $sentinelCtl) {
    Write-Output 'sentinelctl.exe not found'
    exit 1
}

Write-Output "Found sentinelctl.exe at $($sentinelCtl.FullName)"

$maxRetries = 10
$retryDelay = 180  # seconds between retries for transient conditions

# Extract mgmtServer, retrying while sentinel agent still reports http://localhost
$mgmtServer = $null
for ($i = 1; $i -le $maxRetries; $i++) {
    $output = & $sentinelCtl.FullName configure 2>&1
    $match = $output | Select-String 'server\.mgmtServer\s+(\S+)'
    $candidate = if ($match) { $match.Matches[0].Groups[1].Value.Trim() } else { $null }

    if (-not $candidate) {
        Write-Output 'server.mgmtServer value not found in sentinelctl output'
        exit 1
    }

    if ($candidate.TrimEnd('/') -eq 'http://localhost') {
        Write-Output "mgmtServer is http://localhost (attempt $i/$maxRetries); waiting $retryDelay seconds..."
        Start-Sleep -Seconds $retryDelay
        continue
    }

    $mgmtServer = $candidate
    break
}

if (-not $mgmtServer) {
    Write-Output "mgmtServer never resolved past http://localhost after $maxRetries attempts"
    exit 1
}

Write-Output "Extracted mgmtServer: $mgmtServer"

$ninjaCli = 'C:\ProgramData\NinjaRMMAgent\ninjarmm-cli.exe'
$useCliDirect = ($PSVersionTable.PSVersion.Major -lt 3) -or (-not (Get-Command 'Ninja-Property-Get' -ErrorAction SilentlyContinue))

# Get current Ninja value, retrying if the custom field doesn't exist yet
$currentValue = $null
for ($i = 1; $i -le $maxRetries; $i++) {
    if ($useCliDirect) {
        $candidate = & $ninjaCli get s1server 2>&1
    } else {
        $moduleReady = $false
        for ($a = 1; $a -le 10; $a++) {
            try {
                $candidate = Ninja-Property-Get s1server 2>&1
                $moduleReady = $true
                break
            } catch {
                Write-Output "Attempt $a - Ninja property module not ready, waiting 30 seconds..."
                Start-Sleep -Seconds 30
            }
        }
        if (-not $moduleReady) {
            Write-Output 'Ninja property module never became ready'
            exit 1
        }
    }

    if ("$candidate" -match 'Unable to find the specified field') {
        Write-Output "Ninja field 's1server' not found (attempt $i/$maxRetries); waiting $retryDelay seconds..."
        Start-Sleep -Seconds $retryDelay
        continue
    }

    $currentValue = $candidate
    break
}

if ($null -eq $currentValue) {
    Write-Output "Ninja field 's1server' never appeared after $maxRetries attempts"
    exit 1
}

Write-Output "Current Value: $currentValue"

# Only write if blank or different
if ("$currentValue".TrimEnd('/') -eq 'https://usea1-amrose.sentinelone.net') {
    Write-Output "s1server is locked to amrose, skipping update (agent reports: $mgmtServer)"
} elseif ("$currentValue" -ne $mgmtServer) {
    Write-Output "Updating s1server: '$currentValue' -> '$mgmtServer'"
    if ($useCliDirect) {
        & $ninjaCli set s1server $mgmtServer
    } else {
        Ninja-Property-Set s1server $mgmtServer
    }
} else {
    Write-Output "s1server already correct: $mgmtServer"
}

Write-Output "Checking server URL for exit code"
if ($mgmtServer.TrimEnd('/') -eq 'https://usea1-amrose.sentinelone.net') {
    exit 0
} elseif ($mgmtServer.TrimEnd('/') -eq 'https://usea1-ninjaone2.sentinelone.net') {
    exit 99
} else {
    exit 1
}
