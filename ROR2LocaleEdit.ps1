$AppId = 632360

Function Get-SteamPath {
    return (Get-Item 'HKCU:\Software\Valve\Steam\').GetValue("SteamPath").Replace("/", "\")
}

Function ConvertFrom-VDF {
    <# 
    .Synopsis 
        Reads a Valve Data File (VDF) formatted string into a custom object.
    .Description 
        The ConvertFrom-VDF cmdlet converts a VDF-formatted string to a custom object (PSCustomObject) that has a property for each field in the VDF string. VDF is used as a textual data format for Valve software applications, such as Steam.
    .Parameter InputObject
        Specifies the VDF strings to convert to PSObjects. Enter a variable that contains the string, or type a command or expression that gets the string. 
    .Example 
        $vdf = ConvertFrom-VDF -InputObject (Get-Content ".\SharedConfig.vdf")
        Description 
        ----------- 
        Gets the content of a VDF file named "SharedConfig.vdf" in the current location and converts it to a PSObject named $vdf
    .Inputs 
        System.String
    .Outputs 
        PSCustomObject
    #>
    [cmdletbinding()]
    param
    (
        [Parameter(Position = 0, Mandatory = $True, ValueFromPipeline = $true)]
        [ValidateNotNullOrEmpty()]
        [String[]]
        $InputObject
    )
    Begin {
        $root = New-Object -TypeName PSObject
        $chain = [ordered]@{}
        $depth = 0
        $parent = $root
        $element = $null
    }
    
    Process {
        #Magic PowerShell Switch Enumrates Arrays
        switch -Regex ($InputObject) {
            #Case: ValueKey
            '^\t*"(\S+)"\t\t"(.+)"$' {
                Add-Member -InputObject $element -MemberType NoteProperty -Name $Matches[1] -Value $Matches[2]
                continue
            }
            #Case: ParentKey
            '^\t*"(\S+)"$' { 
                $element = New-Object -TypeName PSObject
                Add-Member -InputObject $parent -MemberType NoteProperty -Name $Matches[1] -Value $element
                continue
            }
            #Case: Opening ParentKey Scope
            '^\t*{$' {
                $parent = $element
                $chain.Add($depth, $element)
                $depth++
                continue
            }
            #Case: Closing ParentKey Scope
            '^\t*}$' {
                $depth--
                $parent = $chain.($depth - 1)
                $element = $parent
                $chain.Remove($depth)
                continue
            }
            #Case: Comments or unsupported lines
            Default {
                Write-Debug "Ignored line: $_"
                continue
            }
        } 
    }
    End {
        return $root
    }
}

function FindGameLibraryFolder {
    param (
        [Parameter(Mandatory = $true)]
        [int]
        $GameAppId
    )

    $LibraryFolders = Get-Content "$(Get-SteamPath)\steamapps\libraryfolders.vdf" -Encoding utf8 | ConvertFrom-VDF

    for ($i = 1; $true; $i++) {        
        if ($null -eq $LibraryFolders.LibraryFolders."$i") {
            break
        }

        $path = $LibraryFolders.LibraryFolders."$i".path.Replace("\\", "\")

        if (-Not $null -eq $LibraryFolders.LibraryFolders."$i".apps."$GameAppId") {
            return $path
        }
        #$LibraryFolders.LibraryFolders."$i".apps | % { if ($_.name -eq $GameDepotId) { Write-Output "Found" } }       
    }
}

$libFolder = $(FindGameLibraryFolder -GameAppId $AppId)

$installDir = $(Get-Content "$libFolder\steamapps\appmanifest_$AppId.acf" | ConvertFrom-VDF).AppState.Installdir
$fullGameDir = "$libFolder\steamapps\common\$installDir"
Write-Host "게임 설치 경로: " -nonewline -ForegroundColor Yellow
Write-Host $fullGameDir -foreground Green

Write-Host "`n수정 내용을 불러오는 중..." -ForegroundColor Yellow

$jsonEdit = ((New-Object System.Net.WebClient)).DownloadString("https://raw.githubusercontent.com/Hatser/ROR2LocaleEdit/main/edits/edit-korean.json") | ConvertFrom-Json

Write-Host "`n수정 대상 파일을 찾는 중..." -ForegroundColor Yellow

$targetPath = $jsonEdit.target.Replace("\\", "\")

Write-Host "`n대상 경로: " -nonewline -ForegroundColor Yellow
Write-Host "$fullGameDir\$targetPath" -foreground Green

Write-Host "`n수정 내용 반영 중..." -ForegroundColor Yellow
$jsonTarget = Get-Content "$fullGameDir\$targetPath" -raw | ConvertFrom-Json
$jsonEdit.update.PSObject.Properties | % { $jsonTarget.strings.($_.name) = $_.value }

Write-Host "`n기존 파일 백업 중..." -ForegroundColor Yellow
Rename-Item -Path "$fullGameDir\$targetPath" -NewName "$fullGameDir\$targetPath".Replace('.json', "$(Get-Date -Format "yyyyMMddHHmmssff")_.bak")

Write-Host "`n수정 사항 저장 중..." -ForegroundColor Yellow
$jsonTarget | ConvertTo-Json -depth 2 | set-content "$fullGameDir\$targetPath"

Write-Host "`n수정 사항 반영 완료, 아무 키나 누르면 종료합니다..." -ForegroundColor Cyan
$null = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown');
