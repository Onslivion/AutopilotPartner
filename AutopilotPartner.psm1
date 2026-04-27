Import-Module Az.Accounts 

$AZURE_CLI_APP_ID = "04b07795-8ddb-461a-bbee-02f9e1bf7b46"

 function Get-TenantID { # Credit to Daniel Kåven | https://teams.se/powershell-script-find-a-microsoft-365-tenantid/
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true, Position=0, HelpMessage="The domain name of the tenant")]
        [String]$domain
    )
    $request = Invoke-WebRequest -Uri https://login.windows.net/$domain/.well-known/openid-configuration -UseBasicParsing
    $data = ConvertFrom-Json $request.Content
    return $Data.token_endpoint.split('/')[3]
}

function Get-HWID { # Credit to authors of https://www.powershellgallery.com/packages/Get-WindowsAutoPilotInfo/3.9

        $bad = $false

        $session = New-CimSession

        # Get the common properties.
        Write-Verbose "Checking $comp"
        $serial = (Get-CimInstance -CimSession $session -Class Win32_BIOS).SerialNumber

        # Get the hash (if available)
        $devDetail = (Get-CimInstance -CimSession $session -Namespace root/cimv2/mdm/dmmap -Class MDM_DevDetail_Ext01 -Filter "InstanceID='Ext' AND ParentID='./DevDetail'")
        if ($devDetail)
        {
            $hash = $devDetail.DeviceHardwareData
        }
        else
        {
            $bad = $true
            $hash = ""
        }

        # Getting the PKID is generally problematic for anyone other than OEMs, so let's skip it here
        $product = ""

        # Depending on the format requested, create the necessary object
        # Create a pipeline object
        $c = New-Object psobject -Property @{
            "Device Serial Number" = $serial
            "Windows Product ID" = $product
            "Hardware Hash" = $hash
        }

        # Write the object to the pipeline or array
        if ($bad)
        {
            # Report an error when the hash isn't available
            Write-Error -Message "Unable to retrieve device hardware data (hash) from computer $comp" -Category DeviceError
        }
        
        Write-Host "Gathered details for device with serial number: $serial"

        Remove-CimSession $session

        return $c

}

function Wait-UntilComplete { # Credit to authors of https://www.powershellgallery.com/packages/Get-WindowsAutoPilotInfo/3.9

    param (
        [Parameter(Mandatory=$true, Position=0, HelpMessage="Object representing the Autopilot device identity")]  $Device
    )
        #Import Check
        $importStart = Get-Date
        $percent = 0
        $iter = 1
        do {
            $processed = $false
            $importCheck = Get-AutopilotImportedDevice -id $Device.id
            if ($importCheck.state.deviceImportStatus -eq "unknown") {
                Write-Progress -Activity "Autopilot Enrollment" -Status "Awaiting device import..." -PercentComplete $percent
                $percent += 25 / $iter
                if ($percent -ge 100) {
                    $percent = 99
                }
                $iter++
                Start-Sleep 10
            }
            else {
                $processed = $true
            }

        } while (!$processed)

        $importDuration = (Get-Date) - $importStart
        $importSeconds = [Math]::Ceiling($importDuration.TotalSeconds)

        # Verify that the device imported successfully
        try {
            Get-AutopilotDevice -id $importCheck.state.deviceRegistrationId
        }
        catch {
            Write-Error -Message $("The device import failed. Error: " + $_)
            return
        }

        Write-Host "Device imported. Elapsed time to complete import: $importSeconds seconds"
        
        # Sync Check
        Write-Host "Verifying successful import..."
        try {
            Get-AutopilotDevice -id $importCheck.state.deviceRegistrationId
        }
        catch {
            Write-Error -Message $("The device import failed. Error: " + $_)
            return
        }

        $syncStart = Get-Date
        do {
            $processed = $false
            $syncCheck = Get-AutopilotDevice -id $importCheck.state.deviceRegistrationId
            if (!$syncCheck) {
                Write-Progress -Activity "Autopilot Enrollment" -Status "Awaiting Intune sync..."
                Start-Sleep 15
            }
            else {
                $processed = $true
            }
        } while (!$processed)
        $syncDuration = (Get-Date) - $syncStart
        $syncSeconds = [Math]::Ceiling($syncDuration.TotalSeconds)
        Write-Host "Devices synced. Elapsed time to complete sync: $syncSeconds seconds"
        
        # Assignment Check
        $percent = 0
        $iter = 1
        $assignStart = Get-Date
        do {
            $processed = $false
            $assignCheck = Get-AutopilotDevice -Expand -id $importCheck.state.deviceRegistrationId
            if (!$assignCheck.deploymentProfileAssignmentStatus.StartsWith("assigned")) {
                Write-Progress -Activity "Autopilot Enrollment" -Status "Awaiting assignment to a deployment profile... Current Status: $($assignCheck.deploymentProfileAssignmentStatus)" -PercentComplete $percent
                $percent += 25 / $iter
                if ($percent -ge 100) {
                    $percent = 99
                }
                $iter++
                Start-Sleep 30
            }
            else {
                $processed = $true
            }
        } while (!$processed)
        $assignDuration = (Get-Date) - $assignStart
        $assignSeconds = [Math]::Ceiling($assignDuration.TotalSeconds)
        Write-Host "Profile has been assigned to the device. Elapsed time to complete assignment: $assignSeconds seconds"

}

function Get-Choice {
    param (
        [Parameter(Mandatory=$true, HelpMessage="Input data")]
        [Array] $In,
        [Parameter(Mandatory=$false, HelpMessage="Relevant parameters")]
        [String[]] $Params,
        [Parameter(Mandatory=$false, HelpMessage="Allow selection of multiple values")]
        [switch] $MultipleChoice = $false,
        [Parameter(Mandatory=$false, HelpMessage="Color the output for better visualization")]
        [bool] $Color = $true,
        [Parameter(Mandatory=$false, HelpMessage="Page size")]
        [int] $PageSize = 8
    )
    Process {
        $currentPage = 0
        do {
            for ($i = $currentPage * $pageSize; $i -lt ($currentPage + 1) * $pageSize; $i++) {
                if ($i -ge $In.Length) {
                    break;
                }
                $outStr = $i.ToString() + ". "
                if ($PSBoundParameters.ContainsKey("Params")) {
                    for ($j = 0; $j -lt $Params.Length; $j++) {
                        $outStr += $In[$i].$($Params[$j]) + " | "
                    }
                }
                else {
                    $outStr += $In[$i]
                }
                if ($Color) {
                    switch ($i % 2) {
                        0 { $colorStr = "Yellow" }
                        1 { $colorStr = "Cyan" }
                    }
                }
                else { $colorStr = "White" }
                Write-Host -ForegroundColor $colorStr $outStr 
            }

            $selectStr = "Pick the relevant option. "
            if ($MultipleChoice) {
                $selectStr += "Select several options by separating via commas. "
            }
            if ($pageSize -le $In.Length) {
                if (($currentPage + 1) * $pageSize -lt $In.Length) {
                    $selectStr += "(N) Next Page "
                }
                if ($currentPage -ne 0) {
                    $selectStr += "(P) Previous Page "
                }
            }

            $pick = Read-Host $selectStr

            switch ($pick) {
                {$_.ToLower() -eq "n"} { 
                    if ((($currentPage + 1) * $pageSize) -gt $In.Length) {
                        Write-Host "Cannot go further: this is the last page."
                        continue
                    }
                    else {
                        $currentPage++
                    }
                }
                {$_.ToLower() -eq "p"} { 
                    if ($currentPage -eq 0) {
                        Write-Host "Cannot go back any further: this is the first page."
                        continue
                    }
                    else {
                        $currentPage--
                    }
                }
                default { 
                    try {
                        if ($MultipleChoice) {
                            $pickMultiple = $pick.split(",")
                            $choices = foreach ($num in $pickMultiple) { ([int]::parse($num)) }
                        }
                        else {
                            $choices = @([int]::parse($pick))
                        }
                    }
                    catch {
                        Write-Host "Invalid input."
                        continue
                    }
            
                    $valid = $true
            
                    foreach ($option in $choices) {
                        if (!(($option -ge 0) -and ($option -lt $In.Length))) {
                            $valid = $false
                            Write-Host "Invalid option: $($option)"
                        }
                    }
            
                    if (!$valid) {
                        Write-Host "Invalid input."
                        continue
                    }
            
                    do {
                        foreach ($option in $choices) {
                            $confStr = ""
                            if ($PSBoundParameters.ContainsKey("Params")) {
                                for ($i = 0; $i -lt $Params.Length; $i++){
                                    $confStr += $In[$option].$($Params[$i]) + " | "
                                }
                            }
                            else {
                                $confStr += $In[$option]
                            }
                            Write-Host $confStr
                        }
                        $Confirmation = Read-Host "Confirm? (y/N)"
                        if (($null -eq $Confirmation) -or ($Confirmation.ToLower() -eq "n")) {
                            break
                        }
                    } while ($Confirmation.ToLower() -ne "y")
            
                    if ($Confirmation.ToLower() -eq "y") {
                        $choice = foreach ($option in $choices) { $In[$option] }
                    }
                }
            }

        } while ($null -eq $choice)

        return $choice
    }
}

function Find-Tenant {
    param (
        [Parameter(Mandatory=$true)]
        [String] $ID
    )
    Process {
        try {
            $tenantId = Get-TenantID $ID
            foreach ($tenant in $customers) {
                if ($tenant.CustomerId -eq $tenantId) {
                    $desiredTenant = $tenant
                    break
                }
            }
            
            if (!$desiredTenant) {
                Write-Error -Message "Specified tenant does not have a delegated access relationship in this partner tenant."
            }
        }
        catch {
            Write-Host "The tenant ID/domain specified was invalid. "
            Write-Error -Message $_ -Category InvalidArgument
        }

        return $desiredTenant
    }
}

function Invoke-Authentication {
    param(
        [Hashtable]$Settings,
        [String[]]$RequiredGraphPermissions
    )

    function Invoke-PartnerRestMethod {
        param(
            [String]$Method,
            [SecureString]$Token,
            [String]$Uri
        )

        $PARTNER_BASE_URL = "https://api.partnercenter.microsoft.com/v1"

        $req = Invoke-RestMethod -Method $Method -Uri "$($PARTNER_BASE_URL)$($Uri)" -Authentication Bearer -Token $Token

        return $req

    }

    $AzParams = @{}

    if ($settings.DEVICE_CODE_AUTH) {
        $AzParams.UseDeviceAuthentication = $true
    }

    # Authenticate to Azure Portal
    $AzConfig = Get-AzConfig
    Update-AzConfig -LoginExperienceV2 Off
    Write-Host "Connecting to Azure - this will determine if your tenant is in the Microsoft Partner Network (MPN)"
    Disconnect-AzAccount -ErrorAction SilentlyContinue | Out-Null
    Connect-AzAccount @AzParams | Out-Null

    # Get a Partner Center token
    $PartnerToken = Get-AzAccessToken -ResourceUrl "https://api.partnercenter.microsoft.com" 

    # Verify Partner Status
    if (!$(Get-PartnerRestMethod -Method "GET" -Uri "/profiles/mpn" -Token $partnerToken.Token).mpnId) {
        Write-Host "This does not appear to be a Microsoft Partner Network account." -ForegroundColor Red
        Write-Host "The device will be added directly to the tenant associated with the signed-in account. Ctrl+C to cancel/terminate." -ForegroundColor Red
        Start-Sleep 5
        $isPartner = $false
    }

    # Get target tenant ID for enrollment
    if ($isPartner) {
        # Get a list of all customers
        $customers = $(Invoke-PartnerRestMethod -Method "GET" -Uri "/customers" -Token $partnerToken.Token).items.CompanyProfiles

        # Append partner tenant to list
        $PartnerTenant = Get-AzTenant | Where-Object Id -eq $(Get-AzContext).Tenant
        $customers += [PSCustomObject]@{
            tenantId = $partnerTenant.Id
            companyName = $partnerTenant.Name
            domain = $partnerTenant.DefaultDomain
        }

        if (!$($null -eq$settings.DEFAULT_TENANT)) {
            $TargetTenant = $($customers | Where-Object tenantId -eq $(Get-TenantID $settings.DEFAULT_TENANT)).tenantId
            if ($TargetTenant) { }
            else               { Write-Error "Tenant specified is not found in the list of customers from Partner Center." -ErrorAction Stop}
        }
        else {
            $TargetTenant = $(Get-Choice -In $customers -Params @("tenantId", "domain","companyName") -PageSize 16).tenantId
        }
    }
    else {
        $TargetTenant = $(Get-AzContext).Tenant
    }

    # Connect to Microsoft Graph in target tenant
    Write-Host "Connecting to target tenant via Microsoft Graph..."
    Disconnect-MgGraph -ErrorAction SilentlyContinue | Out-Null
    Connect-MgGraph -AccessToken $(Get-AzAccessToken -ResourceTypeName MSGraph -TenantId $TargetTenant).Token

    # Verify presence of application in tenant
    Write-Host "Getting service principal of Azure CLI..."
    $EntApp = Get-MgServicePrincipal -All | Where-Object Id -eq $AZURE_CLI_APP_ID

    # Verify admin consent of application
    Write-Host "Verifying that Azure CLI has the correct scopes..."
    $permissions = $(Get-MgOauth2PermissionGrant -Filter "clientId eq $($EntApp.Id)" -All) `
        | Where-Object ResourceId -eq "00000003-0000-0000-c000-000000000000"
        | Where-Object ConsentType -eq AllPrincipals
    if (!($RequiredPermissions -in $permissions.Scope)) {
        Write-Host -ForegroundColor Red "Application consents not found."
        Write-Host -ForgroundColor Yellow "Attempting to consent to application..."
        Write-Host -ForegroundColor Cyan "NOTE: This requires Cloud Application Administrator, Application Administrator, or Global Administrator."
        try {
            foreach ($perm in $RequiredPermissions) {
                $params = @{
                    clientId = $EntApp.Id
                    consentType = "AllPrincipals"
                    resourceId = "00000003-0000-0000-c000-000000000000"
                    scope = $perm
                }
                New-MgOauth2PermissionGrant -BodyParameter $params
            }
        }
        catch {
            Write-Error "Unable to add consents to Azure CLI in target tenant. InnerError: $($_.Exception.Message)" -ErrorAction Stop
        }

        # Reauthenticate to attain permissions
        Disconnect-MgGraph -ErrorAction SilentlyContinue | Out-Null
        Connect-MgGraph -AccessToken $(Get-AzAccessToken -ResourceTypeName MSGraph -TenantId $TargetTenant).Token

    }

    Write-Host -ForegroundColor Green "Checks complete - authenticated to target tenant."
    Set-AzConfig -LoginExperienceV2 $($AzConfig | Where-Object Key -eq LoginExperienceV2).Value
    
}

function Import-Autopilot {
    param (
        [Parameter(Mandatory=$false)]
        [String] $SettingsPath,
        [Parameter(Mandatory=$false)]
        [String] $GroupTag,
        [Parameter(Mandatory=$false)]
        [String] $ClientTenant
    )
    
    # Get settings configuration from settings.json
    if ($SettingsPath) {
        try   { $settings = Get-ContentPath -Path $SettingsPath }
        catch { Write-Error -Message "Specified settings file was not found." -ErrorAction Stop }
    }
    else {
        try     { $settings = Get-ContentPath -Path "./settings.json" }
        catch   { Write-Verbose "No settings.json found in current directory. Moving with default settings." }
    }
    
    $settings = $settings -replace '(?m)(?<=^([^"]|"[^"]*")*)//.*' -replace '(?ms)/\*.*?\*/'
    $settings = $settings | ConvertFrom-Json


    if (!$settings) {
        $settings = @{
                DEVICE_CODE_AUTH = $true
                DEFAULT_GROUP_TAG = ""
                FORCE_DEF_GROUP_TAG = $false
                DEFAULT_TENANT = ""
                FORCE_DEF_TENANT = $false
                ENABLE_ASSIGN_USER = $false
                SOAK_TIME = 300
            }
    }

    # Authenticate to Microsoft Graph using the application ID and previously instantiated credentials.
    Invoke-Authentication -Settings $settings -RequiredGraphPermissions @("DeviceManagementServiceConfig.ReadWrite.All")

    # Attain group tag
    if ($PSBoundParameters.ContainsKey("GroupTag")) {
        Write-Host "Using group tag $($GroupTag) as specified in arguments."
    }
    elseif ($settings.FORCE_DEF_GROUP_TAG) {
        $GroupTag = $settings.DEFAULT_GROUP_TAG
        Write-Host "Using group tag '$($settings.DEFAULT_GROUP_TAG) as specified in settings.json"
    }
    else {
        do {
            $GroupTag = Read-Host -Prompt "Enter the group tag of the device (Default: '$($settings.DEFAULT_GROUP_TAG)')"
            if (!$GroupTag) {
                $GroupTag = $DEFAULT_GROUP_TAG
                break
            }
            else {
                do {
                    $Confirmation = Read-Host -Prompt "Group Tag: '$($GroupTag)' | Correct? (y/N)"
                } while (!(($Confirmation.ToLower() -eq "y" ) -or ($Confirmation.ToLower() -eq "n") -or (!$Confirmation)))
            }
        } while ($Confirmation.ToLower() -ne "y")
    }

    # Attain user information if ENABLE_ASSIGN_USER is true.
    if ($settings.ENABLE_ASSIGN_USER) {
        do {
            $AssignedUser = Read-Host -Prompt "Enter the UPN of the assigned user of the device (Press enter if none)"
            if (!$AssignedUser) {
                break
            }
            else {
                do {
                    $Confirmation = Read-Host -Prompt "Assigned User: '$($AssignedUser)' | Correct? (y/N)"
                } while (!(($Confirmation.ToLower() -eq "y" ) -or ($Confirmation.ToLower() -eq "n") -or (!$Confirmation)))
            }
        } while ($Confirmation.ToLower() -ne "y")
    }
    else {
        Write-Host "User assignment disabled - skipping user assignment"
    }

    Write-Host "Acquiring hardware hash information..."
    $device = Get-HWID
    $importIdentity = Add-AutopilotImportedDevice -serialNumber $device."Device Serial Number" -hardwareIdentifier $device."Hardware Hash" -groupTag $GroupTag -assignedUser $AssignedUser
    Wait-UntilComplete -Device $importIdentity

    # Remove tracks. This may not work properly (it is what it is).
    Write-Host "Disconnecting from Microsoft services..."
    Disconnect-MgGraph
    Disconnect-PartnerCenter

    Write-Host "Removing all installed modules..."
    Write-Progress -Activity "Removing installed modules" -Status "Removing PartnerCenter" -PercentComplete 0
    Remove-Module -Name PartnerCenter -Force 
    Write-Progress -Activity "Removing installed modules" -Status "Removing WindowsAutoPilotIntune" -PercentComplete 25
    Remove-Module -Name WindowsAutoPilotIntune -Force

    Write-Progress -Activity "Removing installed modules" -Status "Uninstalling PartnerCenter" -PercentComplete 50
    Uninstall-Module -Name PartnerCenter -Force
    Write-Progress -Activity "Removing installed modules" -Status "Uninstalling WindowsAutoPilotIntune" -PercentComplete 75
    Uninstall-Module -Name WindowsAutoPilotIntune -Force

    # Wait for soak.
    Write-Host "Enrollment complete. Timer to allow Intune to soak begins now."
    if (!$settings.SOAK_TIME){ $soakSecs = 300 }
    else { $soakSecs = $settings.SOAK_TIME }

    for ($i = 0; $i -le $soakSecs; $i++) {
        Write-Progress -Activity "Awaiting Soak" -SecondsRemaining $($soakSecs - $i) -PercentComplete $(($i / $soakSecs) * 100)
        Start-Sleep 1
    }

    exit 0

}