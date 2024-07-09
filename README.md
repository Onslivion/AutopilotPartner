# AutopilotPartner
This module is intended for deploying devices directly into the Windows Autopilot mechanism in a Partner client's tenant.
This is not for deploying through Partner Center APIs.
This will enhance technicians efficiency, as it only requires the device to be connected to the Internet.

## Pre-requisites
- An application ID in the Partner tenant that has the user_impersonation permission for Microsoft Partner Center.
- Each technician involved should be in the appropriate Entra ID group that grants Partner Center access (this is generally called AdminAgents).
- The GDAP relationship for the intended client tenant must have Intune Administrator.

## Usage

```
AutopilotPartner
```

The module requires a settings.json file.
By default, AutopilotPartner will attempt to locate the file in the current directory.
Please read through the settings.json file carefully to better customize your experience.

You can manually specify a path:
```
AutopilotPartner -SettingsPath C:\Windows\Temp\settings.json
```

Additionally, a group tag and/or tenant can be specified directly:
```
AutopilotPartner [-GroupTag <grouptag>] [-ClientTenant <tenant ID or domain>]
```

## Credits and Inspiration

- [WindowsAutoPilotIntune](https://www.powershellgallery.com/packages/WindowsAutoPilotIntune/5.6)
- [GetWindowsAutoPilotInfo.ps1](https://www.powershellgallery.com/packages/Get-WindowsAutoPilotInfo/3.9/Content/Get-WindowsAutopilotInfo.ps1)
- [Get-TenantID](https://teams.se/powershell-script-find-a-microsoft-365-tenantid/)