# Check the number of logged-in users on Windows
$loggedInUsers = 0
$output = quser
if ($LASTEXITCODE -eq 0) {
    $loggedInUsers = ($output | Select-Object -Skip 1).Count
}
Ninja-Property-Set -Name loggedInUsers $loggedInUsers