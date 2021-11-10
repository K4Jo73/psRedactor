[cmdletBinding()]
param(
    [parameter(valueFromPipeline = $false, ValueFromPipelineByPropertyName = $true)]
    [bool] $ProcessFolder = $true,
    [parameter(valueFromPipeline = $false, ValueFromPipelineByPropertyName = $true)]
    [bool] $OutputDetail = $false,
    [parameter(valueFromPipeline = $false, ValueFromPipelineByPropertyName = $true)]
    [string] $OutputFolder = ".\",
    [parameter(valueFromPipeline = $false, ValueFromPipelineByPropertyName = $true)]
    [string[]] $ValidFileTypes = @('*.txt', '*.csv', '*.log'),
    [parameter(valueFromPipeline = $false, ValueFromPipelineByPropertyName = $true)]
    [string] $SearchPatternFileName = "",
    [parameter(valueFromPipeline = $false, ValueFromPipelineByPropertyName = $true)]
    [string[]] $SearchPatterns = @('[A-Za-z0-9]{5,}', '[A-Za-z]{10,}'),
    [parameter(valueFromPipeline = $false, ValueFromPipelineByPropertyName = $true)]
    [string[]] $SearchPatternsDesc = @("Pattern1", "Pattern2")
)


# * VARIABLES
$global:NewLine = [Environment]::NewLine
# $global:CurrentDomain = ([System.Net.Dns]::GetHostByName((HostName)).HostName).Replace("$(HostName)","")
# Write-Host $global:CurrentDomain


# * FUNCTIONS

function Get-Filename($InitialDirectory = "") {
    [System.Reflection.Assembly]::LoadWithPartialName("System.Windows.Forms")

    $OpenFileDialog = New-Object System.Windows.Forms.OpenFileDialog
    $OpenFileDialog.InitialDirectory = $InitialDirectory
    $OpenFileDialog.filter = "All files (*.*)| *.*"
    $OpenFileDialog.ShowDialog() | Out-Null

    return $OpenFileDialog.filename
}

function Get-Folder() {
    [CmdletBinding()] 
    PARAM (
        [string]$InitialDirectory = "",
        [string]$PromptMessage = "Select a folder"
    )

    [System.Reflection.Assembly]::LoadWithPartialName("System.Windows.Forms") | Out-Null
    
    $OpenFolderDialog = New-Object System.Windows.Forms.FolderBrowserDialog
    $OpenFolderDialog.Description = $PromptMessage
    $OpenFolderDialog.RootFolder = "MyComputer"
    $OpenFolderDialog.SelectedPath = $InitialDirectory 

    if ($OpenFolderDialog.ShowDialog() -eq "OK") {
        $folder = $OpenFolderDialog.SelectedPath
    }
    return $folder

}
        
function Get-Configuration() { 
    [cmdletBinding()]
    PARAM (
        [bool]$DoFolder = $true 
    )

    $Results = New-Object -TypeName psobject
    $Results | Add-Member -Member NoteProperty -Name "SearchType" -Value "Not Set"
    $Results | Add-Member -Member NoteProperty -Name "SearchPath" -Value "Not Set"
    $Results | Add-Member -Member NoteProperty -Name "FileTypes" -Value $ValidFileTypes
    $Results | Add-Member -Member NoteProperty -Name "SearchPatternRegEx" -Value $SearchPatterns
    $Results | Add-Member -Member NoteProperty -Name "SearchPatternDesc" -Value $SearchPatternsDesc

    $CfgFile = ".\FileTypes.cfg"
    If ( Test-Path -Path $CfgFile ) {
        Write-Host "Found FileTypes Config File"
        Write-Host "Overriding parameter file type list of $($global:NewLine)$ValidFileTypes"
        $Results.FileTypes = Get-Content $CfgFile
    }

    If ($SearchPatternFileName -eq "") { $SearchPatternFileName = "SearchPatterns" }
    $CfgFile = ".\$($SearchPatternFileName).cfg"
    If ( Test-Path -Path $CfgFile) {
        Write-Host "Found Search Patterns Config File"
        Write-Host "Overriding parameter search pattern list of $($global:NewLine)"
        $SearchPatterns | Out-Host
        Write-Host "SearchPatternFileName: $($CfgFile)"
        $SrchPats = Import-Csv -Path $CfgFile -Delimiter "~"
        $SrchPats = $SrchPats | Where-Object { $_.Enabled -eq "1" } | Select-Object Desc, pattern
        $SrchPats | Format-Table | Out-Host 
        $Results.SearchPatternRegEx = $SrchPats.Pattern
        $Results.SearchPatternDesc = $SrchPats.Desc
    }

    If ($DoFolder) {
        Write-Host "Prompt for folder...."
        $Results.SearchType = "Folder"
        $Results.SearchPath = Get-Folder -PromptMessage "Select the folder to process files"
    }
    else {
        Write-Host "Prompt for file"
        $Results.SearchType = "File"
        $Results.SearchPath = Get-File
    }

    If (!$Results.SearchPath) {
        $Results.SearchType = "Unknown"
    }

    return $Results

}

function Assert-FolderPath() {
    [CmdletBinding()]
    PARAM(
        [string]$FolderPath = ".\"
    )

    If ( Test-Path -Path $FolderPath ) {
        Write-Debug "Path Already Exists [$($FolderPath)]"
        return $FolderPath
    }
    else {
        Write-Debug "Path Does NOT Exists, creating [$($FolderPath)]"
        $NewFolder = New-Item -Path $FolderPath -ItemType "directory"
        If ( Test-Path -Path $NewFolder ) { return $NewFolder } else { return "ERROR CREATING FOLDER [$($FolderPath)]" }
    }

}

function Assert-FolderStructure() {
    [CmdletBinding()]
    PARAM (
        [string]$OutFolder = ".\"
    )

    $Results = New-Object -TypeName PSObject 
    $Results | Add-Member -MemberType NoteProperty -Name "RootFolder" -Value "Not Set"
    $Results | Add-Member -MemberType NoteProperty -Name "ResultsFolder" -Value "Not Set"
    $Results | Add-Member -MemberType NoteProperty -Name "RedactedFolder" -Value "Not Set"
    $Results | Add-Member -MemberType NoteProperty -Name "TranslatedFolder" -Value "Not Set"
    $Results | Add-Member -MemberType NoteProperty -Name "OriginalFolder" -Value "Not Set"

    # Ensure Root Folder Exists
    $Results.RootFolder = Assert-FolderPath "$($OutFolder)\RedactionOutput"
    # Ensure a Fresh Folder For This Execution Exists
    $ResultsFolderName = "Results_" + (Get-Date).ToString("yyyyMMdd_HHmmss")
    $Results.ResultsFolder = Assert-FolderPath "$($Results.RootFolder)\$($ResultsFolderName)"

    # Ensure Sub-Folders Exist
    $Results.RedactedFolder = Assert-FolderPath "$($Results.ResultsFolder)\Redacted"
    $Results.TranslatedFolder = Assert-FolderPath "$($Results.ResultsFolder)\Translated"
    $Results.OriginalFolder = Assert-FolderPath "$($Results.ResultsFolder)\Originals"

    $Results | Format-List | Out-Host

    return $Results

}

function Invoke-RedactFile() {
    [CmdletBinding()]
    PARAM (
        [Parameter(Mandatory = $true)]
        [object]$FileToRedact
    )

    $NextRedactionNo = 1
    $FileToRedact.FullName | Out-Host
    $TranslatedFileName = "$($global:OutputFolders.TranslatedFolder)\Translated_$($FileToRedact.Name)"
    Write-Debug "Translated Name: $($TranslatedFileName)"
    $RedactedFileName = "$($global:OutputFolders.RedactedFolder)\Redacted_$($FileToRedact.Name)"
    Write-Debug "Redacted Name: $($RedactedFileName)"

    Write-Host "Processing File: $($FileToRedact.Name)"
    Write-Host "Checking for following RegEx patterns: "
    $global:config | Out-Host 
    $LineNo = 1
    $FileData = Get-Content $FileToRedact.FullName 
    $FileData | Out-Host
    $FileLineCount = ($FileData | Measure-Object -Line).Lines

    # ForEach ($Current_Line in [System.IO.File]::ReadLines($FileToRedact.FullName)) {
    ForEach ($Current_Line in $FileData) {
        $RedactedString = $Current_Line
        $CheckNumber = 0
        Write-Debug "Line Data: $Current_Line"
        $TotalChecks = ($global:config.SearchPatternRegEx | Measure-Object).Count
        $NotFoundCount = 0
        $FoundCount = 0 
        
        ForEach ($RegExCheck in $global:config.SearchPatternRegEx) {

            $RedactPatternName = $global:config.SearchPatternDesc[$CheckNumber]
            If ($DebugPreference -eq "Continue") { Write-Host "" }
            Write-Debug "Applying RegEx $($RedactPatternName) - $RegExCheck"
            $Found = [RegEx]::Matches($RedactedString, $RegExCheck).Value # Could be one or more matches
            If ($OutputDetail -Or $Found) { 
                Write-Host "Line $($LineNo) of $FileLineCount in file $($FileToRedact.Name)" -NoNewline
            }

            If ($Found) {
                Write-Host " - Matches Found"  # stop the -NoNewLine
             
                $FoundCount += 1
                ForEach ( $f in $Found ) {

                    $OutRedactVal = "00000000$NextRedactionNo"
                    $OutRedactSuffix = "____________________$($RedactPatternName)"
                    $OutRedactVal = "#REDACTED_$($OutRedactVal.SubString($OutRedactVal.Length -7))$($OutRedactSuffix.Substring($OutRedactSuffix.Length -20))#"
                    "$OutRedactVal `t $f" | Out-File -FilePath $TranslatedFileName -Append
                    $RedactedString = $RedactedString.Replace($f, $OutRedactVal)
                    Write-Host "$($RedactPatternName) $f" -ForegroundColor Green 
                    Write-Debug "`tRedacted string is $RedacedString"
                    $NextRedactionNo += 1

                }
                Write-Debug "[$($Found)] = $Current_Line"

            }
            Else {
                $NotFoundCount += 1
            }
            $CheckNumber += 1

        }
        If ($NotFoundCount -eq $TotalChecks) {
            If ($OutputDetail) { Write-Host " - No Matches Found" -Forground Gray }
            $RedactedString = $Current_Line
        }
        Write-Debug "NotFoundChecks: $NotFoundCount - TotalChecks: $TotalChecks"
        Write-Debug "Final Redacted Line: $RedactedString"
        $RedactedString | Out-File -FilePath $RedactedFileName -Append
        $LineNo += 1

    }

}

function Start-Redaction() {
    [CmdletBinding()]
    PARAM (
        [string]$OutFolder = ".\",
        [bool]$DoFolder = $true
    )

    # Create Output Folders
    $global:OutputFolders = Assert-FolderStructure -OutFolder $OutFolder

    # Configure Execution Parameters
    $global:Config = Get-Configuration -DoFolder $DoFolder

    # Start To Process
    If ($global:Config.SearchPath) {
        Write-Host "Starting Redaction"

        $ItemList = Get-ChildItem $Global:Config.SearchPath -Include $Global:Config.FileTypes -Recurse
        $ItemList.FullName | Out-File "$($Global:OutputFolders.ResultsFolder)\ProcessedFileList.txt"

        ForEach ($Item in $ItemList) {

            Copy-Item -Path $Item.FullName -Destination $global:OutputFolders.OriginalFolder
            Invoke-RedactFile -FileToRedact $Item
        }

    } 
    Else {
        Write-Error "Invalid Configuration - Script Halted!"
    }
    $Global:Config | Format-List | Out-Host
    Invoke-Item "$($global:OutputFolders.ResultsFolder)"

}

# * SCRIPT START

If (!$OutputFolder -Or $OutputFolder -eq "") {
    $SelectOutputFolder = Get-Folder -PromptMessage "Select the root folder to store outputs of this execution"
    If (!$SelectOutputFolder) { $OutputFolder = ".\" } else { $OutputFolder = $SelectOutputFolder }
}

Write-Debug "OutputFolder: `t`t$OutputFolder"
Write-Debug "SelectOutputFolder: `t$SelectOutputFolder"
# Start Redaction
Start-Redaction -DoFolder $ProcessFolder -OutFolder $OutputFolder

