param(
    [Parameter(Mandatory = $true)]
    [string]$Username,

    [Parameter(Mandatory = $true)]
    [string]$Password,

    [string]$Domain = $env:USERDOMAIN
)

Add-Type -AssemblyName System.DirectoryServices.AccountManagement

function Test-ADCredential {
    param(
        [string]$User,
        [string]$Pass,
        [string]$Domain
    )

    $context = New-Object System.DirectoryServices.AccountManagement.PrincipalContext(
        [System.DirectoryServices.AccountManagement.ContextType]::Domain,
        $Domain
    )

    return $context.ValidateCredentials($User, $Pass)
}

if (Test-ADCredential -User $Username -Pass $Password -Domain $Domain) {
    Write-Output "Valid credentials"
    exit 0
} else {
    Write-Error "Invalid credentials"
    exit 1
}