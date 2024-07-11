@{
    RootModule = 'AutopilotPartner.psm1'
    ModuleVersion = '1.0.1'
    GUID = 'faa0d447-edd6-4d68-b449-3fc437fb21f9'
    Author = 'Onslivion'
    Description = 'A module designed to import devices to Intune / Autopilot (directly) using Microsoft Partner delegation.'
    FunctionsToExport = @('Import-Autopilot')
    RequiredModules = @(
        'WindowsAutoPilotIntune',
        'PartnerCenter'
    )

    PrivateData = @{
        PSData = @{
            ProjectUri = "https://github.com/Onslivion/AutopilotPartner"
            Tags = @('Intune','Autopilot','Windows','PSEdition_Desktop','CSP','Partner')
            ReleaseNotes = 
            @'
            Version 1.0.1: Allows settings.json to contain non-standard comments (double slash comments)
            Version 1.0.0: Initial release
'@
        }
    }
}