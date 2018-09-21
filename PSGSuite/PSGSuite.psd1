#
# Module manifest for module 'PSGSuite'
#
# Generated by: Nate Ferrell
#
# Generated on: 2017-12-31
#

@{

    # Script module or binary module file associated with this manifest.
    RootModule            = 'PSGSuite.psm1'

    # Version number of this module.
    ModuleVersion         = '2.14.0'

    # ID used to uniquely identify this module
    GUID                  = '9d751152-e83e-40bb-a6db-4c329092aaec'

    # Author of this module
    Author                = 'Nate Ferrell'

    # Company or vendor of this module
    CompanyName           = 'SCRT HQ'

    # Copyright statement for this module
    Copyright             = '(c) SCRT HQ 2016-2018. All rights reserved.'

    # Description of the functionality provided by this module
    Description           = '## Summary

Powershell module wrapping Googles .NET SDKs in handy functions. Authentication is supported both with service account P12 keys as well as client_secrets.json to go through OAuth2.


## Prerequisites

In order to use this module, youll need to have the following:

* Powershell 4.0 or higher
* API Access Enabled in the Admin Console under Security
* Service Account key created and downloaded as a P12 key file
* API Client access allowed for the Service Account that will be used towards the API scopes that you intend to utilize
* Domain-Wide Delegation enabled for the service account


## Breaking Changes in 2.0.0

### Functions Removed

Please note that not all functions were ported to PSGSuite 2.0.0 due to restrictions within the .NET SDK and deprecated API calls. Here is the list of functions no longer existing in PSGSuite as of 2.0.0:
* Get-GSToken: no need for this as the keys are being consumed by Googles Auth SDK directly now, which makes Access/Refresh tokens non-existent for P12 Key service accounts and token management is handled automatically
* Revoke-GSToken: same here, no longer needed due to auth service changes
* Start-PSGSuiteConfigWizard: no longer supported as WPF is not compatible outside of Windows

All other functions are either intact or have an alias included to support backwards compatibility in scripts.

## Tips & Tricks

* All functions support pre-acquired Access Tokens (using the AccessToken parameter).
	* This is useful if you have a lot of recurring commands that leverage the same admin and scope(s) so you do not overrun the user API call quota, i.e. pulling info for a large set of emails in a user''s inbox.
* If the access token is not pre-acquired, then the P12KeyPath, AppEmail, AdminEmail, CustomerID, and Domain parameters will default to reading from the PSGSuite config file (these can also be named in each function call, if preferred).
* If you plan on using this module on multiple computers or between multiple accounts on the same computer, you will need a new PSGoogle config created for each computer / user account pair.
'

    # Minimum version of the Windows PowerShell engine required by this module
    PowerShellVersion     = '4.0'

    # Name of the Windows PowerShell host required by this module
    # PowerShellHostName = ''

    # Minimum version of the Windows PowerShell host required by this module
    # PowerShellHostVersion = ''

    # Minimum version of Microsoft .NET Framework required by this module
    # DotNetFrameworkVersion = ''

    # Minimum version of the common language runtime (CLR) required by this module
    # CLRVersion = ''

    # Processor architecture (None, X86, Amd64) required by this module
    ProcessorArchitecture = 'None'

    # Modules that must be imported into the global environment prior to importing this module
    RequiredModules       = @(@{ModuleName = "Configuration";ModuleVersion = "1.2.0"})

    # Assemblies that must be loaded prior to importing this module
    RequiredAssemblies    = @()

    # Script files (.ps1) that are run in the caller's environment prior to importing this module.
    ScriptsToProcess      = @()

    # Type files (.ps1xml) to be loaded when importing this module
    TypesToProcess        = @()

    # Format files (.ps1xml) to be loaded when importing this module
    FormatsToProcess      = @()

    # Modules to import as nested modules of the module specified in RootModule/ModuleToProcess
    # NestedModules = @()

    # Functions to export from this module
    FunctionsToExport     = '*'

    # Cmdlets to export from this module
    CmdletsToExport       = @()

    # Variables to export from this module
    VariablesToExport     = @()

    # Aliases to export from this module
    AliasesToExport       = '*'

    # DSC resources to export from this module
    # DscResourcesToExport = @()

    # List of all modules packaged with this module
    # ModuleList = @()

    # List of all files packaged with this module
    FileList              = @()

    # Private data to pass to the module specified in RootModule/ModuleToProcess. This may also contain a PSData hashtable with additional module metadata used by PowerShell.
    PrivateData           = @{

        PSData = @{

            # Tags applied to this module. These help with module discovery in online galleries.
            Tags       = 'Google','GSuite','Apps','G','Suite','REST','API','Admin','PSModule','Directory','User','Goo.gl','PSEdition_Core'

            # A URL to the license for this module.
            # LicenseUri = ''

            # A URL to the main website for this project.
            ProjectUri = 'https://github.com/scrthq/PSGSuite'

            # A URL to an icon representing this module.
            IconUri    = 'http://centerlyne.com/wp-content/uploads/2016/10/Google_-G-_Logo.svg_.png'

            # ReleaseNotes of this module
            # ReleaseNotes = ''

            # External dependent modules of this module
            # ExternalModuleDependencies = ''

        } # End of PSData hashtable

    } # End of PrivateData hashtable

    # HelpInfo URI of this module
    HelpInfoURI           = 'https://github.com/scrthq/PSGSuite/wiki'

    # Default prefix for commands exported from this module. Override the default prefix using Import-Module -Prefix.
    # DefaultCommandPrefix = ''

}
