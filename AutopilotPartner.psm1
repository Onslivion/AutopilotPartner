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
            Write-Error -Message $("The device import failed. Error: " + $_) -ErrorAction Stop
        }

        Write-Host "Device imported successfully. Elapsed time to complete import: $importSeconds seconds"
        
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

function Authenticate {
    # Attempt to authenticate to Partner Center using the provided Partner App ID
    Write-Host "Initiating interactive sign-in. You will be signing in to Microsoft Partner Center, under the application $($settings.PARTNER_APP_ID)."
    try {
        if ($settings.DEVICE_CODE_AUTH) { $partnerToken = New-PartnerAccessToken -ApplicationId $settings.PARTNER_APP_ID -Scopes 'https://api.partnercenter.microsoft.com/user_impersonation' -UseDeviceAuthentication }
        else { $partnerToken = New-PartnerAccessToken -ApplicationId $settings.PARTNER_APP_ID -Scopes 'https://api.partnercenter.microsoft.com/user_impersonation' -UseAuthorizationCode }

        $partnerResult = Connect-PartnerCenter -AccessToken $partnerToken.AccessToken
    }
    catch {
        Write-Host "There was a problem signing in to Microsoft Partner Center. Verify your access and the status of Partner Center."
        Write-Error -Message $_
        exit 1
    }

    Write-Host "Connected to Partner Center via $((Get-PartnerOrganizationProfile).CompanyName) | $(Get-TenantID $partnerResult.Account.Tenant)."

    if (-not $(Get-PartnerMPNProfile).MpnId) {
        Write-Host "This does not appear to be a Microsoft Partner Network account." -ForegroundColor Red
        Write-Host "The device will be added directly to the tenant associated with the signed-in account. Ctrl+C to cancel/terminate." -ForegroundColor Red
        Start-Sleep 5
        $isPartner = $false
    }
    else {
        $isPartner = $true
    }

    if ($isPartner) {
        try {
            $customers = Get-PartnerCustomer
        }
        catch {
            Write-Host "There was a problem getting the list of customers from Microsoft Partner Center. Are you sure you're using your Partner credentials?"
            exit 1
        }

        # Include Partner tenant as an option.
        $self = New-Object -TypeName "Microsoft.Store.PartnerCenter.PowerShell.Models.Customers.PSCustomer"
        $self.Domain = $(Get-PartnerOrganizationProfile).Domain
        $self.CustomerId = $(Get-PartnerOrganizationProfile).Id
        $self.Name = $(Get-PartnerOrganizationProfile).CompanyName
        $customers += $self

        # Attain tenant via user input or from parameters.
        try {
            if ($PSBoundParameters.ContainsKey("ClientTenant")) {
                $customer = Find-Tenant $ClientTenant
                Write-Host "Using tenant $($customer.Name) | $($customer.CustomerId) specified in arguments."
            }
            elseif ($settings.FORCE_DEF_TENANT) {
                $customer = Find-Tenant $settings.DEFAULT_TENANT
                Write-Host "Using tenant $($customer.Name) | $($customer.CustomerId) specified in settings.json."
            }
            else {
                $customer = Get-Choice -In $customers -Params "Name","Domain","CustomerId" -PageSize 16
            }
        }
        catch {
            exit 1
        }

        # Initiation / Verification of the application registration in the tenant.
        # If an application registration does not exist, one is made using the least privileged permission set.
        Write-Host "Verifying $($settings.CLIENT_APP_NAME) | $($settings.CLIENT_APP_ID) is an app registration in the client tenant $($customer.Name) | $($customer.CustomerId)"
        $grant = New-Object -TypeName Microsoft.Store.PartnerCenter.Models.ApplicationConsents.ApplicationGrant
        $grant.EnterpriseApplicationId = '00000003-0000-0000-c000-000000000000'
        $grant.Scope = "DeviceManagementManagedDevices.ReadWrite.All,DeviceManagementServiceConfig.ReadWrite.All"
        try {
            New-PartnerCustomerApplicationConsent -ApplicationGrants @($grant) -CustomerId $customer.CustomerId -ApplicationId $settings.CLIENT_APP_ID -DisplayName $settings.CLIENT_APP_NAME
        }
        catch {
            if ($_.ErrorDetails.Message -eq ("Permission entry already exists.")) {
                Write-Host "The application registration already exists in the tenant. Proceeding." -ForegroundColor Yellow
            }
            else {
                Write-Host "An unknown error occurred verifying the app registration's presence in the tenant."
                exit 1
            }
        }

        # Authenticate to Microsoft Graph using the application ID and previously instantiated credentials.
        Write-Host "Authenticating to tenant $($customer.Name) | $($customer.CustomerId) through Microsoft Partner Network using the app registration $($settings.CLIENT_APP_NAME) | $($settings.CLIENT_APP_ID)"
        if ($settings.CLIENT_APP_ID -eq $settings.PARTNER_APP_ID) {
            $authReq = New-PartnerAccessToken -ApplicationId $settings.CLIENT_APP_ID -RefreshToken $partnerToken.RefreshToken -Scopes "https://graph.microsoft.com/.default" -Tenant $customer.CustomerId 
        }
        else {
            Write-Host "The application ID for the partner application is different than the client application. Re-authentication is required."
            if ($settings.DEVICE_CODE_AUTH) { $authReq = New-PartnerAccessToken -ApplicationId $settings.CLIENT_APP_ID -Scopes "https://graph.microsoft.com/.default" -Tenant $customer.CustomerId -UseDeviceAuthentication }
            else { $authReq = New-PartnerAccessToken -ApplicationId $settings.CLIENT_APP_ID -Scopes "https://graph.microsoft.com/.default" -Tenant $customer.CustomerId -UseAuthorizationCode }
        }
    
    }

    else {
        if ($settings.DEVICE_CODE_AUTH) { $authReq = New-PartnerAccessToken -ApplicationId $settings.CLIENT_APP_ID -Scopes "https://graph.microsoft.com/.default" -Tenant Get-TenantID $partnerResult.Account.Tenant -UseDeviceAuthentication }
        else { $authReq = New-PartnerAccessToken -ApplicationId $settings.CLIENT_APP_ID -Scopes "https://graph.microsoft.com/.default" -Tenant $partnerResult.Account.Tenant -UseAuthorizationCode }
    }

    $token = ConvertTo-SecureString -Force -AsPlainText $authReq.AccessToken

    return $token
}

function Import-Autopilot {
    param (
        [Parameter(Mandatory=$false)]
        [String] $SettingsPath = '.\settings.json',
        [Parameter(Mandatory=$false)]
        [String] $GroupTag,
        [Parameter(Mandatory=$false)]
        [String] $ClientTenant
    )
    
    # Get settings configuration from settings.json
    try {
        $settings = Get-Content -Path $SettingsPath
    }
    catch {
        Write-Error -Message "Error locating settings.json file. Please be sure that -SettingsPath is correct."
    }

    $settings = $settings -replace '(?m)(?<=^([^"]|"[^"]*")*)//.*' -replace '(?ms)/\*.*?\*/'
    $settings = $settings | ConvertFrom-Json

    # Check if required values are present in settings.json
    if (!$settings.PARTNER_APP_ID -or !$settings.CLIENT_APP_ID -or !$settings.CLIENT_APP_NAME) {
        Write-Error -Message "One of the following required values is missing from settings.json: PARNTER_APP_ID, CLIENT_APP_ID, CLIENT_APP_NAME"
        exit 1
    }

    # Attempt to authenticate to Partner Center using the provided Partner App ID
    Write-Host "Initiating interactive sign-in. You will be signing in to Microsoft Partner Center, under the application $($settings.PARTNER_APP_ID)."
    try {
        if ($settings.DEVICE_CODE_AUTH) { $partnerToken = New-PartnerAccessToken -ApplicationId $settings.PARTNER_APP_ID -Scopes 'https://api.partnercenter.microsoft.com/user_impersonation' -UseDeviceAuthentication }
        else { $partnerToken = New-PartnerAccessToken -ApplicationId $settings.PARTNER_APP_ID -Scopes 'https://api.partnercenter.microsoft.com/user_impersonation' -UseAuthorizationCode }

        $partnerResult = Connect-PartnerCenter -AccessToken $partnerToken.AccessToken
    }
    catch {
        Write-Host "There was a problem signing in to Microsoft Partner Center. Verify your access and the status of Partner Center."
        Write-Error -Message $_
        exit 1
    }

    Write-Host "Connected to Partner Center via $((Get-PartnerOrganizationProfile).CompanyName) | $(Get-TenantID $partnerResult.Account.Tenant)."

    try {
        $customers = Get-PartnerCustomer
    }
    catch {
        Write-Host "There was a problem getting the list of customers from Microsoft Partner Center. Are you sure you're using your Partner credentials?"
        exit 1
    }

    # Attain tenant via user input or from parameters.
    try {
        if ($PSBoundParameters.ContainsKey("ClientTenant")) {
            $customer = Find-Tenant $ClientTenant
            Write-Host "Using tenant $($customer.Name) | $($customer.CustomerId) specified in arguments."
        }
        elseif ($settings.FORCE_DEF_TENANT) {
            $customer = Find-Tenant $settings.DEFAULT_TENANT
            Write-Host "Using tenant $($customer.Name) | $($customer.CustomerId) specified in settings.json."
        }
        else {
            $customer = Get-Choice -In $customers -Params "Name","Domain","CustomerId" -PageSize 16
        }
    }
    catch {
        exit 1
    }

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

    # Initiation / Verification of the application registration in the tenant.
    # If an application registration does not exist, one is made using the least privileged permission set.
    Write-Host "Verifying $($settings.CLIENT_APP_NAME) | $($settings.CLIENT_APP_ID) is an app registration in the client tenant $($customer.Name) | $($customer.CustomerId)"
    $grant = New-Object -TypeName Microsoft.Store.PartnerCenter.Models.ApplicationConsents.ApplicationGrant
    $grant.EnterpriseApplicationId = '00000003-0000-0000-c000-000000000000'
    $grant.Scope = "DeviceManagementManagedDevices.ReadWrite.All,DeviceManagementServiceConfig.ReadWrite.All"
    try {
        New-PartnerCustomerApplicationConsent -ApplicationGrants @($grant) -CustomerId $customer.CustomerId -ApplicationId $settings.CLIENT_APP_ID -DisplayName $settings.CLIENT_APP_NAME
    }
    catch {
        if ($_.ErrorDetails.Message -eq ("Permission entry already exists.")) {
            Write-Host "The application registration already exists in the tenant. Proceeding." -ForegroundColor Yellow
        }
        else {
            Write-Host "An unknown error occurred verifying the app registration's presence in the tenant."
            exit 1
        }
    }

    # Authenticate to Microsoft Graph using the application ID and previously instantiated credentials.
    Write-Host "Authenticating to tenant $($customer.Name) | $($customer.CustomerId) through Microsoft Partner Network using the app registration $($settings.CLIENT_APP_NAME) | $($settings.CLIENT_APP_ID)"
    if ($settings.CLIENT_APP_ID -eq $settings.PARTNER_APP_ID) {
        $authReq = New-PartnerAccessToken -ApplicationId $settings.CLIENT_APP_ID -RefreshToken $partnerToken.RefreshToken -Scopes "https://graph.microsoft.com/.default" -Tenant $customer.CustomerId 
    }
    else {
        Write-Host "The application ID for the partner application is different than the client application. Re-authentication is required."
        if ($settings.DEVICE_CODE_AUTH) { $authReq = New-PartnerAccessToken -ApplicationId $settings.CLIENT_APP_ID -Scopes "https://graph.microsoft.com/.default" -Tenant $customer.CustomerId -UseDeviceAuthentication }
        else { $authReq = New-PartnerAccessToken -ApplicationId $settings.CLIENT_APP_ID -Scopes "https://graph.microsoft.com/.default" -Tenant $customer.CustomerId -UseAuthorizationCode }
    }
    $token = ConvertTo-SecureString -Force -AsPlainText $authReq.AccessToken

    # Initiate enrollment to Autopilot.
    Write-Host "Initiating Autopilot Enrollment..."
    Write-Host "Connecting to Microsoft Graph..."
    Connect-MgGraph -AccessToken $token
    if (!(("DeviceManagementManagedDevices.ReadWrite.All" -in $(Get-MgContext).scopes) -and ("DeviceManagementServiceConfig.ReadWrite.All" -in $(Get-MgContext).scopes))) {
        Write-Host "The application does not have the correct scopes. Please review the enterprise application $($settings.CLIENT_APP_NAME) | $($settings.CLIENT_APP_ID)"
        Write-Host "Scopes assigned: $($(Get-MgContext).scopes)"
        exit 1
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