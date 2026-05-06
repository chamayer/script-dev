#Check if script is being executed as admin, if not relaunch as admin
$currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
$isAdmin = $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $isAdmin) {
    Write-Host "Not running as Administrator. Restarting with elevation..."

    # Relaunch the script as administrator
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = 'powershell.exe'
    $psi.Arguments = "-ExecutionPolicy Bypass -File `"$PSCommandPath`""
    $psi.Verb = 'runas'

    try {
        [System.Diagnostics.Process]::Start($psi) | Out-Null
    }
    catch {
        Write-Error "User canceled UAC prompt or elevation failed."

    }

    Read-Host "Press Enter to exit"
    exit
}

#Check if AD/365 modules are initialized and installed, does not progress if they aren't/can't be
Write-Host "Both Active Directory and 365 modules must be installed for this script to work.  Checking if modules are correctly installed."

if (Get-Module -ListAvailable -Name ExchangeOnlineManagement) {
    Write-Host "365 Module exists"
}
else {
    Write-Host "365 Module does not exist, installing"

    try {
        Install-Module ExchangeOnlineManagement
        Import-Module ExchangeOnlineManagement

    }
    catch {
        Write-Host -f red "Encountered Error:"$($_.Exception.Message)        
        Write-Warning "IMPORTING 365 MODULE FAILED, EXITING"
        throw
        return
    }
    
}

if (Get-Module -ListAvailable -Name ActiveDirectory) {
    Write-Host "Active Directory Module exists"
}
else {
    Write-Host "Active Directory Module does not exist, installing"
    try {

        Install-Module ExchangeOnlineManagement
        Install-WindowsFeature -Name RSAT-AD-PowerShell -IncludeAllSubFeature
        Import-Module -Name ActiveDirectory

    }
    catch {
        Write-Host -f red "Encountered Error:"$($_.Exception.Message)        
        Write-Warning "IMPORTING ACTIVE DIRECTORY MODULE FAILED, EXITING"
        throw
        return
    }
    
}

if (Get-Module -ListAvailable -Name Microsoft.Graph.Identity.DirectoryManagement) {
    Write-Host "Microsoft.Graph.Identity.DirectoryManagement Module exists"
}
else {
    Write-Host "Microsoft.Graph.Identity.DirectoryManagement Module does not exist, Installing"

    try {
        Install-Module Microsoft.Graph.Identity.DirectoryManagement
        Import-Module Microsoft.Graph.Identity.DirectoryManagement
    }
    catch {
        Write-Host -f red "Encountered Error:"$($_.Exception.Message)       
        Write-Warning "IMPORTING Microsoft.Graph.Identity.DirectoryManagement MODULE FAILED, EXITING"
        throw
        return
    }
    
}

if (Get-Module -ListAvailable Az.KeyVault) {
    Write-Host "Az.KeyVault Module exists"
}
else {
    Write-Host "Az.KeyVault Module does not exist, Installing"

    try {
        Install-Module -Name Az.KeyVault
        Import-Module -Name Az.KeyVault
    }
    catch {
        Write-Host -f red "Encountered Error:"$($_.Exception.Message)        
        Write-Warning "IMPORTING Az.KeyVault MODULE FAILED, EXITING"
        throw
        return
    }
}

# This function replaces Add-Content. When called it gets the current $time and appends the log file using .NET StreamWriter
function Write-Log {
    param (
        [string]$Message
    )
    $time = (Get-Date).ToString("MM/dd/yyyy hh:mm:ss tt")
    $sw = [System.IO.StreamWriter]::new($logpath, $true)
    try {
        $sw.WriteLine("$time :: $Message")
    }
    finally {
        $sw.Close()
    }
}
function Get-ADUserBySamOrUpn {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Identity,

        [Parameter()]
        [string[]]$Properties = @('SamAccountName','UserPrincipalName')
    )

    $id = $Identity.Trim()
    $defaultUpnSuffix = "alldatahealth.com"
    $upnCandidate = if ($id -like '*@*') { $id } else { "$id@$defaultUpnSuffix" }

    Get-ADUser -Filter {
        SamAccountName -eq $id -or
        UserPrincipalName -eq $upnCandidate
    } -Properties $Properties |
    Select-Object -First 1
}


function Get-Time {
    (Get-Date).ToString("MM/dd/yyyy hh:mm:ss tt")
}

#Log the user that the script is executing as
$ExecutingUser = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
$ExecutingComputer = $env:ComputerName
$logpath = "\\adh.local\it$\Reports\UserManagement\User-Management-log.txt" 
Write-Log "ADH-User-Management-Script Executing as $ExecutingUser on $ExecutingComputer"

#clears screen and initializes variables for global use
Clear-Host
$CSV = ""
$CSVPath = ""
$logpath = "\\adh.local\it$\Reports\UserManagement\User-Management-log.txt"


#Main Menu operations, gives user choice to branch out into various other functions. User types the number of the menu option and hits enter to choose. This theme continues through all menus. `n means linebreak.
function Show-MainMenu {
    do {
        # Clear these variables to avoid bleed-over
        $CSV = ""
        $CSVPath = ""

        Write-Host "------`nMAIN MENU`n------" -ForegroundColor Cyan
        Write-Host "1. Create User`n2. Delegate Access`n3. Group Management`n4. Offboard/Reactivate User`n5. Rename User`n6. Check/Add/Remove Email Alias`n7. Enable/Disable Email Forwarding`n8. Enable/Disable Out of Office`n9. Duo User Management`n10. Reset User Password`n11. Unlock AD User`n12. Get Office 365 License Count`n13. Update Phone`n14. Exit Script`n" -ForegroundColor Yellow
        $menuresponse = Read-Host "Enter Selection"

        switch ($menuresponse) {
            "1" { Invoke-UserCreationAction }
            "2" { Invoke-DelegateAccessAction }
            "3" { Invoke-GroupMembershipAction }
            "4" { Invoke-OffboardReactivateAction }
            "5" { Update-UserName }
            "6" { Invoke-AliasManagementAction }
            "7" { Invoke-EmailForwardingAction }
            "8" { Invoke-OutOfOfficeAction }
            "9" { Invoke-DuoGroupAction }
            "10" { Invoke-SetUserPassword }
            "11" { Invoke-UnlockUserAccount }
            "12" { Invoke-GetLicenseCount }
            "13" { Update-Phone }
            "14" { exit }
            default {
                Write-Host "Invalid selection. Please choose a valid option (1-14)." -ForegroundColor Red
            }
        }
    } until (1..13 -contains [int]$menuresponse)
}



#Menu to choose what kind of user is created standard in-house user or offshore (Ruby) user
function Invoke-UserCreationAction {
    do {
        Write-Host "------`nCREATE USER MENU`n------" -ForegroundColor Cyan
        Write-Host "Is this an In-House user, Ruby user, Or Contact?`n"  -ForegroundColor Cyan
        Write-Host "1. Standard User`n2. Ruby User`n3. Contact`n4. Main Menu`n"  -ForegroundColor Yellow
        
        $menuresponse = Read-Host [Enter Selection]
        switch ($menuresponse) {
            "1" { Confirm-NewStandardUser }
            "2" { Confirm-NewRubyUser }
            "3" { Confirm-NewContact}
            "4" { Show-MainMenu }
        }
    }
    until (1..4 -contains $menuresponse) 
}

#Many menus are split into 2 sections. Section 1 is typically CSV reading and confirming the data being read is correct. Section 2 will attempt to write the data. 
function Confirm-NewStandardUser {
    do {
        $CSV = ""
        $CSVPath = ""
        Write-Host "------`nCREATE STANDARD USER MENU`n------" -ForegroundColor Cyan
        Write-Host "Please create a CSV file with the following columns: `n"  -ForegroundColor Cyan
        Write-Host "FirstName,LastName,Username,Password,otherMailbox,Mobile,Phone,GroupMembership`n"  -ForegroundColor Green
        Write-Host "Note that 365 License & Sync groups will automatically be applied, and the GroupMembership field needs to have a semicolon between groups WITHOUT quotes and contain the name of the group, as such:`n"  -ForegroundColor Cyan
        Write-Host "office;CLOSE_filter;All;alldata;Full Timers;USB Block;Peri Printer;Printer_172_Fl_2;GI Billing;Internal;ADHFilterLevelB`n"  -ForegroundColor Green
        Write-Host "Specify the path to the CSV:`n"  -ForegroundColor Yellow
        
        $CSVPath = Read-Host [Enter CSV Path]
        $CSVPath = $CSVPath.Replace("`"", "")

        try {
        
            if (!(Test-Path $CSVPath)) 
            { throw }
        
        }
        
        catch {
            Write-Host -f red "Encountered Error:"$($_.Exception.Message)            
            Write-Warning "CSV FILE DOES NOT EXIST, RETURNING TO MAIN MENU"
            Show-MainMenu
        }
        
        $CSV = Import-Csv -Path $CSVPath
        
        
        Write-Host "Please verify the data below is correct`n"  -ForegroundColor Yellow
        
        #Iterates through each entry in the CSV and displays it on screen for user review
        foreach ($user in $CSV) {
            $UFirstName = $user.FirstName
            $ULastName = $user.LastName
            $UDisplayName = $user.FirstName + " " + $user.LastName
            $UUsername = $user.Username
            $UPassword = $user.Password
            $UotherMailbox = $user.otherMailbox
            $UMobile = $user.Mobile
            $UPhone = $user.Phone
            $UGroupMembership = $user.GroupMembership
            
            $UGroupMembershipFormatted = $UGroupMembership -replace ";", ", "

            Write-Host "First Name: $UFirstName`nLast Name: $ULastName`nFull Name: $UDisplayName`nUsername: $UUsername`nPassword: $UPassword`notherMailbox: $UotherMailbox`nMobile: $UMobile`nPhone: $UPhone`nGroup Membership: $UGroupMembershipFormatted"  -ForegroundColor Green
            Write-Host "------" -ForegroundColor Cyan
        }

        Write-Host "Is all the information above correct? (Scroll up)`n"  -ForegroundColor Cyan
        Write-Host "1. Yes (User will be created)`n2. No (Will go to beginning of menu)`n3. Main Menu`n"  -ForegroundColor Yellow
        $menuresponse = Read-Host [Enter Selection]
        switch ($menuresponse) {
            "1" { Add-NewStandardUser }
            "2" { Confirm-NewStandardUser }
            "3" { Show-MainMenu }
        }
    }
    until (1..3 -contains $menuresponse) 
}

# Pushes data received and reviewed from section 1 above
function Add-NewStandardUser {
    foreach ($user in $CSV) {
        
            

        # Read user data from each field in each row and assign the data to a variable as below
        $username = $user.Username.Replace(" ", "")
        $password = $user.Password
        $firstname = $user.FirstName
        $lastname = $user.LastName
        $telephone = $user.Phone
        $mobile = $user.Mobile
        $otherMailbox = $user.otherMailbox
        $email = $user.Username.Replace(" ", "") + "@alldatahealth.com"
        $primarySMTPProxy = "SMTP:" + $user.Username.Replace(" ", "") + "@alldatahealth.com"
        $OU = "OU=Standard Users,OU=T2 - Users,OU=Tier 2,OU=AllData,DC=ADH,DC=LOCAL"

        # Check to see if the user already exists in AD
        if (Get-ADUser -F { SamAccountName -eq $username }) {
            
            # If user does exist, give a warning
            Write-Warning "A user account with username $username already exists in Active Directory. Returning to Main Menu"
            Show-MainMenu
        }
        else {
            
            # User does not exist then proceed to create the new user account
            # Account will be created in the OU provided by the $OU variable read from the CSV file
            # All sets should be enclosed within try segments, with critical updates failing back to main menu
            try {

                if ($UotherMailbox -like "*@*") {
            

                    Write-Host "Creating user $username..." -ForegroundColor DarkYellow
                    Write-Log "New-ADUser -SamAccountName $username -UserPrincipalName $username@alldatahealth.com -Name $firstname $lastname -GivenName $firstname -Surname $lastname -Enabled $True -DisplayName $firstname $lastname -Path $OU -CannotChangePassword $True -PasswordNeverExpires $True -ScriptPath 'user.bat' -OtherAttributes @{'otherMailbox' = $otherMailbox } -AccountPassword **OBSCURED** -ChangePasswordAtLogon $False -OfficePhone $telephone -MobilePhone $mobile -EmailAddress $email"

                    New-ADUser `
                        -SamAccountName $username `
                        -UserPrincipalName "$username@alldatahealth.com" `
                        -Name "$firstname $lastname" `
                        -GivenName $firstname `
                        -Surname $lastname `
                        -Enabled $True `
                        -DisplayName "$firstname $lastname" `
                        -Path $OU `
                        -CannotChangePassword $True `
                        -PasswordNeverExpires $True `
                        -ScriptPath 'user.bat' `
                        -OtherAttributes @{'otherMailbox' = "$otherMailbox" } `
                        -AccountPassword (ConvertTo-SecureString $password -AsPlainText -Force) -ChangePasswordAtLogon $False `
                        -OfficePhone $telephone `
                        -MobilePhone $mobile `
                        -EmailAddress $email

                }
                else {
                    Write-Host "Creating user $username..." -ForegroundColor DarkYellow
                    Write-Log "New-ADUser -SamAccountName $username -UserPrincipalName $username@alldatahealth.com -Name $firstname $lastname -GivenName $firstname -Surname $lastname -Enabled $True -DisplayName $firstname $lastname -Path $OU -CannotChangePassword $True -PasswordNeverExpires $True -ScriptPath 'user.bat' -AccountPassword **OBSCURED** -ChangePasswordAtLogon $False -OfficePhone $telephone -MobilePhone $mobile -EmailAddress $email"
    
                    New-ADUser `
                        -SamAccountName $username `
                        -UserPrincipalName "$username@alldatahealth.com" `
                        -Name "$firstname $lastname" `
                        -GivenName $firstname `
                        -Surname $lastname `
                        -Enabled $True `
                        -DisplayName "$firstname $lastname" `
                        -Path $OU `
                        -CannotChangePassword $True `
                        -PasswordNeverExpires $True `
                        -ScriptPath 'user.bat' `
                        -AccountPassword (ConvertTo-SecureString $password -AsPlainText -Force) -ChangePasswordAtLogon $False `
                        -OfficePhone $telephone `
                        -MobilePhone $mobile `
                        -EmailAddress $email
                }

                Write-Host "Adding ProxyAddresses for $username..." -ForegroundColor DarkYellow
                #Sets Proxy Addresses
                
                $validateProxy = Get-Aduser -filter * -Properties ProxyAddresses | Where-Object { $_.ProxyAddresses -eq "SMTP:$primarySMTPProxy" } | Select-Object Name

                $smtpProxyUser = $validateProxy.Name
                if ($smtpProxyUser) {
                    Write-Host "User $smtpProxyUser has $primarySMTPProxy configured as an alias, which conflicts with the email address of user $username. Please reach out to A.M. Rose for assistance."
                }
                else {

                }
                Write-Log "Set-ADUser $username -add @{proxyaddresses = $primarySMTPProxy }"
                Set-ADUser $username -add @{proxyaddresses = $primarySMTPProxy }
            
                # If user is created, show message
                Write-Host "The user account $username is created." -ForegroundColor Cyan
                Write-Log "$User | Add-Member -MemberType NoteProperty -Name `"Initial Password`" -Value **OBSCURED** -Force"
                $User | Add-Member -MemberType NoteProperty -Name "Initial Password" -Value $password -Force
            }
            catch {
                Write-Host -f red "Encountered Error:"$($_.Exception.Message)                #Fails to main menu if not successful
                Write-Log "Encountered Error:$_.Exception.Message"
                Write-Warning "Failed to create user, RETURNING TO MAIN MENU"
                Show-MainMenu
            }

        }

        # Attempts to add users to 365 license, sync and T2 - Users Groups
        try {
            Write-Host "Adding $username to group ADEntraSyncGroup..." -ForegroundColor DarkYellow
            Write-Log "Add-ADGroupMember -Identity `"ADEntraSyncGroup`" -Members $username"
            Add-ADGroupMember -Identity "ADEntraSyncGroup" -Members $username

            Write-Host "Adding $username to group ADEntra-Assign365License..." -ForegroundColor DarkYellow
            Write-Log "Add-ADGroupMember -Identity `"ADEntra-Assign365License`" -Members $username"
            Add-ADGroupMember -Identity "ADEntra-Assign365License" -Members $username

            Write-Host "Adding $username to group T2-Users..." -ForegroundColor DarkYellow
            Write-Log "Add-ADGroupMember -Identity `"T2 - Users`" -Members $username"
            Add-ADGroupMember -Identity "T2 - Users" -Members $username

        }
        catch {
            Write-Host -f red "Encountered Error:"$($_.Exception.Message)            
            Write-Log "Encountered Error:$_.Exception.Message"
            Write-Warning "FAILED TO ASSIGN DEFAULT GROUPS, CONTINUING"
        }


        # Attempts to apply all group membership from the CSV
        try {
            $UGroupMembership = $user.GroupMembership
            $UGroupMembershiparray = $UGroupMembership.Split(";")

            
            foreach ($group in $UGroupMembershiparray) {
                Write-Host "Adding $username to $group..." -ForegroundColor DarkYellow
                 
                Write-Log "get-adgroup -filter `"name -eq `"$group`"`" | Add-ADGroupMember -Members $username"
                get-adgroup -filter "name -eq `"$group`"" | Add-ADGroupMember -Members $username
            }  

        }
        catch {
            Write-Host -f red "Encountered Error:"$($_.Exception.Message)            
            Write-Log "Encountered Error:$_.Exception.Message"
            # Only displays warning and does not fail to main menu if there are group issues as the user was already created at this point
            Write-Warning "GROUP MEMBERSHIP FAILED, CONTINUING"
        }

    }
    $CSV = ""
    $CSVPath = ""


    # Next few lines check for available licensing in 365
    Connect-MgGraph -Scopes LicenseAssignment.Read.All -NoWelcome
    $lic = Get-MgSubscribedSku | Where-Object { $_.SkuPartNumber -like 'EXCHANGESTANDARD' }
    $activeunits = $lic.PrepaidUnits.Enabled
    $consumedunits = $lic.ConsumedUnits
    $remainingunits = $activeunits - $consumedunits

    Write-Host "Please ensure there are enough remaining licenses for 365.`n" -ForegroundColor Cyan
    Write-Host "Remaining 365 Plan 1 licenses: $remainingunits`n" -ForegroundColor Green


    Write-Log "Remaining 365 Plan 1 licenses: $remainingunits"

        
    Write-Host "Users created successfully, returning to Main Menu`n"  -ForegroundColor Cyan

    Show-MainMenu

}

# Gets user info for creating Ruby/Offshore users via CSV
function Confirm-NewRubyUser {
    do {
        $CSV = ""
        $CSVPath = ""
        Write-Host "------`nCREATE Ruby USER MENU`n------" -ForegroundColor Cyan
        Write-Host "Please create a CSV file with the following columns: `n"  -ForegroundColor Cyan
        Write-Host "FirstName, LastName, Username, Password, otherMailbox, Mobile, Phone, Country, DuoNeeded`n"  -ForegroundColor Green
        Write-Host "Please put `"Yes`" or `"No`" for DuoNeeded, or No will be assumed. `n"  -ForegroundColor Cyan
        Write-Host "Specify the path to the CSV:`n"  -ForegroundColor Yellow
        
        $CSVPath = Read-Host [Enter CSV Path]
        $CSVPath = $CSVPath.Replace("`"", "")

        try {
        
            if (!(Test-Path $CSVPath)) 
            { throw }
        
        }
        
        catch {
            Write-Host -f red "Encountered Error:"$($_.Exception.Message)            

            Write-Log "Encountered Error:$_.Exception.Message"
            Write-Warning "CSV FILE DOES NOT EXIST, RETURNING TO MAIN MENU"
            Show-MainMenu
        }
        
        $CSV = Import-Csv -Path $CSVPath

        Write-Host "Please verify the data below is correct`n"  -ForegroundColor Yellow
        

        Write-Host "FirstName, LastName, Username, Password, otherMailbox, Mobile, Phone, Country, DuoNeeded`n"  -ForegroundColor Green
        foreach ($user in $CSV) {
            $UFirstName = $user.FirstName
            $ULastName = $user.LastName
            $UDisplayName = $user.FirstName + " " + $user.LastName
            $UUsername = $user.Username
            $UPassword = $user.Password
            $UotherMailbox = $user.otherMailbox
            $UMobile = $user.Mobile
            $UPhone = $user.Phone
            $UCountry = $user.Country
            $UDuo = $user.DuoNeeded
            
            Write-Host "First Name: $UFirstName`nLast Name: $ULastName`nFull Name: $UDisplayName`nUsername: $UUsername`nPassword: $UPassword`notherMailbox: $UotherMailbox`nMobile: $UMobile`nPhone: $UPhone`nCountry: $UCountry`nDuo Needed: $UDuo"  -ForegroundColor Green
            Write-Host "------" -ForegroundColor Cyan
        }

        Write-Host "Is all the information above correct? (Scroll up)`n"  -ForegroundColor Cyan
        Write-Host "1. Yes (User will be created)`n2. No (Will go to beginning of menu)`n3. Main Menu`n"  -ForegroundColor Yellow
        $menuresponse = Read-Host [Enter Selection]
        switch ($menuresponse) {
            "1" { Add-NewRubyUser }
            "2" { Confirm-NewRubyUser }
            "3" { Show-MainMenu }
        }
    }
    until (1..3 -contains $menuresponse) 
}

function Add-NewRubyUser {
    # Import active directory module for running AD cmdlets
    Import-Module ActiveDirectory

    $LogDate = Get-Date -f dd-MM-yyyy_HHmmffff


    # Location of CSV fle that will be exported to including random passwords
    $ExportPath = "C:\Temp\Passwords_$logDate.csv"

    $Exportdirectory = [System.IO.Path]::GetDirectoryName($Exportpath)
    # Validate that $Exportdirectory exists, if not create
    if (!(Test-Path $Exportdirectory )) 
    { New-Item -Path $Exportdirectory -ItemType Directory }

    # Loop through each row containing user details in the CSV file 
    foreach ($User in $CSV) {

        # Read user data from each field in each row and assign the data to a variable as below
        $username = $User.Username.trim()
        $password = $User.Password
        $firstname = $User.FirstName
        $lastname = $User.LastName
        $telephone = $User.Phone
        $mobile = $User.Mobile
        $otherMailbox = $User.otherMailbox
        $country = $User.Country
        $email = $User.Username.trim() + "@alldatahealth.com"
        $primarySMTPProxy = "SMTP:" + $User.Username.trim() + "@alldatahealth.com"
        $UDuo = $user.DuoNeeded

        #Sets OU based on Country from CSV
        if ($country -eq "CO") {
            $OU = "OU=Bronx Office, OU=CallDept, OU=Remote_Users,OU=T2 - Users,OU=Tier 2, OU=AllData, DC=ADH, DC=LOCAL"
        }
        elseif ($country -eq "DO") {
            $OU = "OU=Staten Island Office,OU=CallDept,OU=Remote_Users,OU=T2 - Users,OU=Tier 2,OU=AllData,DC=ADH,DC=LOCAL"
        }
        elseif ($country -eq "PH") {
            $OU = "OU=Queens Office,OU=CallDept,OU=Remote_Users,OU=T2 - Users,OU=Tier 2,OU=AllData,DC=ADH,DC=LOCAL"
        }
        elseif ($country -eq "IN") {
            $OU = "OU=BackMD,OU=Remote_Users,OU=T2 - Users,OU=Tier 2,OU=AllData,DC=ADH,DC=LOCAL"
        }
        # Check to see if the user already exists in AD
        if (Get-ADUser -F { SamAccountName -eq $username }) {

            # If user does exist, give a warning
            Write-Warning "A user account with username $username already exists in Active Directory. Returning to Main Menu."
            Show-MainMenu
        }
        else {

            if ($UotherMailbox -like "*@*") {

                Write-Host "Creating $username..." -ForegroundColor DarkYellow

                Write-Log "New-ADUser -SamAccountName $username -UserPrincipalName `"$username@alldatahealth.com`" -Name `"$firstname $lastname`" -GivenName $firstname -Surname $lastname -Enabled $True -DisplayName `"$firstname $lastname`" -Path $OU -CannotChangePassword $True -PasswordNeverExpires $True -ScriptPath 'Call Dept.bat' -OtherAttributes @{'otherMailbox' = `"$otherMailbox`" } -AccountPassword **OBSCURED** -ChangePasswordAtLogon $False -OfficePhone $telephone -MobilePhone $mobile -country $country -EmailAddress $email"
                try {
                    # User does not exist then proceed to create the new user account
                    # Account will be created in the OU provided by the $OU variable read from the CSV file
                    New-ADUser `
                        -SamAccountName $username `
                        -UserPrincipalName "$username@alldatahealth.com" `
                        -Name "$firstname $lastname" `
                        -GivenName $firstname `
                        -Surname $lastname `
                        -Enabled $True `
                        -DisplayName "$firstname $lastname" `
                        -Path $OU `
                        -CannotChangePassword $True `
                        -PasswordNeverExpires $True `
                        -ScriptPath 'Call Dept.bat' `
                        -OtherAttributes @{'otherMailbox' = "$otherMailbox" } `
                        -AccountPassword (ConvertTo-SecureString $password -AsPlainText -Force) -ChangePasswordAtLogon $False `
                        -OfficePhone $telephone `
                        -MobilePhone $mobile `
                        -country $country `
                        -EmailAddress $email
                }
                catch {
                    Write-Host -f red "Encountered Error:"$($_.Exception.Message)                    
                    Write-Log "Encountered Error:$_.Exception.Message"
                    Write-Warning "CREATE USER FAILED, RETURNING TO MAIN MENU"
                    Show-MainMenu

                }
            } 
            else {
                Write-Host "Creating $username..." -ForegroundColor DarkYellow
                Write-Log "New-ADUser -SamAccountName $username -UserPrincipalName `"$username@alldatahealth.com`" -Name `"$firstname $lastname`" -GivenName $firstname -Surname $lastname -Enabled $True -DisplayName `"$firstname $lastname`" -Path $OU -CannotChangePassword $True -PasswordNeverExpires $True -ScriptPath 'Call Dept.bat' -AccountPassword **OBSCURED** -ChangePasswordAtLogon $False -OfficePhone $telephone -MobilePhone $mobile -country $country -EmailAddress $email"
                try {
                    # User does not exist then proceed to create the new user account
                    # Account will be created in the OU provided by the $OU variable read from the CSV file
                    New-ADUser `
                        -SamAccountName $username `
                        -UserPrincipalName "$username@alldatahealth.com" `
                        -Name "$firstname $lastname" `
                        -GivenName $firstname `
                        -Surname $lastname `
                        -Enabled $True `
                        -DisplayName "$firstname $lastname" `
                        -Path $OU `
                        -CannotChangePassword $True `
                        -PasswordNeverExpires $True `
                        -ScriptPath 'Call Dept.bat' `
                        -AccountPassword (ConvertTo-SecureString $password -AsPlainText -Force) -ChangePasswordAtLogon $False `
                        -OfficePhone $telephone `
                        -MobilePhone $mobile `
                        -country $country `
                        -EmailAddress $email
                }
                catch {
                    Write-Host -f red "Encountered Error:"$($_.Exception.Message)                    
                    Write-Log "Encountered Error:$_.Exception.Message"
                    Write-Warning "CREATE USER FAILED, RETURNING TO MAIN MENU"
                    Show-MainMenu

                }
            }


            #Sets Proxy Addresses
            Write-Host "Adding proxyaddresses for $username..." -ForegroundColor DarkYellow

            $validateProxy = Get-Aduser -filter * -Properties ProxyAddresses | Where-Object { $_.ProxyAddresses -eq "SMTP:$primarySMTPProxy" } | Select-Object Name

            $smtpProxyUser = $validateProxy.Name
            if ($smtpProxyUser) {
                Write-Host "User $smtpProxyUser has $primarySMTPProxy configured as an alias, which conflicts with the email address of user $username. Please reach out to A.M. Rose for assistance."
            }
            else {
                
            }
            Write-Log "Set-ADUser $username -add @{proxyaddresses = $primarySMTPProxy }  "
            Set-ADUser $username -add @{proxyaddresses = $primarySMTPProxy }  

            # If user is created, show message
            Write-Host "The user account $username is created." -ForegroundColor Cyan
            Write-Log "$User | Add-Member -MemberType NoteProperty -Name `"Initial Password`" -Value **OBSCURED** -Force"
            $User | Add-Member -MemberType NoteProperty -Name "Initial Password" -Value $password -Force
        }

        # Attempts to add users to 365 license, sync and T2 - Users Groups
        try {
            Write-Host "Adding $username to group ADEntraSyncGroup..." -ForegroundColor DarkYellow
            Write-Log "Add-ADGroupMember -Identity `"ADEntraSyncGroup`" -Members $username"
            Add-ADGroupMember -Identity "ADEntraSyncGroup" -Members $username

            Write-Host "Adding $username to group ADEntra-Assign365License..." -ForegroundColor DarkYellow
            Write-Log "Add-ADGroupMember -Identity `"ADEntra-Assign365License`" -Members $username"
            Add-ADGroupMember -Identity "ADEntra-Assign365License" -Members $username

            Write-Host "Adding $username to group T2-Users..." -ForegroundColor DarkYellow
            Write-Log "Add-ADGroupMember -Identity `"T2 - Users`" -Members $username"
            Add-ADGroupMember -Identity "T2 - Users" -Members $username

        }
        catch {
            Write-Host -f red "Encountered Error:"$($_.Exception.Message)            
            Write-Log "Encountered Error:$_.Exception.Message"
            Write-Warning "FAILED TO ASSIGN DEFAULT GROUPS, CONTINUING"
        }



        if ($UDuo -eq "Yes") {
            try {
                Write-Host "Adding $username to group Duo Sync..." -ForegroundColor DarkYellow
                Write-Log "Add-ADGroupMember -Identity 'DUO Sync' -Members $username"
                Add-ADGroupMember -Identity 'DUO Sync' -Members $username
            }
            catch {
                Write-Host -f red "Encountered Error:"$($_.Exception.Message)                
                Write-Log "Encountered Error:$_.Exception.Message"
                Write-Warning "FAILED TO APPLY DUO MEMBERSHIP, CONTINUING"
            }
        }
        else {
            Write-Warning "Duo membership not added, continuing"
        }

        
        #All remote users have set groups depending on their location
        try {

           
            Write-Host "Adding $username to group T2 - RDP Users..." -ForegroundColor DarkYellow
            Write-Log "Add-ADGroupMember -Identity 'T2 - RDP Users' -Members $username"
            Add-ADGroupMember -Identity 'T2 - RDP Users' -Members $username

            Write-Host "Adding $username to group RemoteRestricted..." -ForegroundColor DarkYellow
            Write-Log "Add-ADGroupMember -Identity RemoteRestricted -Members $username"
            Add-ADGroupMember -Identity RemoteRestricted -Members $username
            
            if ($country -eq "CO") {
                Write-Host "Adding $username to group Bronx_Office..." -ForegroundColor DarkYellow
                Write-Log "Add-ADGroupMember -Identity Bronx_Office -Members $username"
                Add-ADGroupMember -Identity Bronx_Office -Members $username

                Write-Host "Adding $username to group Call Department - EmailMonitored..." -ForegroundColor DarkYellow
                Write-Log "Add-ADGroupMember -Identity 'Call Department - EmailMonitored' -Members $username"
                Add-ADGroupMember -Identity 'Call Department - EmailMonitored' -Members $username
            }
            elseif ($country -eq "DO") {

                Write-Host "Adding $username to group Staten_Island_Call_Department..." -ForegroundColor DarkYellow
                Write-Log "Add-ADGroupMember -Identity Staten_Island_Call_Department -Members $username"
                Add-ADGroupMember -Identity Staten_Island_Call_Department -Members $username
            }
            elseif ($country -eq "PH") {
                Write-Host "Adding $username to group Queens-Office_Call_Department..." -ForegroundColor DarkYellow
                Write-Log "Add-ADGroupMember -Identity Queens-Office_Call_Department -Members $username"
                Add-ADGroupMember -Identity Queens-Office_Call_Department -Members $username
            }
            elseif ($country -eq "IN") {
                Write-Host "Adding $username to BackMD_Office..." -ForegroundColor DarkYellow
                Write-Log "Add-ADGroupMember -Identity BackMD_Office -Members $username"
                Add-ADGroupMember -Identity BackMD_Office -Members $username
            }

        }
        catch {
            Write-Host -f red "Encountered Error:"$($_.Exception.Message)            
            Write-Log "Encountered Error:$_.Exception.Message"
            Write-Warning "GROUP MEMBERSHIP FAILED, CONTINUING`n"
        }


        $CSV | Export-Csv -Encoding UTF8 $ExportPath -NoTypeInformation
    }

    $CSV = ""
    $CSVPath = ""

    # Next few lines check for available licensing in 365
    Connect-MgGraph -Scopes LicenseAssignment.Read.All -NoWelcome
    $lic = Get-MgSubscribedSku | Where-Object { $_.SkuPartNumber -like 'EXCHANGESTANDARD' }
    $activeunits = $lic.PrepaidUnits.Enabled
    $consumedunits = $lic.ConsumedUnits
    $remainingunits = $activeunits - $consumedunits

    Write-Host "Please ensure there are enough remaining licenses for 365.`n" -ForegroundColor Cyan
    Write-Host "Remaining 365 Plan 1 licenses: $remainingunits`n" -ForegroundColor Green



    Write-Host "Users created successfully, returning to Main Menu`n"  -ForegroundColor Cyan

    Show-MainMenu
    
}

function Confirm-NewContact {
    do {
        $CSV = ""
        $CSVPath = ""
        Write-Host "------`nCREATE CONTACT MENU`n------" -ForegroundColor Cyan
        Write-Host "Please create a CSV file with the following columns: `n"  -ForegroundColor Cyan
        Write-Host "FirstName, LastName, Email`n"  -ForegroundColor Green
        Write-Host "Specify the path to the CSV:`n"  -ForegroundColor Yellow
        Write-Host "Contacts will be added to the Email Filtering CallDept Bypass group. See ticket #113153 for more details" -ForegroundColor DarkRed
        
        $CSVPath = Read-Host [Enter CSV Path]
        $CSVPath = $CSVPath.Replace("`"", "")

        try {
        
            if (!(Test-Path $CSVPath)) 
            { throw }
        
        }
        
        catch {
            Write-Host -f red "Encountered Error:"$($_.Exception.Message)            

            Write-Log "Encountered Error:$_.Exception.Message"
            Write-Warning "CSV FILE DOES NOT EXIST, RETURNING TO MAIN MENU"
            Show-MainMenu
        }
        
        $CSV = Import-Csv -Path $CSVPath

        Write-Host "Please verify the data below is correct`n"  -ForegroundColor Yellow
        

        Write-Host "FirstName, LastName, Email`n"  -ForegroundColor Green
        foreach ($user in $CSV) {
            $UFirstName = $user.FirstName
            $ULastName = $user.LastName
            $UDisplayName = $user.FirstName + " " + $user.LastName
            $UUsername = $user.Email
            
            Write-Host "First Name: $UFirstName`nLast Name: $ULastName`nFull Name: $UDisplayName`nEmail: $UUsername`n"  -ForegroundColor Green
            Write-Host "------" -ForegroundColor Cyan
        }

        Write-Host "Is all the information above correct? (Scroll up)`n"  -ForegroundColor Cyan
        Write-Host "1. Yes (Contact will be created)`n2. No (Will go to beginning of menu)`n3. Main Menu`n"  -ForegroundColor Yellow
        $menuresponse = Read-Host [Enter Selection]
        switch ($menuresponse) {
            "1" { Add-Contact }
            "2" { Confirm-NewContact }
            "3" { Show-MainMenu }
        }
    }
    until (1..3 -contains $menuresponse) 


}

function Add-Contact {
    $LogDate = Get-Date -f dd-MM-yyyy_HHmmffff

    # Loop through each row containing user details in the CSV file 
    foreach ($User in $CSV) {

        # Read user data from each field in each row and assign the data to a variable as below
        $username = $User.Email.trim()
        $firstname = $User.FirstName
        $lastname = $User.LastName
        $displayName = $user.FirstName + " " + $user.LastName

        #Sets OU based on Country from CSV

        $OU = "OU=Contacts,OU=T2 - Users,OU=Tier 2,OU=AllData,DC=ADH,DC=LOCAL"
        # Check to see if the user already exists in AD
        if (Get-ADObject -Filter { mail -eq $username }) {

            # If user does exist, give a warning
            Write-Warning "A contact with: $username already exists in Active Directory. Returning to Main Menu."
            Show-MainMenu
        }
        else {
                Write-Host "Creating $username..." -ForegroundColor DarkYellow
                try {
                    # User does not exist then proceed to create the new user account
                    # Account will be created in the OU provided by the $OU variable read from the CSV file
                    $contactDetails = @{
                    givenName = $firstname
                    sn = $lastname
                    displayName = $displayName
                    Mail  = $username
                    proxyAddresses = "SMTP:" + $username
                    targetAddress = "SMTP:" + $username
                }

                Write-Log "New-ADObject -Name $displayName -Type Contact -Path $OU -OtherAttributes $contactDetails"

                    New-ADObject `
                        -Name $displayName `
                        -Type "Contact" `
                        -Path $OU `
                        -OtherAttributes $contactDetails
                    
                }
                catch {
                    Write-Host -f red "Encountered Error:"$($_.Exception.Message)                    
                    Write-Log "Encountered Error:$_.Exception.Message"
                    Write-Warning "CREATE CONTACT FAILED, RETURNING TO MAIN MENU"
                    Show-MainMenu

                }

                try {
                    $Contact = Get-ADObject -Filter "mail -eq '$username'" -Properties DistinguishedName
                    Write-Host "Adding $username to group ADEntraSyncGroup..." -ForegroundColor DarkYellow
                    Write-Log "Set-ADGroup -Identity `"ADEntraSyncGroup`" -Add @{'member'=`"$($Contact.DistinguishedName)`"}"
                    Set-ADGroup -Identity "ADEntraSyncGroup"  -Add @{'member'=$contact.DistinguishedName}

                    $Contact = Get-ADObject -Filter "mail -eq '$username'" -Properties DistinguishedName
                    Write-Host "Adding $username to group Email Filtering CallDept Bypass..." -ForegroundColor DarkYellow
                    Write-Log "Set-ADGroup -Identity `"Email Filtering CallDept Bypass`" -Add @{'member'=`"$($Contact.DistinguishedName)`"}"
                    Set-ADGroup -Identity "Email Filtering CallDept Bypass"  -Add @{'member'=$contact.DistinguishedName}
                }
                catch {
                    Write-Host -f red "Encountered Error:"$($_.Exception.Message)            
                    Write-Log "Encountered Error:$_.Exception.Message"
                    Write-Warning "FAILED TO ASSIGN DEFAULT GROUPS, CONTINUING"
                }


            }

    }

    $CSV = ""
    $CSVPath = ""

    
    Write-Host "Contacts created successfully, returning to Main Menu`n"  -ForegroundColor Cyan

    Show-MainMenu
}
# Next series of menu options are for managing Full Control delegate access, updates msExchDelegateListLink in AD
function Invoke-DelegateAccessAction {
    do {
        Write-Host "------`nDELEGATE ACCESS MENU`n------" -ForegroundColor Cyan
        Write-Host "1. ADD Full Control Access`n2. REMOVE Full Control Access`n3. ADD Send As Access`n4. REMOVE Send As Access`n5. Main Menu`n" -ForegroundColor Yellow
        $menuresponse = Read-Host [Enter Selection]
        switch ($menuresponse) {
            "1" { grant-delegate-full-access-1 }
            "2" { remove-delegate-full-access-1 }
            "3" { grant-send-as-access-1 }
            "4" { remove-send-as-access-1 }
            "5" { Show-MainMenu }
        }
    }
    until (1..3 -contains $menuresponse) 
}

function grant-delegate-full-access-1 {
    do {
        $CSV = ""
        $CSVPath = ""
        Write-Host "------`nGRANT DELEGATE ACCESS MENU`n------" -ForegroundColor Cyan
        Write-Host "Please create a CSV file with the following columns: `n"  -ForegroundColor Cyan
        Write-Host "Mailbox, DelegateUser, AutoMap`n"  -ForegroundColor Green
        Write-Host "Note that Mailbox (email) is the mailbox you want to give access to, and DelegateUser is the user (email) to give access: `nAutoMap Default is True to specify False enter False into the column"  -ForegroundColor Cyan
        Write-Host "Specify the path to the CSV:`n"  -ForegroundColor Yellow
        
        $CSVPath = Read-Host [Enter CSV Path]
        $CSVPath = $CSVPath.Replace("`"", "")

        try {
        
            if (!(Test-Path $CSVPath)) 
            { throw }
        
        }
        
        catch {
            Write-Host -f red "Encountered Error:"$($_.Exception.Message)            
            Write-Log "Encountered Error:$_.Exception.Message"
            Write-Warning "CSV FILE DOES NOT EXIST, RETURNING TO MAIN MENU"
            Show-MainMenu
        }
        
        $CSV = Import-Csv -Path $CSVPath

        Write-Host "Please verify the data below is correct`n"  -ForegroundColor Yellow
        
        #Displays all CSV info on screen for user review
        foreach ($delegate in $CSV) {
            $UMailboxDelegate = $delegate.Mailbox
            $UDelegateUser = $delegate.DelegateUser
            $UAutoMapping = $delegate.AutoMap

            Write-Host "Mailbox: $UMailboxDelegate`nDelegate User: $UDelegateUser`nAutoMap: $UAutoMapping"  -ForegroundColor Green
            Write-Host "------" -ForegroundColor Cyan
        }

        Write-Host "Is all the information above correct? (Scroll up)`n"  -ForegroundColor Cyan
        Write-Host "1. Yes (Delegate Access will be granted)`n2. No (Will go to beginning of menu)`n3. Main Menu`n"  -ForegroundColor Yellow
        $menuresponse = Read-Host [Enter Selection]
        switch ($menuresponse) {
            "1" { grant-delegate-full-access-2 }
            "2" { grant-delegate-full-access-1 }
            "3" { Show-MainMenu }
        }
    }
    until (1..3 -contains $menuresponse) 
}

function grant-delegate-full-access-2 {
    foreach ($delegate in $CSV) {
        #Next few lines gets the user info for the mailbox being controlled and the user gaining delegate access.
        $UMailboxDelegate = $delegate.Mailbox
        $UDelegateUser = $delegate.DelegateUser
        $UAutoMapping = $delegate.AutoMap -eq "F" -or $delegate.AutoMap -eq "False"

        #Adds the distinguishedname of the user that needs access to the mailbox and sets into msExchDelegateListLink variable
        try {
            Connect-ExchangeOnline -ShowBanner:$false 
            if ($UAutoMapping) {
                Write-Host "Adding Full Control Delegate Access for $UDelegateUser to mailbox $UMailboxDelegate... With AutoMapping Set to False" -ForegroundColor DarkYellow
                Write-Log "Add-MailboxPermission -Identity $UMailboxDelegate -User $UDelegateUser -AccessRights FullAccess -AutoMapping $false"
                Add-MailboxPermission -Identity $UMailboxDelegate -User $UDelegateUser -AccessRights FullAccess -AutoMapping $false
            }
            else {
                Write-Host "Adding Full Control Delegate Access for $UDelegateUser to mailbox $UMailboxDelegate... With AutoMapping Set to True" -ForegroundColor DarkYellow
                Write-Log "Add-MailboxPermission -Identity $UMailboxDelegate -User $UDelegateUser -AccessRights FullAccess"
                Add-MailboxPermission -Identity $UMailboxDelegate -User $UDelegateUser -AccessRights FullAccess
            }
        }
        catch {
            Write-Host -f red "Encountered Error:"$($_.Exception.Message)            
            Write-Log "Encountered Error:$_.Exception.Message"
            Write-Warning "FAILED TO ADD DELEGATE ACCESS, RETURNING TO MAIN MENU"
            Show-MainMenu
        }

    }
    $CSV = ""
    $CSVPath = ""
        
    Write-Host "Delegate access added successfully, please allow 30 minutes for this to sync to 365. Returning to Main Menu`n"  -ForegroundColor Cyan

    Show-MainMenu
}

# This section functions the same as grant-delegate-full-access-1 for user info review
function remove-delegate-full-access-1 {
    do {
        $CSV = ""
        $CSVPath = ""
        Write-Host "------`REMOVE DELEGATE ACCESS MENU`n------" -ForegroundColor Cyan
        Write-Host "Please create a CSV file with the following columns: `n"  -ForegroundColor Cyan
        Write-Host "Mailbox, DelegateUser`n"  -ForegroundColor Green
        Write-Host "Note that Mailbox (email) is the mailbox you want to remove access from, and DelegateUser is the user (email) to remove access from: `n"  -ForegroundColor Cyan
        Write-Host "Specify the path to the CSV:`n"  -ForegroundColor Yellow
            
        $CSVPath = Read-Host [Enter CSV Path]
        $CSVPath = $CSVPath.Replace("`"", "")

        try {
        
            if (!(Test-Path $CSVPath)) 
            { throw }
        
        }
        
        catch {
            Write-Host -f red "Encountered Error:"$($_.Exception.Message)            
            Write-Log "Encountered Error:$_.Exception.Message"
            Write-Warning "CSV FILE DOES NOT EXIST, RETURNING TO MAIN MENU"
            Show-MainMenu
        }
        
        $CSV = Import-Csv -Path $CSVPath

        Write-Host "Please verify the data below is correct`n"  -ForegroundColor Yellow
            
    
        foreach ($delegate in $CSV) {
            $UMailboxDelegate = $delegate.Mailbox
            $UDelegateUser = $delegate.DelegateUser
    
            Write-Host "Mailbox: $UMailboxDelegate`nDelegate User: $UDelegateUser`n"  -ForegroundColor Green
            Write-Host "------" -ForegroundColor Cyan
        }
    
        Write-Host "Is all the information above correct? (Scroll up)`n"  -ForegroundColor Cyan
        Write-Host "1. Yes (Delegate access will be removed)`n2. No (Will go to beginning of menu)`n3. Main Menu`n"  -ForegroundColor Yellow
        $menuresponse = Read-Host [Enter Selection]
        switch ($menuresponse) {
            "1" { remove-delegate-full-access-2 }
            "2" { remove-delegate-full-access-1 }
            "3" { Show-MainMenu }
        }
    }
    until (1..3 -contains $menuresponse) 
}
    
#Section is almost the same as grant-delegate-full-access-2 except it removes the distinguishedname for the user that is being removed from delegate access from msExchDelegateListLink
function remove-delegate-full-access-2 {
    foreach ($delegate in $CSV) {
        $UMailboxDelegate = $delegate.Mailbox
        $UDelegateUser = $delegate.DelegateUser
    
        try {
            Write-Host "Removing Full Control Delegate Access for $UDelegateUser to mailbox $UMailboxDelegate..." -ForegroundColor DarkYellow
            Write-Log "Remove-MailboxPermission -Identity $UMailboxDelegate -User $UDelegateUser -AccessRights FullAccess -InheritanceType All"
            Remove-MailboxPermission -Identity $UMailboxDelegate -User $UDelegateUser -AccessRights FullAccess -InheritanceType All
    
        }
        catch {
            Write-Host -f red "Encountered Error:"$($_.Exception.Message)            
            Write-Log "Encountered Error:$_.Exception.Message"
            Write-Warning "FAILED TO REMOVE DELEGATE ACCESS, RETURNING TO MAIN MENU"
            Show-MainMenu
        }
    
    }
    $CSV = ""
    $CSVPath = ""
            
    Write-Host "Delegate access removed successfully, please allow 30 minutes for this to sync to 365. Returning to Main Menu`n"  -ForegroundColor Cyan
    
    Show-MainMenu
}
    
function grant-send-as-access-1 {
    do {
        $CSV = ""
        $CSVPath = ""
        Write-Host "------`nGRANT SEND AS DELEGATE ACCESS MENU`n------" -ForegroundColor Cyan
        Write-Host "Please create a CSV file with the following columns: `n"  -ForegroundColor Cyan
        Write-Host "Mailbox, DelegateUser`n"  -ForegroundColor Green
        Write-Host "Note that Mailbox (email) is the mailbox you want to give access to, and DelegateUser is the user (email) to give access: `n"  -ForegroundColor Cyan
        Write-Host "Specify the path to the CSV:`n"  -ForegroundColor Yellow
        
        $CSVPath = Read-Host [Enter CSV Path]
        $CSVPath = $CSVPath.Replace("`"", "")

        try {
        
            if (!(Test-Path $CSVPath)) 
            { throw }
        
        }
        
        catch {
            Write-Host -f red "Encountered Error:"$($_.Exception.Message)            
            Write-Log "Encountered Error:$_.Exception.Message"
            Write-Warning "CSV FILE DOES NOT EXIST, RETURNING TO MAIN MENU"
            Show-MainMenu
        }
        
        $CSV = Import-Csv -Path $CSVPath

        Write-Host "Please verify the data below is correct`n"  -ForegroundColor Yellow
        
        #Displays all CSV info on screen for user review
        foreach ($delegate in $CSV) {
            $UMailboxDelegate = $delegate.Mailbox
            $UDelegateUser = $delegate.DelegateUser

            Write-Host "Mailbox: $UMailboxDelegate`nDelegate User: $UDelegateUser`n"  -ForegroundColor Green
            Write-Host "------" -ForegroundColor Cyan
        }

        Write-Host "Is all the information above correct? (Scroll up)`n"  -ForegroundColor Cyan
        Write-Host "1. Yes (Delegate Access will be granted)`n2. No (Will go to beginning of menu)`n3. Main Menu`n"  -ForegroundColor Yellow
        $menuresponse = Read-Host [Enter Selection]
        switch ($menuresponse) {
            "1" { grant-send-as-access-2 }
            "2" { grant-send-as-access-1 }
            "3" { Show-MainMenu }
        }
    }
    until (1..3 -contains $menuresponse) 
}

function grant-send-as-access-2 {

    Connect-ExchangeOnline -ShowBanner:$false

    foreach ($delegate in $CSV) {
        #Next few lines gets the user info for the mailbox being controlled and the user gaining delegate access.
        $UMailboxDelegate = $delegate.Mailbox
        $UDelegateUser = $delegate.DelegateUser

        #Adds the distinguishedname of the user that needs access to the mailbox and sets into msExchDelegateListLink variable
        try {

            Write-Host "Adding Send As Delegate Access for $UDelegateUser to mailbox $UMailboxDelegate..." -ForegroundColor DarkYellow
            Write-Log "Add-RecipientPermission -Identity $UMailboxDelegate -Trustee $UDelegateUser -AccessRights SendAs"
            Add-RecipientPermission -Identity $UMailboxDelegate -Trustee $UDelegateUser -AccessRights SendAs

        }
        catch {
            Write-Host -f red "Encountered Error:"$($_.Exception.Message)            
            Write-Log "Encountered Error:$_.Exception.Message"
            Write-Warning "FAILED TO ADD DELEGATE ACCESS, RETURNING TO MAIN MENU"
            Show-MainMenu
        }

    }
    $CSV = ""
    $CSVPath = ""
        
    Write-Host "Delegate access added successfully, please allow up to 5 minutes for changes to take effect. Returning to Main Menu`n"  -ForegroundColor Cyan

    Show-MainMenu
}

# This section functions the same as grant-delegate-full-access-1 for user info review
function remove-send-as-access-1 {
    do {
        $CSV = ""
        $CSVPath = ""
        Write-Host "------`REMOVE SEND AS DELEGATE ACCESS MENU`n------" -ForegroundColor Cyan
        Write-Host "Please create a CSV file with the following columns: `n"  -ForegroundColor Cyan
        Write-Host "Mailbox, DelegateUser`n"  -ForegroundColor Green
        Write-Host "Note that Mailbox (email) is the mailbox you want to remove access from, and DelegateUser is the user (email) to remove access from: `n"  -ForegroundColor Cyan
        Write-Host "Specify the path to the CSV:`n"  -ForegroundColor Yellow
            
        $CSVPath = Read-Host [Enter CSV Path]
        $CSVPath = $CSVPath.Replace("`"", "")

        try {
        
            if (!(Test-Path $CSVPath)) 
            { throw }
        
        }
        
        catch {
            Write-Host -f red "Encountered Error:"$($_.Exception.Message)            
            Write-Log "Encountered Error:$_.Exception.Message"
            Write-Warning "CSV FILE DOES NOT EXIST, RETURNING TO MAIN MENU"
            Show-MainMenu
        }
        
        $CSV = Import-Csv -Path $CSVPath

        Write-Host "Please verify the data below is correct`n"  -ForegroundColor Yellow
            
    
        foreach ($delegate in $CSV) {
            $UMailboxDelegate = $delegate.Mailbox
            $UDelegateUser = $delegate.DelegateUser
    
            Write-Host "Mailbox: $UMailboxDelegate`nDelegate User: $UDelegateUser`n"  -ForegroundColor Green
            Write-Host "------" -ForegroundColor Cyan
        }
    
        Write-Host "Is all the information above correct? (Scroll up)`n"  -ForegroundColor Cyan
        Write-Host "1. Yes (Delegate access will be removed)`n2. No (Will go to beginning of menu)`n3. Main Menu`n"  -ForegroundColor Yellow
        $menuresponse = Read-Host [Enter Selection]
        switch ($menuresponse) {
            "1" { remove-send-as-access-2 }
            "2" { remove-send-as-access-1 }
            "3" { Show-MainMenu }
        }
    }
    until (1..3 -contains $menuresponse) 
}
    
#Section is almost the same as grant-delegate-full-access-2 except it removes the distinguishedname for the user that is being removed from delegate access from msExchDelegateListLink
function remove-send-as-access-2 {

    Connect-ExchangeOnline -ShowBanner:$false 

    foreach ($delegate in $CSV) {
        $UMailboxDelegate = $delegate.Mailbox
        $UDelegateUser = $delegate.DelegateUser
    
    
        try {

            Write-Host "Removing Full Control Delegate Access for $UDelegateUser to mailbox $UMailboxDelegate..." -ForegroundColor DarkYellow
            Write-Log "remove-RecipientPermission -Identity $UMailboxDelegate -Trustee $UDelegateUser -AccessRights SendAs"
            remove-RecipientPermission -Identity $UMailboxDelegate -Trustee $UDelegateUser -AccessRights SendAs
    
        }
        catch {
            Write-Host -f red "Encountered Error:"$($_.Exception.Message)            
            Write-Log "Encountered Error:$_.Exception.Message"
            Write-Warning "FAILED TO REMOVE DELEGATE ACCESS, RETURNING TO MAIN MENU"
            Show-MainMenu
        }
    
    }
    $CSV = ""
    $CSVPath = ""
            
    Write-Host "Delegate access removed successfully, please allow up to 5 minutes for changes to take effect. Returning to Main Menu`n"  -ForegroundColor Cyan
    
    Show-MainMenu
}
    

function Invoke-GroupMembershipAction {
    do {
        Write-Host "------`nGROUP MEMBERSHIP MENU`n------" -ForegroundColor Cyan
        Write-Host "1. Get Group Membership`n2. ADD Group Membership`n3. REMOVE Group Membership`n4. Create New Group`n5. Main Menu`n" -ForegroundColor Yellow
        $menuresponse = Read-Host [Enter Selection]
        switch ($menuresponse) {
            "1" { Get-GroupMembership }
            "2" { Grant-GroupMembership }
            "3" { remove-group-membership-1 }
            "4" { Confirm-NewGroupCreation }
            "5" { Show-MainMenu }
        }
    }
    until (1..4 -contains $menuresponse) 
}
 
# This section gets all group membership of a single user for easy review.  Intended to spot-check user access and does not have a CSV fed into it.
function Get-GroupMembership {
    Write-Host "------`nLIST GROUP MEMBERSHIP OF USER MENU`n------" -ForegroundColor Cyan
    Write-Host "Enter the username you wish to display group membership`n" -ForegroundColor Yellow
    $username = Read-Host [Enter Username]
    #$userdn = (Get-ADObject -Filter { CN -eq $username }).distinguishedName
    $userdn = @(
        Get-ADObject -Filter { SamAccountName -eq $username } -ErrorAction SilentlyContinue
        Get-ADObject -Filter { CN -eq $username } -ErrorAction SilentlyContinue
        Get-ADObject -Filter { UserPrincipalName -eq $username } -ErrorAction SilentlyContinue
        Get-ADObject -Filter { mail -eq $username } -ErrorAction SilentlyContinue
    ) | Select-Object -First 1 -ExpandProperty DistinguishedName


    try {
        $groups = get-adprincipalgroupmembership $userdn | Select-Object name

    }
    catch {
        Write-Host -f red "Encountered Error:"$($_.Exception.Message)        
        Write-Log "Encountered Error:$_.Exception.Message"
        Write-Warning "FAILED TO GET USER/GROUP MEMBERSHIP, RETURNING TO MAIN MENU"
        Show-MainMenu
    }

    foreach ($groupnames in $groups) {
        $group = $groupnames.name
        Write-Host "$group"  -ForegroundColor Green
    }
    Write-Host "`nHere is a list of all groups in single line CSV format for easy usage:`n" -ForegroundColor Cyan
    $groupcsvlist = $groups.name -join ','
    Write-Host $groupcsvlist -ForegroundColor Green
    Write-Host "`nReturning to main menu.`n`n" -ForegroundColor Cyan

    Show-MainMenu
}

# Gets and reviews desired user group membership, fed via CSV
function Grant-GroupMembership {
    do {
        $CSV = ""
        $CSVPath = ""
        Write-Host "------`nADD GROUP MEMBERSHIP MENU`n------" -ForegroundColor Cyan
        Write-Host "Please create a CSV file with the following columns: `n"  -ForegroundColor Cyan
        Write-Host "Username, GroupName`n"  -ForegroundColor Green
        Write-Host "If adding a user to multiple groups, use the following format GroupNameA;GroupNameB `n"  -ForegroundColor Green
        Write-Host "When adding a contact, please use the email address of the contact for the Username column `n" -ForegroundColor Green
        Write-Host "Specify the path to the CSV:`n"  -ForegroundColor Yellow
            
        $CSVPath = Read-Host [Enter CSV Path]
        $CSVPath = $CSVPath.Replace("`"", "")

        try {
        
            if (!(Test-Path $CSVPath)) 
            { throw }
        
        }
        
        catch {
            Write-Host -f red "Encountered Error:"$($_.Exception.Message)            
            Write-Log "Encountered Error:$($_.Exception.Message)"
            Write-Warning "CSV FILE DOES NOT EXIST, RETURNING TO MAIN MENU"
            Show-MainMenu
        }
        
        $CSV = Import-Csv -Path $CSVPath

        Write-Host "Please verify the data below is correct`n"  -ForegroundColor Yellow
            
    
        foreach ($user in $CSV) {
            $UGroupMembership = $user.GroupName
            $UGroupMembershiparray = $UGroupMembership -split ";"
            $group = $UGroupMembershiparray
            $username = $user.Username
			
            Write-Host "Group: $group`nUsername: $username`n"  -ForegroundColor Green
            Write-Host "------" -ForegroundColor Cyan
        }
    
        Write-Host "Is all the information above correct? (Scroll up)`n"  -ForegroundColor Cyan
        Write-Host "1. Yes (User will be added to Group)`n2. No (Will go to beginning of menu)`n3. Main Menu`n"  -ForegroundColor Yellow
        $menuresponse = Read-Host [Enter Selection]
        switch ($menuresponse) {
            "1" { grant-group-membership-2 }
            "2" { Grant-GroupMembership }
            "3" { Show-MainMenu }
        }
    }
    until (1..3 -contains $menuresponse) 
}
    

function grant-group-membership-2 {
    try {
        foreach ($user in $CSV) {
            $username = $user.Username
            $UGroupMembership = $user.GroupName
            $UGroupMembershiparray = $UGroupMembership -split ";"

            $adObject = @(
                Get-ADObject -Filter { SamAccountName -eq $username } -Properties DistinguishedName,ObjectClass -ErrorAction SilentlyContinue
                Get-ADObject -Filter { CN -eq $username } -Properties DistinguishedName,ObjectClass -ErrorAction SilentlyContinue
                Get-ADObject -Filter { UserPrincipalName -eq $username } -Properties DistinguishedName,ObjectClass -ErrorAction SilentlyContinue
                Get-ADObject -Filter { mail -eq $username } -Properties DistinguishedName,ObjectClass -ErrorAction SilentlyContinue
            ) | Select-Object -First 1

            $userdn = $adObject.DistinguishedName
            $objectClass = $adObject.ObjectClass

            foreach ($group in $UGroupMembershiparray) {
                Write-Host "Adding $username to $group..." -ForegroundColor DarkYellow
                
                # Logging command that will be run
                Write-Log "Adding $username to group $group"

                # Find group by name and add user
                $adGroup = Get-ADGroup -Filter { Name -eq $group }

                if ($adGroup) {
                    if ($objectClass -eq 'contact') {
                        Write-Log "Set-ADGroup -Identity `"$($adGroup.DistinguishedName)`" -Add @{member=`"$userdn`"}"
                        Set-ADGroup -Identity $adGroup.DistinguishedName -Add @{member = $userdn}
                    }
                    else {
                        Write-Log "Add-ADGroupMember -Identity `"$($adGroup.DistinguishedName)`" -Members `"$userdn`""
                        Add-ADGroupMember -Identity $adGroup -Members $userdn
                    }
                }
                else {
                    Write-Warning "Group $group not found, please review"
                    Write-Log "Group $group not found for user $username"
                }
            }
        }
    }
    catch {
        Write-Host -ForegroundColor Red "Encountered Error: $($_.Exception.Message)"
        Write-Log "Encountered Error: $($_.Exception.Message)"
        Write-Warning "FAILED TO ADD GROUP MEMBERSHIP, CONTINUING BUT NEEDS REVIEW"
    }


    $CSV = ""
    $CSVPath = ""
            
    Write-Host "Group Membership added successfully, returning to Main Menu`n" -ForegroundColor Cyan
    Show-MainMenu
}
    
# functionally is the same as grant-group-membership-1
function remove-group-membership-1 {
    do {
        $CSV = ""
        $CSVPath = ""
        Write-Host "------`nREMOVE GROUP MEMBERSHIP MENU`n------" -ForegroundColor Cyan
        Write-Host "Please create a CSV file with the following columns: `n"  -ForegroundColor Cyan
        Write-Host "GroupName, Username`n"  -ForegroundColor Green
        Write-Host "Specify the path to the CSV:`n"  -ForegroundColor Yellow
                
        $CSVPath = Read-Host [Enter CSV Path]
        $CSVPath = $CSVPath.Replace("`"", "")

        try {
        
            if (!(Test-Path $CSVPath)) 
            { throw }
        
        }
        
        catch {
            Write-Host -f red "Encountered Error:"$($_.Exception.Message)
            Write-Log "Encountered Error:$($_.Exception.Message)"
            Write-Warning "CSV FILE DOES NOT EXIST, RETURNING TO MAIN MENU"
            Show-MainMenu
        }
        
        $CSV = Import-Csv -Path $CSVPath

        Write-Host "Please verify the data below is correct`n"  -ForegroundColor Yellow
                
        
                
        foreach ($groupmember in $CSV) {
            $group = $groupmember.GroupName
            $username = $groupmember.Username
    
            Write-Host "Group: $group`nUsername: $username`n"  -ForegroundColor Green
            Write-Host "------" -ForegroundColor Cyan
        }
    
        Write-Host "Is all the information above correct? (Scroll up)`n"  -ForegroundColor Cyan
        Write-Host "1. Yes (User will be removed from Group membership)`n2. No (Will go to beginning of menu)`n3. Main Menu`n"  -ForegroundColor Yellow
        $menuresponse = Read-Host [Enter Selection]
        switch ($menuresponse) {
            "1" { remove-group-membership-2 }
            "2" { remove-group-membership-1 }
            "3" { Show-MainMenu }
        }
    }
    until (1..3 -contains $menuresponse) 
}
         
# functionally is the same as grant-group-membership-2 except it uses remove-adgroupmember instead of add.
function remove-group-membership-2 {
    foreach ($groupmember in $CSV) {
        $group = $groupmember.GroupName
        $username = $groupmember.Username
        #$userdn = (Get-ADObject -Filter { CN -eq $username }).distinguishedName
        $userdn = @(
            Get-ADObject -Filter { SamAccountName -eq $username } -ErrorAction SilentlyContinue
            Get-ADObject -Filter { CN -eq $username } -ErrorAction SilentlyContinue
            Get-ADObject -Filter { UserPrincipalName -eq $username } -ErrorAction SilentlyContinue
            Get-ADObject -Filter { mail -eq $username } -ErrorAction SilentlyContinue
        ) | Select-Object -First 1 -ExpandProperty DistinguishedName

        $groupformatted = $group.Replace("`"", "")
    
        try {

            $grpcount = (get-adgroup -filter { name -like $groupformatted -or samaccountname -like $groupformatted } | Measure-Object).count
            if ($grpcount -ne "1") {
                throw
            }
        }
        catch {
            Write-Host -f red "Encountered Error:"$($_.Exception.Message)
            Write-Log "Encountered Error:$($_.Exception.Message)"
            Write-Warning "FAILED TO GET GROUP, RETURNING TO MAIN MENU"
            Show-MainMenu
        }

        try {
            Write-Host "Removing group membership for $username to group $groupformatted..." -ForegroundColor DarkYellow
            Write-Log "get-adgroup -filter { name -like $groupformatted -or samaccountname -like $groupformatted } | Remove-ADGroupMember -Members $username"
            get-adgroup -filter { name -like $groupformatted -or samaccountname -like $groupformatted } | Remove-ADGroupMember -Members $userdn
    
        }
        catch {
            Write-Host -f red "Encountered Error:"$($_.Exception.Message)
            Write-Log "Encountered Error:$($_.Exception.Message)"
            Write-Warning "FAILED TO REMOVE GROUP MEMBERSHIP FOR $username, CONTINUING"
        }



    
    }
    $CSV = ""
    $CSVPath = ""
            
    Write-Host "Group Membership removed successfully, returning to Main Menu`n"  -ForegroundColor Cyan
    $CSV = ""
    Show-MainMenu
}


function Confirm-NewGroupCreation {
    do {
        $CSV = ""
        $CSVPath = ""
        Write-Host "------`nCREATE NEW GROUP MENU`n------" -ForegroundColor Cyan
        Write-Host "Please create a CSV file with the following columns: `n"  -ForegroundColor Cyan
        Write-Host "GroupName, GroupEmail, GroupMembership`n"  -ForegroundColor Green
        Write-Host "Note that the GroupMembership field needs to have a semicolon between users WITHOUT quotes and contain the name of the samaccountname of users, such as:`n"  -ForegroundColor Cyan
        Write-Host "lazer.admin; amrose; admin`n"  -ForegroundColor Green
        Write-Host "Specify the path to the CSV:`n"  -ForegroundColor Yellow
        
        $CSVPath = Read-Host [Enter CSV Path]
        $CSVPath = $CSVPath.Replace("`"", "")

        try {
        
            if (!(Test-Path $CSVPath)) 
            { throw }
        
        }
        
        catch {
            Write-Host -f red "Encountered Error:"$($_.Exception.Message)
            Write-Warning "CSV FILE DOES NOT EXIST, RETURNING TO MAIN MENU"
            Show-MainMenu
        }
        
        $CSV = Import-Csv -Path $CSVPath
        
        
        Write-Host "Please verify the data below is correct`n"  -ForegroundColor Yellow
        
        #Iterates through each entry in the CSV and displays it on screen for user review
        foreach ($grp in $CSV) {
            $GroupName = $grp.GroupName
            $GroupEmail = $grp.GroupEmail
            $GroupMembership = $grp.GroupMembership
            
            $UGroupMembershipFormatted = $GroupMembership -replace "; ", ", "

            Write-Host "group Name: $GroupName`nGroup Email: $GroupEmail`nGroup Membership: $UGroupMembershipFormatted"  -ForegroundColor Green
            Write-Host "------" -ForegroundColor Cyan
        }

        Write-Host "Is all the information above correct? (Scroll up)`n"  -ForegroundColor Cyan
        Write-Host "1. Yes (group will be created)`n2. No (Will go to beginning of menu)`n3. Main Menu`n"  -ForegroundColor Yellow
        $menuresponse = Read-Host [Enter Selection]
        switch ($menuresponse) {
            "1" { Add-NewGroup }
            "2" { Confirm-NewGroupCreation }
            "3" { Show-MainMenu }
        }
    }
    until (1..3 -contains $menuresponse) 
}

# Pushes data received and reviewed from section 1 above
function Add-NewGroup {
    foreach ($grp in $CSV) {
        
        # Read Group data from each field in each row and assign the data to a variable as below
        $GroupName = $grp.GroupName
        $GroupEmail = $grp.GroupEmail
        $GroupMembership = $grp.GroupMembership
        $primarySMTPProxy = "SMTP:" + $grp.GroupEmail
        $OU = "OU=Distribution,OU=T2 - Groups,OU=Tier 2,OU=AllData,DC=ADH,DC=LOCAL"

        # Check to see if the Group already exists in AD
        if (get-adgroup -F { SamAccountName -eq $GroupName }) {
            
            # If Group does exist, give a warning
            Write-Warning "A group with samaccountname $GroupName already exists in Active Directory. Returning to Main Menu"
            Show-MainMenu
        }
        else {
            
            # Group does not exist then proceed to create the new Group
            # Group will be created in the OU provided by the $OU variable read from the CSV file
            # All sets should be enclosed within try segments, with critical updates failing back to main menu
            try {

                Write-Host "Creating group $GroupName..." -ForegroundColor DarkYellow
                Write-Log "New-ADGroup -Name $GroupName -GroupScope Universal -Path $OU -Otherattributes @{`'Mail`'=$GroupEmail }"

                New-ADGroup -Name $GroupName -GroupScope Universal -Path $OU -Otherattributes @{'Mail' = $GroupEmail }

                     

                Write-Host "Adding ProxyAddresses for $GroupName..." -ForegroundColor DarkYellow
                #Sets Proxy Addresses
                Write-Log "Set-ADGroup $GroupName -add @{proxyaddresses = $primarySMTPProxy }"
                Set-ADGroup $GroupName -add @{proxyaddresses = $primarySMTPProxy }

                Write-Host "Adding $GroupName to group ADEntraSyncGroup..." -ForegroundColor DarkYellow
                Write-Log "Add-ADGroupMember -Identity `"ADEntraSyncGroup`" -Members $GroupName"
                Add-ADGroupMember -Identity "ADEntraSyncGroup" -Members $GroupName
            
                # If group is created, show message
                Write-Host "The group $GroupName is created." -ForegroundColor Cyan

            }
            catch {
                Write-Host -f red "Encountered Error:"$($_.Exception.Message)
                #Fails to main menu if not successful
                Write-Log "Encountered Error:$($_.Exception.Message)"
                Write-Warning "Failed to create Group, RETURNING TO MAIN MENU"
                Show-MainMenu
            }

        }

        # Attempts to apply all group membership from the CSV
        try {
            $UGroupMembershiparray = $GroupMembership.Split("; ")

            
            foreach ($u in $UGroupMembershiparray) {
                Write-Host "Adding $u to $GroupName..." -ForegroundColor DarkYellow
                Write-Log "get-adgroup -filter `"name -eq `"$GroupName`"`" | Add-ADGroupMember -Members $u"
                get-adgroup -filter "name -eq `"$GroupName`"" | Add-ADGroupMember -Members $u
            }  

        }
        catch {
            Write-Host -f red "Encountered Error:"$($_.Exception.Message)
            Write-Log "Encountered Error:$($_.Exception.Message)"
            # Only displays warning and does not fail to main menu if there are group issues as the group was already created at this point
            Write-Warning "GROUP MEMBERSHIP FAILED, CONTINUING"
        }

    }
    $CSV = ""
    $CSVPath = ""

        
    Write-Host "Users created successfully, returning to Main Menu`n"  -ForegroundColor Cyan

    Show-MainMenu

}



# This section is intended to be used when a user(s) is no longer with the company. Is fed via CSV in case there are multiple users and for easier data entry/review.
function Invoke-OffboardReactivateAction {
    do {
        Write-Host "------`nOFFBOARD / REACTIVATE USER MENU`n------" -ForegroundColor Cyan
        Write-Host "1. Offboard User`n2. Reactivate User`n3. Main Menu`n" -ForegroundColor Yellow
        $menuresponse = Read-Host [Enter Selection]
        switch ($menuresponse) {
            "1" { Invoke-OffboardUserAction }
            "2" { Invoke-ReactivateUserAction }
            "3" { Show-MainMenu }
        }
    }
    until (1..3 -contains $menuresponse)
}

function Invoke-OffboardUserAction {
    do {
        $CSV = ""
        $CSVPath = ""
        Write-Host "------`nOFFBOARD USER MENU`n------" -ForegroundColor Cyan
        Write-Host "Please create a CSV file with the following columns: `n"  -ForegroundColor Cyan
        Write-Host "Username, Email`n"  -ForegroundColor Green
        Write-Host "Specify the path to the CSV:`n"  -ForegroundColor Yellow

        $CSVPath = Read-Host [Enter CSV Path]
        $CSVPath = $CSVPath.Replace("`"", "")

        try {
        
            if (!(Test-Path $CSVPath)) 
            { throw }
        
        }
        
        catch {
            Write-Host -f red "Encountered Error:"$($_.Exception.Message)
            Write-Log "Encountered Error:$($_.Exception.Message)"
            Write-Warning "CSV FILE DOES NOT EXIST, RETURNING TO MAIN MENU"
            Show-MainMenu
        }
        
        $CSV = Import-Csv -Path $CSVPath

        Write-Host "Please verify the data below is correct`n"  -ForegroundColor Yellow
        

        foreach ($user in $CSV) {
            $username = $user.Username
            $email = $user.Email
            Write-Host "Username: $username`nEmail: $email"  -ForegroundColor Green
            Write-Host "------" -ForegroundColor Cyan
        }

        Write-Host "Is all the information above correct? (Scroll up)`n"  -ForegroundColor Cyan
        Write-Host "1. Yes (User will be DISABLED and converted to Shared Mailbox)`n2. No (Will go to beginning of menu)`n3. Main Menu`n"  -ForegroundColor Yellow
        $menuresponse = Read-Host [Enter Selection]
        switch ($menuresponse) {
            "1" { Set-OffboardUser }
            "2" { Invoke-OffboardUserAction }
            "3" { Show-MainMenu }
        }
    }
    until (1..3 -contains $menuresponse) 
}

# Performs set operations to offboard a user. Currently:
# - Disables the user in Active Directory (AD).
# - Moves the user to the "Disabled Users" Organizational Unit (OU).
# - Removes the user from all AD groups except the ADEntraSyncGroup and Domain Users groups.
# - Converts the user to a shared mailbox in Microsoft 365.
# - Adds an autoreply to the user's email.
# - Removes the user from the Global Address List (GAL).
# - Records the date and the user who executed the script in the "Info" attribute of the Disabled User.
function Set-OffboardUser {

    Connect-ExchangeOnline -ShowBanner:$false 

    foreach ($user in $CSV) {
        $username = $user.Username
        $email = $user.Email
        $sam = Get-ADUserBySamOrUpn -Identity $username

        try {
            Write-Host "Setting mailbox for $email to Shared Type..." -ForegroundColor DarkYellow
            Write-Log "set-mailbox $email -type shared"
            set-mailbox $email -type shared

        }
        catch {

            Write-Host -f red "Encountered Error:"$($_.Exception.Message)
            Write-Log "Encountered Error:$($_.Exception.Message)"
            #Hard fails since this is the first operation and indicates data was incorrect in CSV
            Write-Warning "FAILED TO SET MAILBOX TO SHARED, RETURNING TO MAIN MENU"
            Show-MainMenu
        }

        try {
            Write-Host "Setting AutoReply for $email..." -ForegroundColor DarkYellow
            Write-Log "Set-MailboxAutoReplyConfiguration $email -AutoReplyState Enabled -ExternalMessage `"<p>The email address you have attempted to contact is no longer in use.<br>Please reach out to <a href=""mailto:info@alldatahealth.com"">info@alldatahealth.com</a>.</p>`" -InternalMessage `"<p>The email address you have attempted to contact is no longer in use.<br>Please reach out to <a href=""mailto:info@alldatahealth.com"">info@alldatahealth.com</a>.</p>`""
            Set-MailboxAutoReplyConfiguration $email -AutoReplyState Enabled -ExternalMessage "<p>The email address you have attempted to contact is no longer in use.<br>Please reach out to <a href=""mailto:info@alldatahealth.com"">info@alldatahealth.com</a>.</p>" -InternalMessage "<p>The email address you have attempted to contact is no longer in use.<br>Please reach out to <a href=""mailto:info@alldatahealth.com"">info@alldatahealth.com</a>.</p>"
        }
        catch {
            Write-Host -f red "Encountered Error:"$($_.Exception.Message)            
            Write-Log "Encountered Error:$_.Exception.Message"
            Write-Warning "FAILED TO SET AUTOREPLY FOR $email, CONTINUING BUT REVIEW IS NEEDED"
        }

        try {
            Write-Host "Disabling AD User $username..." -ForegroundColor DarkYellow
            Write-Log "Get-ADUserBySamOrUpn -Identity $username | Disable-ADAccount"
            Get-ADUserBySamOrUpn -Identity $username | Disable-ADAccount
        
        }
        catch {
            Write-Host -f red "Encountered Error:"$($_.Exception.Message)            
            Write-Log "Encountered Error:$_.Exception.Message"
            #Does not hard fail since the user was already converted to a shared mailbox and would be in an 'incomplete' state
            Write-Warning "FAILED TO DISABLE USER, CONTINUING BUT REVIEW IS NEEDED"
        }
        
        
        try {
            Write-Host "Saving the Date and Executing user info to $username Attributes..." -ForegroundColor DarkYellow
            Write-Log "Get-ADUserBySamOrUpn -Identity $username | Set-ADUser -Replace @{info = `"Disabled on $(Get-Time) by $ExecutingUser`" }"
            Get-ADUserBySamOrUpn -Identity $username | Set-ADUser -Replace @{info = "Disabled on $(Get-Time) by $ExecutingUser" } 
        }
        catch {
            Write-Host -f red "Encountered Error:"$($_.Exception.Message)            
            Write-Log "Encountered Error:$_.Exception.Message"
            Write-Warning "FAILED TO SAVE DATE AND EXECUTING USER TO INFO ATTRIBUTE, CONTINUING BUT NEEDS REVIEW"
        }


        try {
            Write-Host "Removing $email from the Global Address List..." -ForegroundColor DarkYellow
            Write-Log "Get-ADUserBySamOrUpn -Identity $username | Set-ADObject -Replace @{msExchHideFromAddressLists = $true }"
            Get-ADUserBySamOrUpn -Identity $username | Set-ADObject -Replace @{msExchHideFromAddressLists = $true }   
        }
        catch {
            Write-Host -f red "Encountered Error:"$($_.Exception.Message) 
            Write-Log "Encountered Error:$_.Exception.Message"
            Write-Warning "FAILED TO SAVE DATE AND EXECUTING USER TO INFO ATTRIBUTE, CONTINUING BUT NEEDS REVIEW"
        }
    

        # The Below Saves The users Group Memberships to the Attribute extensionAttribute1 before removing the user from all Group's excluding Domain Users and ADEntraSyncGroup
        $remaininggroups = Get-ADUserBySamOrUpn -Identity $username | Get-ADPrincipalGroupMembership | Select-Object -Property Name, distinguishedName
        $groupList = $remaininggroups.Name -join ", "
        
        try {
            Write-Host "Saving Group Memberships for disabled user $username..." -ForegroundColor DarkYellow
            $existingAttribute1 = (Get-ADUserBySamOrUpn -Identity $username -Properties extensionAttribute1).extensionAttribute1
            if ($existingAttribute1) {
                $groupList = "$existingAttribute1 | $groupList"
                Write-Log "Get-ADUserBySamOrUpn -Identity $username | Set-ADObject -Replace @{extensionAttribute1 = $groupList }"
                Get-ADUserBySamOrUpn -Identity $username | Set-ADObject -Replace @{extensionAttribute1 = $groupList }
            } else {
                Write-Log "Get-ADUserBySamOrUpn -Identity $username | Set-ADObject -Add @{extensionAttribute1 = $groupList }"
                Get-ADUserBySamOrUpn -Identity $username | Set-ADObject -Add @{extensionAttribute1 = $groupList }
            }
        }
        catch {
            Write-Host -f red "Encountered Error:"$($_.Exception.Message)            
            Write-Log "Encountered Error:$_.Exception.Message"
            Write-Warning "FAILED TO SAVE GROUP MEMBERSHIPS TO ATTRIBUTE EXTENSIONATTRIBUTE1, CONTINUING BUT NEEDS REVIEW"
        }

        try {
            $originalDN = (Get-ADUserBySamOrUpn -Identity $username).DistinguishedName
            $originalOUPath = $originalDN -replace '^CN=[^,]+,', ''
            Write-Host "Saving original OU for $username..." -ForegroundColor DarkYellow
            $existingAttribute2 = (Get-ADUserBySamOrUpn -Identity $username -Properties extensionAttribute2).extensionAttribute2
            if ($existingAttribute2) {
                $originalOUPath = "$existingAttribute2 | $originalOUPath"
                Write-Log "Get-ADUserBySamOrUpn -Identity $username | Set-ADObject -Replace @{extensionAttribute2 = $originalOUPath}"
                Get-ADUserBySamOrUpn -Identity $username | Set-ADObject -Replace @{extensionAttribute2 = $originalOUPath}
            } else {
                Write-Log "Get-ADUserBySamOrUpn -Identity $username | Set-ADObject -Add @{extensionAttribute2 = $originalOUPath}"
                Get-ADUserBySamOrUpn -Identity $username | Set-ADObject -Add @{extensionAttribute2 = $originalOUPath}
            }
        }
        catch {
            Write-Host -f red "Encountered Error:"$($_.Exception.Message)
            Write-Log "Encountered Error:$_.Exception.Message"
            Write-Warning "FAILED TO SAVE ORIGINAL OU TO EXTENSIONATTRIBUTE2, CONTINUING BUT NEEDS REVIEW"
        }

        foreach ($rgrpname in $remaininggroups) {
            if ($rgrpname.Name -ne "ADEntraSyncGroup" -and $rgrpname.Name -ne "Domain Users" ) {
                try {
                    Write-Host "Removing $username from group $($rgrpname.Name)..." -ForegroundColor DarkYellow
                    Write-Log "Remove-ADGroupMember -Identity $($rgrpname.Name) -Members $sam"
                    Remove-ADGroupMember -Identity $($rgrpname.distinguishedName) -Members $sam
                }
                catch {
                    Write-Host -f red "Encountered Error:"$($_.Exception.Message)                    
                    Write-Log "Encountered Error:$_.Exception.Message"
                    Write-Warning "FAILED TO REMOVE $username from $($rgrpname.Name), CONTINUING BUT NEEDS REVIEW"
                }
            }
        }

        try {
            Write-Host "Moving $username To Disabled Users OU..." -ForegroundColor DarkYellow
            Write-Log "Get-ADUserBySamOrUpn -Identity $username | Move-ADObject -TargetPath `"OU=Disabled Users, OU=Users, OU=AllData, DC=ADH, DC=LOCAL`""
            Get-ADUserBySamOrUpn -Identity  $username | Move-ADObject -TargetPath "OU=Disabled Users, OU=Users, OU=AllData, DC=ADH, DC=LOCAL"
        
        }
        catch {
            Write-Host -f red "Encountered Error:"$($_.Exception.Message)            
            Write-Log "Encountered Error:$_.Exception.Message"
            Write-Warning "FAILED TO MOVE USER TO DISABLED USERS OU, CONTINUING"
            
        }
    }
    $CSV = ""
    $CSVPath = ""
        
    Write-Host "Offboarded user(s) successfully, please review any messages above. Returning to Main Menu`n"  -ForegroundColor Cyan
    $CSV = ""
    Show-MainMenu
}

# This section is used to update the Phone of a users via CSV: Username, Phone
function Update-Phone {
    $CSV = ""
    $CSVPath = ""
    Write-Host "------`nRENAME USER MENU`n------" -ForegroundColor Cyan
    Write-Host "Please create a CSV file with the following columns: `n"  -ForegroundColor Cyan
    Write-Host "Username, NewPhone`n"  -ForegroundColor Green
    Write-Host "Note: This script will update the Phone Number for the user.`n"  -ForegroundColor Cyan
    Write-Host "Specify the path to the CSV:`n"  -ForegroundColor Yellow
                
    $CSVPath = Read-Host [Enter CSV Path]
    $CSVPath = $CSVPath.Replace("`"", "")

    try {
        
        if (!(Test-Path $CSVPath)) 
        { throw }
        
    }
        
    catch {
        Write-Host -f red "Encountered Error:"$($_.Exception.Message)        
        Write-Log "Encountered Error:$_.Exception.Message"
        Write-Warning "CSV FILE DOES NOT EXIST, RETURNING TO MAIN MENU"
        Show-MainMenu
    }
        
    $CSV = Import-Csv -Path $CSVPath

    Write-Host "Please verify the data below is correct`n"  -ForegroundColor Yellow

    foreach ($usern in $CSV) {

        #Gets new values from CSV iteration
        $Username = $usern.Username
        $NewPhone = $usern.NewPhone
        
        $existuser = Get-ADUserBySamOrUpn -Identity $Username -properties telephoneNumber | Select-Object samaccountname, telephoneNumber

        #Gets current values from AD
        $OldPhone = $existuser.telephoneNumber

        #Following series of Write-Host lines are intended for data review of the user
        Write-Host "Phone for user $Username will be changed FROM $OldPhone TO ${NewPhone}: `n"  -ForegroundColor Cyan
        Write-Host "Please double check the data above.`n" -ForegroundColor Cyan
        Write-Host "Is all the information above correct? (Scroll up)`n"  -ForegroundColor Cyan
        Write-Host "1. Process Changes`n2. Cancel and Return to the Main Menu`n" -ForegroundColor Yellow

        $confirmUpdatePhone = Read-Host [Enter Selection]
        switch ($confirmUpdatePhone) {
            "1" {
                try {
                    Write-Host "Attempting to change Phone for $Username ..." -ForegroundColor DarkYellow
                    Write-Log "Get-ADUserBySamOrUpn -Identity  $Username | Set-ADUser -OfficePhone  $NewPhone -PassThru"
                    #Sets new user properties.
                    Get-ADUserBySamOrUpn -Identity $Username | Set-ADUser -OfficePhone  $NewPhone -PassThru
                    Write-Host "User information changed successfully.  Please allow up to 30 minutes for 365 to update.  Updated information below:`n" -ForegroundColor Cyan 

                    #Gets the updated data from AD for review to ensure data was set correctly
                    $existuser = Get-ADUserBySamOrUpn -Identity  $Username -properties samaccountname, telephoneNumber | Select-Object samaccountname, telephoneNumber
                    $OldPhone = $existuser.telephoneNumber
            
            
                    Write-Host "Phone: $OldPhone"  -ForegroundColor Green
                    Write-Host "------`n" -ForegroundColor Cyan

                }
                catch {
                    Write-Host -f red "Encountered Error:"$($_.Exception.Message)                    
                    Write-Log "Encountered Error:$_.Exception.Message"
                    Write-Warning "FAILED TO MODIFY USER ATTRIBUTES. RETURNING TO MAIN MENU"
                    Show-MainMenu
                }

                #Blanks out all the variables just in case there is bad data in next few lines of CSV
                $existuser = ""
                $OldPhone = ""
                $NewPhone = ""


            }
            "2" { Show-MainMenu }
        }
                  
    }

    Write-Host "`nReturning to main menu.`n`n" -ForegroundColor Cyan

    Show-MainMenu
}

# This section is used to update the following attributes of users via CSV: cn, displayname, givenname, name, sn
function Update-UserName {
    $CSV = ""
    $CSVPath = ""
    Write-Host "------`nRENAME USER MENU`n------" -ForegroundColor Cyan
    Write-Host "Please create a CSV file with the following columns: `n"  -ForegroundColor Cyan
    Write-Host "OriginalUsername, FirstName, LastName, DisplayName`n"  -ForegroundColor Green
    Write-Host "Note: This script will update fields related to First Name, Last Name, and Display Name.`n"  -ForegroundColor Cyan
    Write-Host "Specify the path to the CSV:`n"  -ForegroundColor Yellow
                
    $CSVPath = Read-Host [Enter CSV Path]
    $CSVPath = $CSVPath.Replace("`"", "")

    try {
        
        if (!(Test-Path $CSVPath)) 
        { throw }
        
    }
        
    catch {
        Write-Host -f red "Encountered Error:"$($_.Exception.Message)        
        Write-Log "Encountered Error:$_.Exception.Message"
        Write-Warning "CSV FILE DOES NOT EXIST, RETURNING TO MAIN MENU"
        Show-MainMenu
    }
        
    $CSV = Import-Csv -Path $CSVPath

    Write-Host "Please verify the data below is correct`n"  -ForegroundColor Yellow

    foreach ($usern in $CSV) {

        #Gets new values from CSV iteration
        $OriginalUsername = $usern.OriginalUsername
        $Newcn = $usern.DisplayName
        $NewdisplayName = $usern.DisplayName
        $NewgivenName = $usern.FirstName
        $Newname = $usern.DisplayName
        $Newsn = $usern.LastName

        $existuser = Get-ADUserBySamOrUpn -Identity $OriginalUsername -properties cn, sn, displayname, mail, mailnickname | Select-Object cn, displayname, givenname, mail, name, samaccountname, sn, userprincipalname, mailnickname

        #Gets current values from AD
        $Oldcn = $existuser.cn
        $OlddisplayName = $existuser.displayName
        $OldgivenName = $existuser.givenName
        $Oldname = $existuser.name
        $OldsAMAccountName = $existuser.samaccountname
        $Oldsn = $existuser.sn

        #Following series of Write-Host lines are intended for data review of the user
        Write-Host "Attributes for user $OriginalUsername will be changed FROM the following: `n"  -ForegroundColor Cyan

        Write-Host "cn (Should equal displayName): $Oldcn"  -ForegroundColor Green
        Write-Host "displayName: $OlddisplayName"  -ForegroundColor Green
        Write-Host "givenName (First Name): $OldgivenName"  -ForegroundColor Green
        Write-Host "name (Should equal displayName): $Oldname"  -ForegroundColor Green
        Write-Host "sn (Last Name): $Oldsn"  -ForegroundColor Green

        Write-Host "The following fields for user $OriginalUsername will be changed TO the following: `n"  -ForegroundColor Yellow

        Write-Host "cn: $NewdisplayName"  -ForegroundColor Green
        Write-Host "displayName: $NewdisplayName"  -ForegroundColor Green
        Write-Host "givenName: $NewgivenName"  -ForegroundColor Green
        Write-Host "name: $Newname"  -ForegroundColor Green
        Write-Host "sn: $Newsn"  -ForegroundColor Green

        Write-Host "Please double check ALL the data above.`n" -ForegroundColor Cyan
        Write-Host "Is all the information above correct? (Scroll up)`n"  -ForegroundColor Cyan
        Write-Host "1. Process Changes`n2. Cancel and Return to the Main Menu`n" -ForegroundColor Yellow

        $confirmRename = Read-Host [Enter Selection]
        switch ($confirmRename) {
            "1" {
                try {
                    Write-Host "Attempting to rename $OldsAMAccountName..." -ForegroundColor DarkYellow
                    Write-Log "Get-ADUserBySamOrUpn -Identity  $OldsAMAccountName | Set-ADUser -DisplayName $NewdisplayName -GivenName $NewgivenName -Surname $Newsn -PassThru | Rename-ADObject -NewName $NewdisplayName -PassThru"

                    #Sets new user properties. Needs to use Rename-ADObject to update cn and name
                    Get-ADUserBySamOrUpn -Identity $OldsAMAccountName | Set-ADUser -DisplayName $NewdisplayName -GivenName $NewgivenName -Surname $Newsn -PassThru | Rename-ADObject -NewName $NewdisplayName -PassThru
                    Write-Host "User information changed successfully.  Please allow up to 30 minutes for 365 to update.  Updated information below:`n" -ForegroundColor Cyan 

                    #Gets the updated data from AD for review to ensure data was set correctly
                    $existuser = Get-ADUserBySamOrUpn -Identity $OldsAMAccountName -properties cn, sn, displayname, mail, mailnickname | Select-Object cn, displayname, givenname, mail, name, samaccountname, sn, userprincipalname, mailnickname
                    $Oldcn = $existuser.cn
                    $OlddisplayName = $existuser.displayName
                    $OldgivenName = $existuser.givenName
                    $Oldname = $existuser.name
                    $OldsAMAccountName = $existuser.samaccountname
                    $Oldsn = $existuser.sn
            
            
                    Write-Host "cn (Should equal displayName): $Oldcn"  -ForegroundColor Green
                    Write-Host "displayName: $OlddisplayName"  -ForegroundColor Green
                    Write-Host "givenName (First Name): $OldgivenName"  -ForegroundColor Green
                    Write-Host "name (Should equal displayName): $Oldname"  -ForegroundColor Green
                    Write-Host "sAMAccountName: $OldsAMAccountName"  -ForegroundColor Green
                    Write-Host "sn (Last Name): $Oldsn"  -ForegroundColor Green

                    Write-Host "------`n" -ForegroundColor Cyan

                }
                catch {
                    Write-Host -f red "Encountered Error:"$($_.Exception.Message)                    
                    Write-Log "Encountered Error:$_.Exception.Message"
                    Write-Warning "FAILED TO MODIFY USER ATTRIBUTES. RETURNING TO MAIN MENU"
                    Show-MainMenu
                }

                #Blanks out all the variables just in case there is bad data in next few lines of CSV
                $existuser = ""
                $Oldcn = ""
                $OlddisplayName = ""
                $OldgivenName = ""
                $Oldmail = ""
                $Oldmailnickname = ""
                $Oldname = ""
                $OldsAMAccountName = ""
                $Oldsn = ""
                $OlduserPrincipalName = ""
                $oldproxy = ""
                $newproxy = ""
                $newproxyalias = ""

            }
            "2" { Show-MainMenu }
        }
                  
    }

    Write-Host "`nReturning to main menu.`n`n" -ForegroundColor Cyan

    Show-MainMenu
}

function Invoke-AliasManagementAction {
    do {
        Write-Host "------`nALIAS MANAGEMENT MENU`n------" -ForegroundColor Cyan
        Write-Host "1. Get Email Aliases`n2. ADD Email Alias`n3. REMOVE Email Aliases`n4. Main Menu`n" -ForegroundColor Yellow
        $menuresponse = Read-Host [Enter Selection]
        switch ($menuresponse) {
            "1" { Get-EmailAliases }
            "2" { Confirm-AddEmailAlias }
            "3" { Confirm-RemoveEmailAlias }
            "4" { Show-MainMenu }
        }
    }
    until (1..4 -contains $menuresponse) 
}
 
# This section gets all aliases of a single user for easy review.  Intended to spot-check user aliases and does not have a CSV fed into it.
function Get-EmailAliases {
    Write-Host "------`nLIST ALIASES OF USER MENU`n------" -ForegroundColor Cyan
    Write-Host "Enter the username you wish to aliases (not email address)`n" -ForegroundColor Yellow
    $username = Read-Host [Enter Username]

    try {
        $user = Get-ADUserBySamOrUpn -Identity $username | Select-Object samaccountname, displayname
        $usersam = $user.samaccountname
        $userdisplay = $user.displayname
        $aliases = Get-ADUserBySamOrUpn -Identity $username -properties proxyaddresses | Select-Object @{Name = "ProxyAddresses"; Expression = { ($_.ProxyAddresses | Where-Object { $_ -clike "smtp*" } | ForEach-Object { $_ -replace "smtp:", "" }) } }
        Write-Host "`nUsername: $usersam`ndisplayName: $userdisplay`n"

    }
    catch {
        Write-Host -f red "Encountered Error:"$($_.Exception.Message)        
        Write-Log "Encountered Error:$_.Exception.Message"
        Write-Warning "FAILED TO GET USER, RETURNING TO MAIN MENU"
        Show-MainMenu
    }

    foreach ($ualias in $aliases) {
        $alias = $ualias.ProxyAddresses
        if ($alias -notlike "*onmicrosoft*") {
            Write-Host "Alias: $alias"  -ForegroundColor Green
        }
    }
    Write-Host "`nHere is a list of all aliases in single line CSV format for easy usage:`n" -ForegroundColor Cyan
    Write-Host $alias -ForegroundColor Green
    Write-Host "`nReturning to main menu.`n`n" -ForegroundColor Cyan

    Show-MainMenu
}

# Gets and reviews desired user group membership, fed via CSV
function Confirm-AddEmailAlias {
    do {
        $CSV = ""
        $CSVPath = ""
        Write-Host "------`nADD EMAIL ALIASES MENU`n------" -ForegroundColor Cyan
        Write-Host "Please create a CSV file with the following columns: `n"  -ForegroundColor Cyan
        Write-Host "Username, aliases`n"  -ForegroundColor Green
        Write-Host "Note that the alias field needs to be only a single email address. If you need to add more than 1 alias, you need to add multiple lines.`n"  -ForegroundColor Cyan
        Write-Host "Specify the path to the CSV:`n"  -ForegroundColor Yellow
            
        $CSVPath = Read-Host [Enter CSV Path]
        $CSVPath = $CSVPath.Replace("`"", "")

        try {
        
            if (!(Test-Path $CSVPath)) 
            { throw }
        
        }
        
        catch {
            Write-Host -f red "Encountered Error:"$($_.Exception.Message)            
            Write-Log "Encountered Error:$_.Exception.Message"
            Write-Warning "CSV FILE DOES NOT EXIST, RETURNING TO MAIN MENU"
            Show-MainMenu
        }
        
        $CSV = Import-Csv -Path $CSVPath

        Write-Host "Please verify the data below is correct`n"  -ForegroundColor Yellow
            
    
        foreach ($aliasuser in $CSV) {
            $aliasusername = $aliasuser.username
            $alias = $aliasuser.aliases


            Write-Host "Username: $aliasusername`nAlias: $alias`n`n"  -ForegroundColor Green
            
        }


        Write-Host "------" -ForegroundColor Cyan
        Write-Host "Is all the information above correct? (Scroll up)`n"  -ForegroundColor Cyan
        Write-Host "1. Yes (Users will have aliases added to their account)`n2. No (Will go to beginning of menu)`n3. Main Menu`n"  -ForegroundColor Yellow
        $aliasusername = ""
        $alias = ""
        $menuresponse = Read-Host [Enter Selection]
        switch ($menuresponse) {
            "1" { Add-EmailAlias }
            "2" { Confirm-AddEmailAlias }
            "3" { Show-MainMenu }
        }
    }
    until (1..3 -contains $menuresponse) 
}
    

function Add-EmailAlias {
    foreach ($aliasuser in $CSV) {
        $aliasusername = $aliasuser.username
        $alias = $aliasuser.aliases
        $proxy = "smtp:" + $alias

    
        try {
            Write-Host "Adding Alias (ProxyAddresses) for $aliasusername..." -ForegroundColor DarkYellow
            Write-Log "Get-ADUserBySamOrUpn -Identity $aliasusername | Set-AdUser -add @{ProxyAddresses = $($proxy) }"
            Get-ADUserBySamOrUpn -Identity $aliasusername | Set-AdUser -add @{ProxyAddresses = $($proxy) }
    
        }
        catch {
            Write-Host -f red "Encountered Error:"$($_.Exception.Message)           
            Write-Log "Encountered Error:$_.Exception.Message"
            Write-Warning "FAILED TO ADD ALIAS, RETURNING TO MAIN MENU"
            $aliasusername = ""
            $alias = ""
            $proxy = ""
            Show-MainMenu
        }
    
    }
    $CSV = ""
    $CSVPath = ""
    $aliasusername = ""
    $alias = ""
    $proxy = ""
            
    Write-Host "Alias added successfully, please allow 30 minutes to sync. Returning to Main Menu`n"  -ForegroundColor Cyan
    
    Show-MainMenu
}
    
# functionally is the same as grant-group-membership-1
function Confirm-RemoveEmailAlias {
    do {
        $CSV = ""
        $CSVPath = ""
        Write-Host "------`nREMOVE EMAIL ALIAS MENU`n------" -ForegroundColor Cyan
        Write-Host "Please create a CSV file with the following columns: `n"  -ForegroundColor Cyan
        Write-Host "Username, aliases`n"  -ForegroundColor Green
        Write-Host "Note that the alias field needs to be only a single email address. If you need to add more than 1 alias, you need to add multiple lines.`n"  -ForegroundColor Cyan
        Write-Host "Specify the path to the CSV:`n"  -ForegroundColor Yellow
                
        $CSVPath = Read-Host [Enter CSV Path]
        $CSVPath = $CSVPath.Replace("`"", "")

        try {
        
            if (!(Test-Path $CSVPath)) 
            { throw }
        
        }
        
        catch {
            Write-Host -f red "Encountered Error:"$($_.Exception.Message)            
            Write-Log "Encountered Error:$_.Exception.Message"
            Write-Warning "CSV FILE DOES NOT EXIST, RETURNING TO MAIN MENU"
            Show-MainMenu
        }
        
        $CSV = Import-Csv -Path $CSVPath

        Write-Host "Please verify the data below is correct`n"  -ForegroundColor Yellow
                
        
        foreach ($aliasuser in $CSV) {
            $aliasusername = $aliasuser.username
            $alias = $aliasuser.aliases

            Write-Host "Username: $aliasusername`nAlias: $alias`n`n"  -ForegroundColor Green
            
        }
    
        Write-Host "Is all the information above correct? (Scroll up)`n"  -ForegroundColor Cyan
        Write-Host "1. Yes (Users will have aliases removed from their account)`n2. No (Will go to beginning of menu)`n3. Main Menu`n"  -ForegroundColor Yellow
        $menuresponse = Read-Host [Enter Selection]
        switch ($menuresponse) {
            "1" { Remove-EmailAlias }
            "2" { Confirm-RemoveEmailAlias }
            "3" { Show-MainMenu }
        }
    }
    until (1..3 -contains $menuresponse) 
}
         
# functionally is the same as grant-group-membership-2 except it uses remove-adgroupmember instead of add.
function Remove-EmailAlias {
    foreach ($aliasuser in $CSV) {
        $aliasusername = $aliasuser.username
        $alias = $aliasuser.aliases
        $proxy = "smtp:" + $alias

    
        try {
            Write-Host "Removing Alias (ProxyAddresses) for $aliasusername..." -ForegroundColor DarkYellow
            Write-Log "Get-ADUserBySamOrUpn -Identity $aliasusername | Set-ADuser -Remove @{proxyAddresses = $proxy }"
            Get-ADUserBySamOrUpn -Identity $aliasusername | Set-ADuser -Remove @{proxyAddresses = $proxy }
    
        }
        catch {
            Write-Host -f red "Encountered Error:"$($_.Exception.Message)            
            Write-Log "Encountered Error:$_.Exception.Message"
            Write-Warning "FAILED TO REMOVE ALIAS, RETURNING TO MAIN MENU"
            $aliasusername = ""
            $alias = ""
            $proxy = ""
            Show-MainMenu
        }
    
    }
    $CSV = ""
    $CSVPath = ""
    $aliasusername = ""
    $alias = ""
    $proxy = ""


    Write-Host "Alias removed successfully, please allow 30 minutes to sync. Returning to Main Menu`n"  -ForegroundColor Cyan
    $CSV = ""
    Show-MainMenu
}


# The following sections are used to enable/disable email forwarding in 365, uses Connect-ExchangeOnline
function Invoke-EmailForwardingAction {
    do {
        $CSV = ""
        $CSVPath = ""
        Write-Host "------`nEmail Forwarding MENU`n------" -ForegroundColor Cyan
        Write-Host "1. ENABLE Email Forwarding`n2. DISABLE Email Forwarding`n3. Main Menu`n" -ForegroundColor Yellow
        $menuresponse = Read-Host [Enter Selection]
        switch ($menuresponse) {
            "1" { enable-email-forwarding-1 }
            "2" { disable-email-forwarding-1 }
            "3" { Show-MainMenu }
        }
    }
    until (1..3 -contains $menuresponse) 
}
    
function enable-email-forwarding-1 {
    do {
        $CSV = ""
        $CSVPath = ""
        Write-Host "------`nENABLE EMAIL FORWARDING MENU`n------" -ForegroundColor Cyan        
        Write-Host "Please create a CSV file with the following columns: `n"  -ForegroundColor Cyan
        Write-Host "mailboxAddress, ForwardingAddress`n"  -ForegroundColor Green
        Write-Host "Specify the path to the CSV:`n"  -ForegroundColor Yellow
            
        $CSVPath = Read-Host [Enter CSV Path]
        $CSVPath = $CSVPath.Replace("`"", "")

        try {
        
            if (!(Test-Path $CSVPath)) 
            { throw }
        
        }
        
        catch {
            Write-Host -f red "Encountered Error:"$($_.Exception.Message)            
            Write-Log "Encountered Error:$_.Exception.Message"
            Write-Warning "CSV FILE DOES NOT EXIST, RETURNING TO MAIN MENU"
            Show-MainMenu
        }
        
        $CSV = Import-Csv -Path $CSVPath

        Write-Host "Please verify the data below is correct`n"  -ForegroundColor Yellow
            
    
        foreach ($mailboxforward in $CSV) {
            $mailbox = $mailboxforward.mailboxAddress
            $forwardingaddr = $mailboxforward.ForwardingAddress
    

            Write-Host "Mailbox: $mailbox`nForwardingAddress: $forwardingaddr`n"  -ForegroundColor Green
        }
    
        Write-Host "Is all the information above correct? (Scroll up)`n"  -ForegroundColor Cyan
        Write-Host "1. Yes (User will have mail forwarding enabled)`n2. No (Will go to beginning of menu)`n3. Main Menu`n"  -ForegroundColor Yellow
        $menuresponse = Read-Host [Enter Selection]
        switch ($menuresponse) {
            "1" { enable-email-forwarding-2 }
            "2" { enable-email-forwarding-1 }
            "3" { Show-MainMenu }
        }
    }
    until (1..3 -contains $menuresponse) 
}
    
function enable-email-forwarding-2 {
    foreach ($mailboxforward in $CSV) {
        $mailbox = $mailboxforward.mailboxAddress
        $forwardingaddr = $mailboxforward.ForwardingAddress
    
        try {

            # This if/else statement checks if the email is internal or external.  This was done this way as email should not be typically forwarded to internal AND external users at the same time
            # The if is for internal forwarding, the else is for external forwarding. Note the ForwardingAddress (internal) and ForwardingSMTPAddress (external) values.  Could be changed to do both at the same time.
            if ($forwardingaddr -like "*@alldatahealth.com") {
                Connect-ExchangeOnline -ShowBanner:$false 

                Write-Host "Enabling forwarding for $mailbox to $forwardingaddr..." -ForegroundColor DarkYellow
                Write-Log "Set-Mailbox -Identity $mailbox -ForwardingAddress $forwardingaddr -DeliverToMailboxAndForward $true"
                Set-Mailbox -Identity $mailbox -ForwardingAddress $forwardingaddr -DeliverToMailboxAndForward $true
            }
            else {
                Connect-ExchangeOnline -ShowBanner:$false 
                Write-Host "Enabling forwarding for $mailbox to $forwardingaddr..." -ForegroundColor DarkYellow
                Write-Log "Set-Mailbox -Identity $mailbox -ForwardingSmtpAddress $forwardingaddr -DeliverToMailboxAndForward $true"
                Set-Mailbox -Identity $mailbox -ForwardingSmtpAddress $forwardingaddr -DeliverToMailboxAndForward $true
            }   
        }
        catch {
            Write-Host -f red "Encountered Error:"$($_.Exception.Message)           
            Write-Log "Encountered Error:$_.Exception.Message"
            Write-Warning "FAILED TO ADD EMAIL FORWARDING, RETURNING TO MAIN MENU"
            Show-MainMenu
        }
    
    }
    $CSV = ""
    $CSVPath = ""
            
    Write-Host "Email forwarding added successfully, returning to Main Menu`n"  -ForegroundColor Cyan
    $CSV = ""
    Show-MainMenu
}
    

function disable-email-forwarding-1 {
    $CSV = ""
    $CSVPath = ""
    do {
        Write-Host "------`nDISABLE EMAIL FORWARDING MENU`n------" -ForegroundColor Cyan        
        Write-Host "Please create a CSV file with the following columns: `n"  -ForegroundColor Cyan
        Write-Host "mailboxAddress`n"  -ForegroundColor Green
        Write-Host "Specify the path to the CSV:`n"  -ForegroundColor Yellow
            
        $CSVPath = Read-Host [Enter CSV Path]
        $CSVPath = $CSVPath.Replace("`"", "")

        try {
        
            if (!(Test-Path $CSVPath)) 
            { throw }
        
        }
        
        catch {
            Write-Host -f red "Encountered Error:"$($_.Exception.Message)            
            Write-Log "Encountered Error:$_.Exception.Message"
            Write-Warning "CSV FILE DOES NOT EXIST, RETURNING TO MAIN MENU"
            Show-MainMenu
        }
        
        $CSV = Import-Csv -Path $CSVPath

        Write-Host "Please verify the data below is correct`n"  -ForegroundColor Yellow
            
    
        foreach ($mailboxforward in $CSV) {
            $mailbox = $mailboxforward.mailboxAddress
    
            Write-Host "Mailbox: $mailbox`n"  -ForegroundColor Green
        }
    
        Write-Host "Is all the information above correct? (Scroll up)`n"  -ForegroundColor Cyan
        Write-Host "1. Yes (User will have mail forwarding disabled)`n2. No (Will go to beginning of menu)`n3. Main Menu`n"  -ForegroundColor Yellow
        $menuresponse = Read-Host [Enter Selection]
        switch ($menuresponse) {
            "1" { disable-email-forwarding-2 }
            "2" { disable-email-forwarding-1 }
            "3" { Show-MainMenu }
        }
    }
    until (1..3 -contains $menuresponse) 
}

# functionally the same as enable-email-forwarding-2 section, except removes forwarding by setting the forwardidng addresses to null and DeliverToMailboxAndForward to false
# Accounts for internal and external forwarding
function disable-email-forwarding-2 {

    foreach ($mailboxforward in $CSV) {
        $mailbox = $mailboxforward.mailboxAddress
    
        try {

            Connect-ExchangeOnline -ShowBanner:$false 

            Write-Host "Disabling forwarding for $mailbox..." -ForegroundColor DarkYellow
            Write-Log "Set-Mailbox -Identity $mailbox -ForwardingAddress $null -ForwardingSmtpAddress $null -DeliverToMailboxAndForward $false"
            Set-Mailbox -Identity $mailbox -ForwardingAddress $null -ForwardingSmtpAddress $null -DeliverToMailboxAndForward $false
        }
        catch {
            Write-Host -f red "Encountered Error:"$($_.Exception.Message)            
            Write-Log "Encountered Error:$_.Exception.Message"
            Write-Warning "FAILED TO DISABLE EMAIL FORWARDING, RETURNING TO MAIN MENU"
            Show-MainMenu
        }
    
    }
    $CSV = ""
    $CSVPath = ""
            
    Write-Host "Email forwarding added successfully, returning to Main Menu`n"  -ForegroundColor Cyan
    $CSV = ""
    Show-MainMenu
}


function Invoke-OutOfOfficeAction {
    do {
        $CSV = ""
        $CSVPath = ""
        Write-Host "------`nOUT OF OFFICE MENU`n------" -ForegroundColor Cyan
        Write-Host "1. ENABLE Out of Office for a single user `n2. ENABLE Out of Office from CSV `n3. DISABLE Out of Office`n4. Main Menu`n" -ForegroundColor Yellow
        $menuresponse = Read-Host [Enter Selection]
        switch ($menuresponse) {
            "1" { Enable-OutOfOffice-User }
            "2" { Enable-OutOfOffice-CSV }
            "3" { Disable-OutOfOffice }
            "4" { Show-MainMenu }
        }
    }
    until (1..3 -contains $menuresponse) 
}

# Sets out of office for a single user, does not use CSV and email and message are typed into Powershell and reviewed before setting. Uses Connect-ExchangeOnline
function Enable-OutOfOffice-User {
   
    $CSV = ""
    $CSVPath = ""
    Write-Host "------`nENABLE OUT OF OFFICE MENU`n------" -ForegroundColor Cyan
    Write-Host "This will set an Out of Office reply for both internal and external senders." -ForegroundColor Cyan
    Write-Host "Specify the email address to ENABLE Out of Office on:`n"  -ForegroundColor Yellow
            
    $emailOOO = Read-Host [Enter email address]

    Write-Host "Specify the Out of Office message:`n"  -ForegroundColor Yellow

    $messageOOO = Read-Host [Enter message]



    Write-Host "Please verify the data below is correct`n"  -ForegroundColor Yellow
        
    Write-Host "Email address: $emailOOO`n" -ForegroundColor Green
    Write-Host "Message: $messageOOO`n" -ForegroundColor Green
        
    
    Write-Host "Is all the information above correct? (Scroll up)`n"  -ForegroundColor Cyan
    Write-Host "1. Yes (User will have Out of Office ENABLED)`n2. No (Will go to beginning of menu)`n3. Main Menu`n"  -ForegroundColor Yellow

    do {
        $menuresponse = Read-Host [Enter Selection]
        switch ($menuresponse) {
            "1" { 

                try {
                    Connect-ExchangeOnline -ShowBanner:$false 

                    Write-Host "Enabling Auto-Reply message for $emailOOO..." -ForegroundColor DarkYellow
                    Write-Log "Set-MailboxAutoReplyConfiguration $emailOOO -AutoReplyState Enabled -ExternalMessage $messageOOO -InternalMessage $messageOOO"

                    Set-MailboxAutoReplyConfiguration $emailOOO -AutoReplyState Enabled -ExternalMessage $messageOOO -InternalMessage $messageOOO

                    Write-Host "Out of Office set successfully for $emailOOO. Returning to the Main Menu.`n"  -ForegroundColor Cyan
                    
                    
                    $emailOOO = ""
                    $messageOOO = ""

                    Show-MainMenu
                }
                catch {
                    Write-Host -f red "Encountered Error:"$($_.Exception.Message)                    
                    Write-Log "Encountered Error:$_.Exception.Message"
                    Write-Warning "FAILED TO ENABLE OUT OF OFFICE, RETURNING TO MAIN MENU"
                    
                    
                    $emailOOO = ""
                    $messageOOO = ""

                    Show-MainMenu
                }
                
            }
            "2" { Enable-OutOfOffice-User }
            "3" { Show-MainMenu }
        }
    }
    until (1..3 -contains $menuresponse) 
}

# Sets out of office for Users from CSV, HTML file and Start and End times have to be provided. Is reviewed before setting. Uses Connect-ExchangeOnline
function Enable-OutOfOffice-CSV {
   
    $CSV = ""
    $CSVPath = ""
    Write-Host "------`nENABLE OUT OF OFFICE MENU`n------" -ForegroundColor Cyan
    Write-Host "This will set an Out of Office reply for both internal and external senders." -ForegroundColor Cyan
    Write-Host "Please create a CSV file with the following column: `n"  -ForegroundColor Cyan
    Write-Host "mailboxAddress,`n"  -ForegroundColor Green

    $CSVPath = Read-Host [Enter CSV Path]
    $CSVPath = $CSVPath.Replace("`"", "")
    

    try {
        
        if (!(Test-Path $CSVPath)) 
        { throw }
    
    }
    
    catch {
        Write-Host -f red "Encountered Error:"$($_.Exception.Message)        
        Write-Log "Encountered Error:$_.Exception.Message"
        Write-Warning "CSV FILE DOES NOT EXIST, RETURNING TO MAIN MENU"
        Show-MainMenu
    }

    Write-Host "Specify the path to the  Out of Office message HTML file:`n"  -ForegroundColor Yellow

    $HTMLPath = Read-Host [Enter HTML Path]
    $HTMLPath = $HTMLPath.Replace("`"", "")

    try {
        
        if (!(Test-Path $HTMLPath)) 
        { throw }
    
    }
    
    catch {
        Write-Host -f red "Encountered Error:"$($_.Exception.Message)        
        Write-Log "Encountered Error:$_.Exception.Message"
        Write-Warning "HTML FILE DOES NOT EXIST, RETURNING TO MAIN MENU"
        Show-MainMenu
    }

    Write-Host "Please verify the CSV data below is correct`n"  -ForegroundColor Yellow
    
    $CSV = Import-Csv -Path $CSVPath

    foreach ($mailbox in $CSV) {

        $oooUser = $mailbox.mailboxAddress
        Write-Host "Mailbox: $oooUser `n"  -ForegroundColor Green
    }

    Write-Host "Please specify the start and end date and time in the follwoing format 04-30-2024 17:00:00"
    
    $StartTime = Read-Host [Enter Start Time]
    $EndTIme = Read-Host [Enter End Time]

    Write-Host "Please verify that the start and end time is corect" -ForegroundColor Yellow

    Write-Host "Start Time: $StartTime`n"  -ForegroundColor Green
    Write-Host "End Time: $EndTime`n"  -ForegroundColor Green
    
    Write-Host "Is all the information above correct? (Scroll up)`n"  -ForegroundColor Cyan
    Write-Host "1. Yes (Users will have Out of Office ENABLED)`n2. No (Will go to beginning of menu)`n3. Main Menu`n"  -ForegroundColor Yellow

    do {
        $menuresponse = Read-Host [Enter Selection]
        switch ($menuresponse) {
            "1" { 

                
                Connect-ExchangeOnline -ShowBanner:$false 
                $messageOOO = Get-Content $HTMLPath -Raw
                    
                foreach ($mailbox in $CSV) {
                    $oooUser = $mailbox.mailboxAddress
                    Write-Host "Enabling Auto-Reply message for: $oooUser`n"  -ForegroundColor Green
                    Write-Log "Set-MailboxAutoReplyConfiguration -Identity $oooUser -AutoReplyState Scheduled -StartTime $StartTime -EndTime $EndTime"

                    try {
                        Set-MailboxAutoReplyConfiguration -Identity $oooUser -AutoReplyState Scheduled -StartTime $StartTime -EndTime $EndTime -ExternalMessage $messageOOO -InternalMessage $messageOOO -ErrorAction Stop
                        Write-Host "Out of Office set successfully for $oooUser`n"  -ForegroundColor Cyan

                    }
                    catch {
                        Write-Host -ForegroundColor Red "Encountered Error for $oooUser $($_.Exception.Message)"
                        Write-Log "Error for $oooUser $($_.Exception.Message)"
                        Write-Warning "FAILED TO ENABLE OUT OF OFFICE FOR $oooUser"
                    
                    
                        $emailOOO = ""
                        $messageOOO = ""

                        Show-MainMenu
                    }
                }    
                Show-MainMenu
                
            }
            "2" { Enable-OutOfOffice-CSV }
            "3" { Show-MainMenu }
        }


    }
    until (1..3 -contains $menuresponse) 
}
    
    
function Disable-OutOfOffice {
    $CSV = ""
    $CSVPath = ""

    Write-Host "------`nDISABLE OUT OF OFFICE MENU`n------" -ForegroundColor Cyan
    Write-Host "This will disable Out of Office reply for a single user.`n" -ForegroundColor Cyan
    Write-Host "Specify the email address to DISABLE Out of Office on:`n"  -ForegroundColor Yellow
            
    $emailOOO = Read-Host [Enter email address]


    Write-Host "Please verify the email address below is correct`n"  -ForegroundColor Yellow
        
    Write-Host "Email address: $emailOOO`n" -ForegroundColor Green
        
    
    Write-Host "Is all the information above correct? (Scroll up)`n"  -ForegroundColor Cyan
    Write-Host "1. Yes (User will have Out of Office DISABLED)`n2. No (Will go to beginning of menu)`n3. Main Menu`n"  -ForegroundColor Yellow

    do {
        $menuresponse = Read-Host [Enter Selection]
        switch ($menuresponse) {
            "1" { 

                try {
                    Connect-ExchangeOnline -ShowBanner:$false 

                    Write-Host "Disabling Auto-Reply message for $emailOOO..." -ForegroundColor DarkYellow
                    Write-Log "Set-MailboxAutoReplyConfiguration $emailOOO -AutoReplyState Disabled -ExternalMessage $null -InternalMessage $null"

                    Set-MailboxAutoReplyConfiguration $emailOOO -AutoReplyState Disabled -ExternalMessage $null -InternalMessage $null

                    Write-Host "Out of Office disabled successfully for $emailOOO. Returning to the Main Menu.`n"  -ForegroundColor Cyan

                    $emailOOO = ""

                    Show-MainMenu
                }
                catch {
                    Write-Host -f red "Encountered Error:"$($_.Exception.Message)
                    Write-Log "Encountered Error:$_.Exception.Message"
                    Write-Warning "FAILED TO DISABLE OUT OF OFFICE, RETURNING TO MAIN MENU"
                    

                    $emailOOO = ""
                    
                    Show-MainMenu
                }
                
            }
            "2" { Disable-OutOfOffice }
            "3" { Show-MainMenu }
        }
    }
    until (1..3 -contains $menuresponse) 
}


#This section is used to add or remove users one at a time to or from Duo and is not fed from a CSV. 
function Invoke-DuoGroupAction {
    do {
        Write-Host "------`n Duo User MENU`n------" -ForegroundColor Cyan
        Write-Host "1. Add Duo User`n2. Remove Duo user`n3. Main Menu`n" -ForegroundColor Yellow
        $menuresponse = Read-Host "Enter Selection"
        switch ($menuresponse) {
            "1" { Add-UserToDuo }
            "2" { Remove-UserFromDuo }
            "3" { Show-MainMenu }
        }
    } until (1..3 -contains $menuresponse)
}

function Add-UserToDuo {
    Write-Host "Please create a CSV file with the following column." -ForegroundColor Cyan
    Write-Host "Only fill the alternatePhone column if the user needs phone call-back enabled." -ForegroundColor Cyan
    Write-Host "If filling the alternatePhone column, please leave the alternateEmail blank" -ForegroundColor Cyan
    Write-Host "The phone number should be in the following format: 1XXXXXXXXXX`n" -ForegroundColor Cyan
    
    Write-Host "userName,alternateEmail,alternatePhone`n" -ForegroundColor Green
    
    Write-Host "Please enter the path of the CSV file" -ForegroundColor Yellow
    
    
    $CSVPath = Read-Host [Enter CSV Path]
    $CSVPath = $CSVPath.Replace("`"", "")

    try {
        
        if (!(Test-Path $CSVPath)) 
        { throw }
    
    }
    
    catch {
        Write-Host -f red "Encountered Error:"$($_.Exception.Message)        
        Write-Log "Encountered Error:$_.Exception.Message"
        Write-Warning "CSV FILE DOES NOT EXIST, RETURNING TO MAIN MENU"
        Show-MainMenu
    }

    Write-Host "Please verify the CSV data below is correct`n"  -ForegroundColor Yellow


    $CSV = Import-Csv -Path $CSVPath

    foreach ($User in $CSV) {
        $Username = $User.userName
        $externalEmail = $User.alternateEmail
        $externalPhone = $User.alternatePhone

        Write-Host "User: $Username. External Email: $externalEmail. Externall Phone: $externalPhone`n"  -ForegroundColor Green
    }

    Write-Host "Is all the information above correct? (Scroll up)`n" -ForegroundColor Cyan
    Write-Host "1. Yes (The User Will Be Added To Duo)`n2. No (Will go to beginning of menu)`n3. Main Menu`n" -ForegroundColor Yellow

    do {
        $menuresponse = Read-Host "Enter Selection"
        switch ($menuresponse) {
            "1" {

                foreach ($User in $CSV) {
                    $Username = $User.userName
                    $externalEmail = $User.alternateEmail
                
                    if ($User.alternatePhone -and $User.alternatePhone.ToString().Trim() -ne "") {
                        $externalPhone = $User.alternatePhone
                        $groupName = "Duo Sync Phone"  # Phone call-back enabled group
                    
                        try {		  
                            Get-ADUserBySamOrUpn -Identity $Username | Set-ADUser -Replace @{otherTelephone = $externalPhone }
                            Add-ADGroupMember -Identity $groupName -Members $Username
                        
                            Write-Host "User $Username has been successfully added to $groupName with external phone $externalPhone" -ForegroundColor Green
                            $DuoSuccess = $true
                        }
                        catch {
                            Write-Host "An error occurred while adding $Username to $groupName. Please check the username, email, and phone, and try again." -ForegroundColor Red
                            Write-Warning "FAILED TO ADD USER TO $groupName, RETURNING TO MAIN MENU"
                            $DuoSuccess = $false
                        }
                    }
                    else {
                        $externalPhone = $null
                        $groupName = "Duo Sync" # Default group
                    
                        try {		  
                            Get-ADUserBySamOrUpn -Identity $Username | Set-ADUser -Replace @{otherMailbox = $externalEmail }
                            Add-ADGroupMember -Identity $groupName -Members $Username
                        
                            Write-Host "User $Username has been successfully added to $groupName with the external email $externalEmail" -ForegroundColor Green
                            $DuoSuccess = $true
                        }
                        catch {
                            Write-Host "An error occurred while adding $Username to $groupName. Please check the username, email, and try again." -ForegroundColor Red
                            Write-Warning "FAILED TO ADD USER TO $groupName, RETURNING TO MAIN MENU"
                            $DuoSuccess = $false
                        }
                    }
                
                    if ($DuoSuccess) {
                        Add-Content -Path $logpath -Value "$(Get-Time) :: Set-ADUser $Username -Add @{otherMailbox = $externalEmail}"
                        if ($externalPhone) {
                            Add-Content -Path $logpath -Value "$(Get-Time) :: Set-ADUser $Username -Add @{otherTelephone = $externalPhone}"
                        }
                        Add-Content -Path $logpath -Value "$(Get-Time) :: Add-ADGroupMember -Identity '$groupName' -Members $Username"
                    }
                    else {
                        Add-Content -Path $logpath -Value "$(Get-Time) :: Encountered Error: $($_.Exception.Message)"                    }
                }
   
                Show-MainMenu
            }
            "2" { Add-UserToDuo }
            "3" { Show-MainMenu }
        }
    } until (1..3 -contains $menuresponse) 
}

function Remove-UserFromDuo {
    Write-Host "Please enter the username of the user to be removed from Duo" -ForegroundColor Yellow
    $DuoUser = Read-Host "Enter Username"
    
    Write-Host "`nPlease verify the data below is correct:`n" -ForegroundColor Yellow
    Write-Host "Username: $DuoUser" -ForegroundColor Green

    Write-Host "Is all the information above correct? (Scroll up)`n" -ForegroundColor Cyan
    Write-Host "1. Yes (The User Will Be Removed From Duo)`n2. No (Will go to beginning of menu)`n3. Main Menu`n" -ForegroundColor Yellow
    
    do {
        $menuresponse = Read-Host "Enter Selection"
        switch ($menuresponse) {
            "1" { 
                try {
                    Remove-ADGroupMember -Identity "Duo Sync" -Members $DuoUser -Confirm:$false
                    Write-Host "User $DuoUser has been successfully removed from Duo Sync." -ForegroundColor Green
                    Add-Content -Path $logpath -Value "$(Get-Time) :: Remove-ADGroupMember -Identity 'Duo Sync' -Members $DuoUser -Confirm:$false"
                    Show-MainMenu
                }
                catch {
                    Write-Host "An error occurred while removing the user. Please check the username and try again." -ForegroundColor Red
                    Add-Content -Path $logpath -Value "$(Get-Time) :: Encountered Error: $($_.Exception.Message)"
                    Write-Warning "FAILED TO REMOVE USER FROM DUO, RETURNING TO MAIN MENU"
                    Show-MainMenu
                }
            }
            "2" { Remove-UserFromDuo }
            "3" { Show-MainMenu }
        }
    } until (1..3 -contains $menuresponse) 
}

#This is section is used to Reset user passwords one at a time.
function Invoke-SetUserPassword {
    Write-Host "------`nRESET USER PASSWORD`n------" -ForegroundColor Cyan
    Write-Host "Enter the username you wish to Reset the Password for`n" -ForegroundColor Yellow
    $username = Read-Host [Enter Username]
    Write-Host "Enter the new password`n" -ForegroundColor Yellow
    $password = Read-Host [Enter Password]

    Write-Host "`nPlease verify the data below is correct:`n" -ForegroundColor Yellow
    Write-Host "Username: $username" -ForegroundColor Green

    Write-Host "Is all the information above correct? (Scroll up)`n" -ForegroundColor Cyan
    Write-Host "1. Yes (The Users Password will be reset)`n2. No (Will go to beginning of menu)`n3. Main Menu`n" -ForegroundColor Yellow

    do {
        $menuresponse = Read-Host "Enter Selection"
        switch ($menuresponse) {
            "1" { 
                try {
                    Set-ADAccountPassword -Identity $username -Reset -NewPassword (ConvertTo-SecureString -AsPlainText "$password" -Force)
                    Set-ADUser -Identity $username -ChangePasswordAtLogon $False
                    Add-Content -Path $logpath -Value "$(Get-Time) :: Set-ADAccountPassword -Identity $username -Reset -NewPassword **OBSCURED**"
                    Add-Content -Path $logpath -Value "$(Get-Time) :: Set-ADUser -Identity $username -ChangePasswordAtLogon $False"
                    Show-MainMenu
        
                }
                catch {
                    Write-Host "An error occurred while reseting the user password. Please check the username and try again." -ForegroundColor Red
                    Add-Content -Path $logpath -Value "$(Get-Time) :: Encountered Error: $($_.Exception.Message)"
                    Write-Warning "FAILED TO RESET THE USER PASSWORD, RETURNING TO MAIN MENU"
                    Show-MainMenu
                }
            }
            "2" { Set-UserPassword }
            "3" { Show-MainMenu }
        }
    } until (1..3 -contains $menuresponse) 
}

function Invoke-UnlockUserAccount {
    Write-Host "------`nUNLOCK USER ACCOUNT`n------" -ForegroundColor Cyan
    Write-Host "Enter the username for the user you wish to unlock`n" -ForegroundColor Yellow
    $username = Read-Host [Enter Username]

    Write-Host "`nPlease verify the data below is correct:`n" -ForegroundColor Yellow
    Write-Host "Username: $username" -ForegroundColor Green

    Write-Host "Is all the information above correct? (Scroll up)`n" -ForegroundColor Cyan
    Write-Host "1. Yes (The Users will be unlocked)`n2. No (Will go to beginning of menu)`n3. Main Menu`n" -ForegroundColor Yellow

    do {
        $menuresponse = Read-Host "Enter Selection"
        switch ($menuresponse) {
            "1" { 
                try {
                    Unlock-ADAccount -Identity $username
                    Add-Content -Path $logpath -Value "$(Get-Time) :: Unlock-ADAccount -Identity $username"
                    Show-MainMenu
        
                }
                catch {
                    Write-Host "An error occurred while unlocking the user account. Please check the username and try again." -ForegroundColor Red
                    Add-Content -Path $logpath -Value "$(Get-Time) :: Encountered Error: $($_.Exception.Message)"
                    Write-Warning "FAILED TO UNLOCK THE USER ACCOUNT, RETURNING TO MAIN MENU"
                    Show-MainMenu
                }
            }
            "2" { Invoke-UnlockUserAccount }
            "3" { Show-MainMenu }
        }
    } until (1..3 -contains $menuresponse) 
}
    
function Invoke-GetLicenseCount {
    Write-Host "1. Get License Count`n2. Main Menu`n" -ForegroundColor Yellow

    do {
        $menuresponse = Read-Host "Enter Selection"
        switch ($menuresponse) {
            "1" { 
                try {
                    Update-AzConfig -EnableLoginByWam $false # We had to disable WAM since users were using runas to launch powershell and had issues authenticating
                    Connect-AzAccount -SubscriptionId "78009903-1567-47ba-a28e-1d5344339dcd"
                
                    # Get the Secret key for ADH-IT Entra App
                    $ClientSecret = Get-AzKeyVaultSecret -VaultName "ADH-InHouse-IT" -Name "ADH-IT" -AsPlainText
                
                    # Convert the secret key to a SecureString
                    $ClientSecretPass = ConvertTo-SecureString -String $ClientSecret -AsPlainText -Force
                
                    # Set the MgGraph params
                    $ClientID = "eb144143-a197-4b94-9eb0-3551736f80d8"
                    $TenantId = "7bef2ee1-1d01-4204-b5f4-e4b89ace0269"
                    $ClientSecretCredential = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList $ClientId, $ClientSecretPass
                
                    # Connect to Microsoft Graph
                    Connect-MgGraph -TenantId $TenantId -ClientSecretCredential $ClientSecretCredential -NoWelcome
                
                    # Retrieve Licenses and map them to readable form
                    $SkuMapping = @{
                        'O365_BUSINESS_ESSENTIALS'  = 'Office 365 Business Basic'
                        'EXCHANGESTANDARD'          = 'Exchange Online Plan 1'
                        'EXCHANGEENTERPRISE'        = 'Exchange Online Plan 2'
                        'PBI_PREMIUM_PER_USER_DEPT' = 'Power BI Premium Per User'
                        'PBI_PREMIUM_PER_USER'      = 'Power BI Premium Per User'
                    }
                
                    # Retrieve SKUs and filter to only necessary ones
                    $skus = Get-MgSubscribedSku -All | Where-Object {
                        $SkuMapping.ContainsKey($_.SkuPartNumber)
                    }
                
                    # Merge by license name
                    $rawSummary = foreach ($sku in $skus) {
                        $total = ($sku.PrepaidUnits.Enabled + $sku.PrepaidUnits.Warning + $sku.PrepaidUnits.Suspended)
                        $assigned = $sku.ConsumedUnits
                        $available = $total - $assigned
                    
                        [pscustomobject]@{
                            'License Name' = $SkuMapping[$sku.SkuPartNumber]
                            'Assigned'     = $assigned
                            'Available'    = $available
                            'Total'        = $total
                        }
                    }
                
                    $summary = $rawSummary | Group-Object 'License Name' | ForEach-Object {
                        $name = $_.Name
                        $assigned = ($_.Group | Measure-Object -Property Assigned -Sum).Sum
                        $available = ($_.Group | Measure-Object -Property Available -Sum).Sum
                        $total = ($_.Group | Measure-Object -Property Total -Sum).Sum
                    
                        Write-Host "License '$name' has $available of $total licenses available (Assigned: $assigned)."
                    }
                
                    Show-MainMenu
                }
                catch {
                    Write-Host "An error occurred while retrieving the licenses. Please check the error messages and try again." -ForegroundColor Red
                    Add-Content -Path $logpath -Value "$(Get-Time) :: Encountered Error: $($_.Exception.Message)"
                    Write-Warning "FAILED TO RETRIEVE THE LICENSES, RETURNING TO MAIN MENU"
                    Show-MainMenu
                }
            }
            "2" { Show-MainMenu }
        }
    } until (1..2 -contains $menuresponse)
}

function Invoke-ReactivateUserAction {
    do {
        $CSV = ""
        $CSVPath = ""
        Write-Host "------`nREACTIVATE USER MENU`n------" -ForegroundColor Cyan
        Write-Host "Please create a CSV file with the following columns:`n" -ForegroundColor Cyan
        Write-Host "Username, Email`n" -ForegroundColor Green
        Write-Host "Note: The user must have been offboarded using this script after 4/27/2026.`n" -ForegroundColor Cyan
        Write-Host "Specify the path to the CSV:`n" -ForegroundColor Yellow

        $CSVPath = Read-Host [Enter CSV Path]
        $CSVPath = $CSVPath.Replace("`"", "")

        try {
            if (!(Test-Path $CSVPath)) { throw }
        }
        catch {
            Write-Host -f red "Encountered Error:"$($_.Exception.Message)
            Write-Log "Encountered Error:$_.Exception.Message"
            Write-Warning "CSV FILE DOES NOT EXIST, RETURNING TO MAIN MENU"
            Show-MainMenu
        }

        $CSV = Import-Csv -Path $CSVPath

        Write-Host "Please verify the data below is correct`n" -ForegroundColor Yellow

        foreach ($user in $CSV) {
            $username = $user.Username
            $email = $user.Email

            # Pull stored attributes for preview
            $adUser = Get-ADUserBySamOrUpn -Identity $username -Properties extensionAttribute1, extensionAttribute2, info
            $storedOU     = $adUser.extensionAttribute2
            $storedGroups = $adUser.extensionAttribute1
            $disabledInfo = $adUser.info

            Write-Host "Username:       $username" -ForegroundColor Green
            Write-Host "Email:          $email" -ForegroundColor Green
            Write-Host "Disabled Info:  $disabledInfo" -ForegroundColor Green
            Write-Host "Original OU:    $storedOU" -ForegroundColor Green
            Write-Host "Groups to restore: $storedGroups" -ForegroundColor Green
            Write-Host "------" -ForegroundColor Cyan
        }

        Write-Host "Is all the information above correct? (Scroll up)`n" -ForegroundColor Cyan
        Write-Host "1. Yes (User will be reactivated)`n2. No (Will go to beginning of menu)`n3. Main Menu`n" -ForegroundColor Yellow
        $menuresponse = Read-Host [Enter Selection]
        switch ($menuresponse) {
            "1" { Set-ReactivateUser }
            "2" { Invoke-ReactivateUserAction }
            "3" { Show-MainMenu }
        }
    }
    until (1..3 -contains $menuresponse)
}

function Set-ReactivateUser {

    Connect-ExchangeOnline -ShowBanner:$false

    foreach ($user in $CSV) {
        $username = $user.Username
        $email    = $user.Email

        $adUser = Get-ADUserBySamOrUpn -Identity $username -Properties extensionAttribute1, extensionAttribute2
        $originalOU   = $adUser.extensionAttribute2
        $savedGroups  = $adUser.extensionAttribute1

        # --- Re-enable AD account ---
        try {
            Write-Host "Enabling AD account for $username..." -ForegroundColor DarkYellow
            Write-Log "Get-ADUserBySamOrUpn -Identity $username | Enable-ADAccount"
            Get-ADUserBySamOrUpn -Identity $username | Enable-ADAccount
        }
        catch {
            Write-Host -f red "Encountered Error:"$($_.Exception.Message)
            Write-Log "Encountered Error:$_.Exception.Message"
            Write-Warning "FAILED TO ENABLE AD ACCOUNT FOR $username, RETURNING TO MAIN MENU"
            Show-MainMenu
        }

        # --- Move back to original OU ---
        if ($originalOU) {
            try {
                Write-Host "Moving $username back to original OU..." -ForegroundColor DarkYellow
                Write-Log "Get-ADUserBySamOrUpn -Identity $username | Move-ADObject -TargetPath `"$originalOU`""
                Get-ADUserBySamOrUpn -Identity $username | Move-ADObject -TargetPath $originalOU
            }
            catch {
                Write-Host -f red "Encountered Error:"$($_.Exception.Message)
                Write-Log "Encountered Error:$_.Exception.Message"
                Write-Warning "FAILED TO MOVE $username TO ORIGINAL OU, CONTINUING BUT NEEDS REVIEW"
            }
        }
        else {
            Write-Warning "No original OU found in extensionAttribute2 for $username — OU move skipped. Manual placement required."
        }

        # --- Unhide from GAL ---
        try {
            Write-Host "Restoring $email to the Global Address List..." -ForegroundColor DarkYellow
            Write-Log "Get-ADUserBySamOrUpn -Identity $username | Set-ADObject -Replace @{msExchHideFromAddressLists = `$false}"
            Get-ADUserBySamOrUpn -Identity $username | Set-ADObject -Replace @{msExchHideFromAddressLists = $false}
        }
        catch {
            Write-Host -f red "Encountered Error:"$($_.Exception.Message)
            Write-Log "Encountered Error:$_.Exception.Message"
            Write-Warning "FAILED TO RESTORE $email TO GAL, CONTINUING BUT NEEDS REVIEW"
        }

        # --- Convert mailbox back to Regular ---
        try {
            Write-Host "Converting mailbox $email back to Regular type..." -ForegroundColor DarkYellow
            Write-Log "Set-Mailbox $email -Type Regular"
            Set-Mailbox $email -Type Regular
        }
        catch {
            Write-Host -f red "Encountered Error:"$($_.Exception.Message)
            Write-Log "Encountered Error:$_.Exception.Message"
            Write-Warning "FAILED TO CONVERT MAILBOX FOR $email, CONTINUING BUT NEEDS REVIEW"
        }

        # --- Disable auto-reply ---
        try {
            Write-Host "Disabling auto-reply for $email..." -ForegroundColor DarkYellow
            Write-Log "Set-MailboxAutoReplyConfiguration $email -AutoReplyState Disabled -ExternalMessage `$null -InternalMessage `$null"
            Set-MailboxAutoReplyConfiguration $email -AutoReplyState Disabled -ExternalMessage $null -InternalMessage $null
        }
        catch {
            Write-Host -f red "Encountered Error:"$($_.Exception.Message)
            Write-Log "Encountered Error:$_.Exception.Message"
            Write-Warning "FAILED TO DISABLE AUTO-REPLY FOR $email, CONTINUING BUT NEEDS REVIEW"
        }

        # --- Re-add to default sync/license groups ---
        try {
            Write-Host "Adding $username to ADEntraSyncGroup..." -ForegroundColor DarkYellow
            Write-Log "Add-ADGroupMember -Identity `"ADEntraSyncGroup`" -Members $username"
            Add-ADGroupMember -Identity "ADEntraSyncGroup" -Members $username

            Write-Host "Adding $username to ADEntra-Assign365License..." -ForegroundColor DarkYellow
            Write-Log "Add-ADGroupMember -Identity `"ADEntra-Assign365License`" -Members $username"
            Add-ADGroupMember -Identity "ADEntra-Assign365License" -Members $username

            Write-Host "Adding $username to T2 - Users..." -ForegroundColor DarkYellow
            Write-Log "Add-ADGroupMember -Identity `"T2 - Users`" -Members $username"
            Add-ADGroupMember -Identity "T2 - Users" -Members $username
        }
        catch {
            Write-Host -f red "Encountered Error:"$($_.Exception.Message)
            Write-Log "Encountered Error:$_.Exception.Message"
            Write-Warning "FAILED TO RE-ADD DEFAULT GROUPS FOR $username, CONTINUING BUT NEEDS REVIEW"
        }

        # --- Restore previous group memberships from extensionAttribute1 ---
        if ($savedGroups) {
            $groupArray = $savedGroups -split ",\s*"
            foreach ($grp in $groupArray) {
                $grp = $grp.Trim()
                if ($grp -eq "Domain Users" -or $grp -eq "ADEntraSyncGroup" -or $grp -eq "T2 - Users") { continue }
                try {
                    Write-Host "Restoring membership: $grp for $username..." -ForegroundColor DarkYellow
                    Write-Log "get-adgroup -filter `"name -eq '$grp'`" | Add-ADGroupMember -Members $username"
                    $adGroup = Get-ADGroup -Filter "name -eq '$grp'" -ErrorAction Stop
                    Add-ADGroupMember -Identity $adGroup -Members $username
                }
                catch {
                    Write-Host -f red "Encountered Error:"$($_.Exception.Message)
                    Write-Log "Encountered Error:$_.Exception.Message"
                    Write-Warning "FAILED TO RESTORE GROUP $grp FOR $username, CONTINUING"
                }
            }
        }
        else {
            Write-Warning "No saved group memberships found in extensionAttribute1 for $username — group restore skipped."
        }

        # --- Clear reactivation-related attributes ---
        try {
            Write-Host "Clearing extensionAttribute1 and extensionAttribute2 for $username..." -ForegroundColor DarkYellow
            Write-Log "Get-ADUserBySamOrUpn -Identity $username | Set-ADObject -Clear extensionAttribute1, extensionAttribute2"
            Get-ADUserBySamOrUpn -Identity $username | Set-ADObject -Clear extensionAttribute1, extensionAttribute2
        }
        catch {
            Write-Host -f red "Encountered Error:"$($_.Exception.Message)
            Write-Log "Encountered Error:$_.Exception.Message"
            Write-Warning "FAILED TO CLEAR EXTENSION ATTRIBUTES FOR $username, CONTINUING BUT NEEDS REVIEW"
        }

        Write-Log "User $username reactivated by $ExecutingUser on $(Get-Time)"
        Write-Host "Reactivation complete for $username. Please review any warnings above.`n" -ForegroundColor Cyan
    }

    $CSV = ""
    $CSVPath = ""

    Write-Host "Reactivation process complete, returning to Main Menu`n" -ForegroundColor Cyan
    Show-MainMenu
}

Show-MainMenu