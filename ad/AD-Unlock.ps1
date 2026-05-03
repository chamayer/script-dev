$Username = Read-Host "Enter username"

Import-Module ActiveDirectory -ErrorAction Stop

$DCs = Get-ADDomainController -Filter * | Select-Object -ExpandProperty HostName

$lockedOnAny = $false
$results = @()

foreach ($DC in $DCs) {
    try {
        $user = Get-ADUser -Identity $Username -Server $DC -Properties LockedOut, LastLogonDate, BadLogonCount, BadPasswordTime -ErrorAction Stop
        $results += [PSCustomObject]@{
            DC           = $DC
            LockedOut    = $user.LockedOut
            BadLogons    = $user.BadLogonCount
            LastBadPWD   = if ($user.BadPasswordTime) { [DateTime]::FromFileTime($user.BadPasswordTime) } else { 'N/A' }
            LastLogon    = if ($user.LastLogonDate) { $user.LastLogonDate } else { 'Never' }
        }
        if ($user.LockedOut) { $lockedOnAny = $true }
    } catch {
        $results += [PSCustomObject]@{
            DC           = $DC
            LockedOut    = 'ERROR'
            BadLogons    = '-'
            LastBadPWD   = '-'
            LastLogon    = $_.Exception.Message
        }
    }
}

# Print user info from first successful query
$first = Get-ADUser -Identity $Username -Properties DisplayName, Enabled -ErrorAction SilentlyContinue
if ($first) {
    Write-Host "`nUser:         $($first.SamAccountName)"
    Write-Host "Display Name: $($first.Name)"
    Write-Host "Enabled:      $($first.Enabled)"
}

Write-Host "`nLockout status per DC:"
$results | Format-Table -AutoSize

if ($lockedOnAny) {
    $response = Read-Host "Account is LOCKED on one or more DCs. Unlock on all DCs now? (Y/N)"
    if ($response -match '^[Yy]') {
        foreach ($DC in $DCs) {
            try {
                Unlock-ADAccount -Identity $Username -Server $DC -ErrorAction Stop
                Write-Host "Unlocked on $DC" -ForegroundColor Green
            } catch {
                Write-Host "Failed to unlock on $DC`: $($_.Exception.Message)" -ForegroundColor Red
            }
        }
    } else {
        Write-Host "No changes made." -ForegroundColor Yellow
    }
} else {
    Write-Host "Account is not locked on any DC." -ForegroundColor Green
}