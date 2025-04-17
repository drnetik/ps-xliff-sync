<#
 .Synopsis
  Synchronizes and checks translations for a workspace folder with Microsoft Dynamics 365 Business Central apps.
 .Description
  Iterates through the translation units of a base XLIFF file and synchronizes them with a target XLIFF file.
 .Parameter buildProjectFolder
  Specifies the path to the workspace folder containing the projects.
 .Parameter appFolders
  Specifies the names of the app folders in the workspace folder. If empty, all subfolders will be processed.
 .Parameter translationRules
  Specifies which technical validation rules should be used.
 .Parameter translationRulesEnableAll
  Specifies whether to apply all technical validation rules.
 .Parameter restrictErrorsToLanguages
  Specifies languages to restrict errors to. For languages not in the list only warnings will be raised. If empty, then the setting of AzureDevOps applies to all languages.
  .Parameter ErrorSeverity
  Specifies whether to generate Azure DevOps Pipeline or GitHub Acitons compatible output. This setting determines the severity of errors.
 .Parameter reportProgress
  Specifies whether the command should report progress.
 .Parameter printProblems
  Specifies whether the command should print all detected problems.
 .Parameter printUnitsWithErrors
  Specifies whether the command should print the units with errors.
 .Parameter useSelfClosingTags
  Specifies whether the updated target document should use self-closing XML tags.
 .Parameter processAppFoldersSortedByDependencies
  Specifies whether the command should process the app folders in order of app dependencies (uses module BcContainerHelper for sorting).
 .Parameter FormatTranslationUnit
  A scriptblock that determines how translation units are represented in warning/error messages.
  By default, the Xliff Generator note and XLIFF Sync note of the translation unit is returned.
 .Parameter syncAdditionalParameters
  Specifies additional parameters to pass as arguments to the Sync-XliffTranslations function that is invoked by this function.
 .Parameter testAdditionalParameters
 Specifies additional parameters to pass as arguments to the Test-XliffTranslations function that is invoked by this function.
#>

function Test-BcAppXliffTranslations {
    Param(
        [Parameter(Mandatory = $false)]
        [string] $buildProjectFolder = $ENV:BUILD_REPOSITORY_LOCALPATH,
        [Parameter(Mandatory = $false)]
        [string[]] $appFolders = @(),
        [Parameter(Mandatory = $false)]
        [ValidateSet("ConsecutiveSpacesConsistent", "ConsecutiveSpacesExist", "OptionMemberCount", "OptionLeadingSpaces", "Placeholders", "PlaceholdersDevNote")]
        [string[]] $translationRules = @("ConsecutiveSpacesConsistent", "OptionMemberCount", "OptionLeadingSpaces", "Placeholders"),
        [switch] $translationRulesEnableAll,
        [Parameter(Mandatory = $false)]
        [string[]] $restrictErrorsToLanguages = @(),
        [Parameter(Mandatory = $false)]
        [ValidateSet('info', 'error', 'warning')]
        [string] $ErrorSeverity = 'warning',
        [switch] $reportProgress,
        [switch] $printProblems,
        [switch] $printUnitsWithErrors,
        [switch] $useSelfClosingTags,
        [switch] $processAppFoldersSortedByDependencies,
        [ValidateNotNull()]
        [ScriptBlock]$FormatTranslationUnit = { param($TranslationUnit) "$($TranslationUnit.note | Where-Object from -EQ 'Xliff Generator' | Select-Object -ExpandProperty '#text'): $($TranslationUnit.note | Where-Object from -EQ 'XLIFF Sync' | Select-Object -ExpandProperty '#text')" },
        $syncAdditionalParameters = @{},
        $testAdditionalParameters = @{}
    )

    $hasLoggedErrors = $false

    if ((-not $appFolders) -or ($appFolders.Length -eq 0)) {
        $appFolders = (Get-ChildItem $buildProjectFolder -Directory).Name
        Write-Host "-appFolders not explicitly set, using subfolders of $($buildProjectFolder): $appFolders"
    }

    if ($processAppFoldersSortedByDependencies) {
        $appFolders = Sort-AppFoldersByDependencies -appFolders $appFolders -baseFolder $buildProjectFolder -WarningAction SilentlyContinue
    }

    $appFolders | ForEach-Object {
        Write-CIMessage -Type group -Message "Checking translations for `"$($_)`""
        $appProjectFolder = Join-Path $buildProjectFolder $_
        $appTranslationsFolder = Join-Path $appProjectFolder "Translations"
        Write-Host "Retrieving translation files from $appTranslationsFolder"
        $baseXliffFile = Get-ChildItem -Path $appTranslationsFolder -Filter '*.g.xlf'
        Write-Host "Base translation file $($baseXliffFile.FullName)"
        $targetXliffFiles = Get-ChildItem -Path $appTranslationsFolder -Filter '*.xlf' | Where-Object { -not $_.FullName.EndsWith('.g.xlf') }
        $allUnitsWithIssues = @()

        foreach ($targetXliffFile in $targetXliffFiles) {
            Write-CIMessage -Type section -Message "Processing `"$($targetXliffFile.BaseName)`""
            $unitsWithIssues = @()
            [string]$ErrorSeverityForFile = $ErrorSeverity
            if (($ErrorSeverity -eq 'error') -and ($restrictErrorsToLanguages.Length -gt 0)) {
                if ($null -eq ($restrictErrorsToLanguages | Where-Object { $targetXliffFile.Name -match $_ })) {
                    $ErrorSeverityForFile = 'warning'
                }
                Write-Host "Translation error severity is '$ErrorSeverityForFile' for file $($targetXliffFile.FullName)"
            }

            Write-Host "Syncing to file $($targetXliffFile.FullName)"
            $unitsWithIssues += Sync-XliffTranslations -sourcePath $baseXliffFile.FullName -targetPath $targetXliffFile.FullName -ErrorSeverity $ErrorSeverityForFile -reportProgress:$reportProgress -printProblems:$printProblems -useSelfClosingTags:$useSelfClosingTags -FormatTranslationUnit $FormatTranslationUnit @syncAdditionalParameters
            Write-Host "Checking translations in file $($targetXliffFile.FullName)"
            $unitsWithIssues += Test-XliffTranslations -targetPath $targetXliffFile.FullName -checkForMissing -checkForProblems -translationRules $translationRules -translationRulesEnableAll:$translationRulesEnableAll -ErrorSeverity $ErrorSeverityForFile -reportProgress:$reportProgress -FormatTranslationUnit $FormatTranslationUnit -printProblems:$printProblems @testAdditionalParameters

            $fileIssueCount = $unitsWithIssues.Count
            if ($fileIssueCount -gt 0) {
                Write-Host "$fileIssueCount issues detected in file $($targetXliffFile.FullName)."
                if ($printUnitsWithErrors) {
                    Write-Host "Units with issues:"
                    Write-Host $unitsWithIssues
                }

                if ($ErrorSeverityForFile -eq 'error') {
                    $allUnitsWithIssues += $unitsWithIssues
                    $hasLoggedErrors = $true
                }
            }
        }

        if (@("error", "warning").Contains($ErrorSeverity) -and ($targetXliffFiles.Count -eq 0)) {
            Write-CIMessage -Type $ErrorSeverity -Message "There are no target translation files for $($baseXliffFile.Name)"
            if ($ErrorSeverity -eq 'error') {
                $hasLoggedErrors = $true
            }
        }
        Write-CIMessage -Type endgroup

        $issueCount = $allUnitsWithIssues.Count
        if (($ErrorSeverity -eq 'error') -and ($issueCount -gt 0)) {
            Write-CIMessage -Type error -Message "$issueCount issues detected in translation files!"
            $hasLoggedErrors = $true
        }
    }

    if ($hasLoggedErrors) {
        Write-CIMessage -Type error -Message "Failing pipeline due to translation issues."
        if (-not (Is-GitHubActions)) {
            Write-Host "##vso[task.complete result=Failed;]Make step fail"
            exit 0
        } else {
            exit 1
        }
    }
}

Set-Alias -Name Check-BcAppXliffTranslations -Value Test-BcAppXliffTranslations
Export-ModuleMember -Function Test-BcAppXliffTranslations -Alias Check-BcAppXliffTranslations
