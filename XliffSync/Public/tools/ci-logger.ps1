function Is-GitHubActions {
    return $env:GITHUB_ACTIONS -eq "true"
}

function Is-AzureDevOps {
    return [bool]$env:AGENT_NAME
}

function Write-CIMessage {
    param (
        [Parameter(Mandatory)]
        [ValidateSet("group", "endgroup", "section", "error", "warning", "info")]
        [string] $Type,

        [Parameter(Mandatory = $false)]
        [string] $Message
    )

    if (Is-GitHubActions) {
        switch ($Type) {
            "group" { Write-Host "::group::$Message" }
            "endgroup" { Write-Host "::endgroup::" }
            "section" { Write-Host "::group::$Message" }  # GitHub kennt keinen "section", also wie group
            "error" { Write-Host "::error::$Message" }
            "warning" { Write-Host "::warning::$Message" }
            default { Write-Host "$Message" }
        }
    } elseif (Is-AzureDevOps) {
        switch ($Type) {
            "group" { Write-Host "##[group]$Message" }
            "endgroup" { Write-Host "##[endgroup]" }
            "section" { Write-Host "##[section]$Message" }
            "error" { Write-Host "##vso[task.logissue type=error]$Message" }
            "warning" { Write-Host "##vso[task.logissue type=warning]$Message" }
            default { Write-Host "$Message" }
        }
    } else {
        # Fallback für lokale oder nicht unterstützte Umgebungen
        switch ($Type) {
            "group" { Write-Host "[GROUP] $Message" }
            "endgroup" { Write-Host "[/GROUP]" }
            "section" { Write-Host "[SECTION] $Message" }
            "error" { Write-Host -ForegroundColor Red "[ERROR] $Message" }
            "warning" { Write-Host -ForegroundColor Yellow "[WARNING] $Message" }
            default { Write-Host "$Message" }
        }
    }
}

function Write-CIProgress {
    param (
        [Parameter(Mandatory = $true)]
        [string] $Message,

        [int] $PercentComplete = 0,

        [ValidateSet("info", "warning", "error")]
        [string] $ErrorSeverity
    )

    if (Is-GitHubActions) {
        Write-CIMessage -Type info -Message "[Progress $PercentComplete%] $Message"
    } elseif ($ErrorSeverity -ne 'info') {
        Write-Host "##vso[task.setprogress value=$PercentComplete;]$Message"
    } else {
        Write-Progress -Activity $Message -PercentComplete $PercentComplete
    }
}

