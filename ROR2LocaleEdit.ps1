$AppId = 632360

Function Get-Folder($initialDirectory) {
    [void] [System.Reflection.Assembly]::LoadWithPartialName('System.Windows.Forms')
    $FolderBrowserDialog = New-Object System.Windows.Forms.FolderBrowserDialog
    $FolderBrowserDialog.RootFolder = 'MyComputer'
    if ($initialDirectory) { $FolderBrowserDialog.SelectedPath = $initialDirectory }
    [void] $FolderBrowserDialog.ShowDialog()
    return $FolderBrowserDialog.SelectedPath
}

Function Get-SteamPath {
    try {
        return (Get-Item 'HKCU:\Software\Valve\Steama\' -ErrorAction SilentlyContinue).GetValue("SteamPath").Replace("/", "\")
    }
    catch {
        Write-Host "Steam 경로를 찾을 수 없었습니다.`n직접 선택하시겠습니까?" -ForegroundColor White
        Write-Host "기본 값: " -NoNewline -ForegroundColor White
        Write-Host "ENTER" -ForegroundColor Yellow
        Write-Host "[ENTER] 예 " -NoNewline -ForegroundColor Yellow
        Write-Host "[N] 스크립트 종료" -ForegroundColor White
        $Key = $Host.UI.RawUI.ReadKey()
        Switch ($Key.Character) {
            Default {
                $folder = Get-Folder
                if ($folder -eq "") {
                    exit
                }
                return $folder
            }
            N {
                exit
            }
        }
    }
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

    try { 
        $LibraryFolders = Get-Content "$(Get-SteamPath)\steamapps\libraryfolders.vdf" -ErrorAction Stop -Encoding utf8 | ConvertFrom-VDF
    }
    catch {
        Write-Host "라이브러리 정보 파일을 찾지 못했습니다. 스크립트를 종료합니다." -NoNewline -ForegroundColor White
        exit
    }

    for ($i = 1; $true; $i++) {        
        if ($null -eq $LibraryFolders.LibraryFolders."$i") {
            break
        }

        $path = $LibraryFolders.LibraryFolders."$i".path.Replace("\\", "\")

        if (-Not $null -eq $LibraryFolders.LibraryFolders."$i".apps."$GameAppId") {
            return $path
        }    
    }
}

$libFolder = $(FindGameLibraryFolder -GameAppId $AppId)

$installDir = $(Get-Content "$libFolder\steamapps\appmanifest_$AppId.acf" | ConvertFrom-VDF).AppState.Installdir
$fullGameDir = "$libFolder\steamapps\common\$installDir"
Write-Host "게임 설치 경로: " -NoNewline -ForegroundColor White
Write-Host $fullGameDir -ForegroundColor Green

Write-Host "`n수정 내용을 불러오는 중..." -ForegroundColor White

$webClient = New-Object System.Net.WebClient
$webClient.Encoding = [System.Text.Encoding]::UTF8
$jsonEdit = $webClient.DownloadString("https://raw.githubusercontent.com/Hatser/ROR2LocaleEdit/main/edits/edit-korean.json") | ConvertFrom-Json

Write-Host "`n수정 대상 파일을 찾는 중..." -ForegroundColor White

$targetPath = $jsonEdit.target.Replace("\\", "\")

Write-Host "`n대상 경로: " -NoNewline -ForegroundColor White
Write-Host "$fullGameDir\$targetPath" -ForegroundColor Green

Write-Host "`n수정 내용 반영 중..." -ForegroundColor White
try { 
    $jsonTarget = Get-Content "$fullGameDir\$targetPath" -raw | ConvertFrom-Json
}
catch {
    Write-Host "수정 대상 파일을 찾지 못했습니다. 스크립트를 종료합니다." -NoNewline -ForegroundColor White
    exit
}
$jsonEdit.update.PSObject.Properties | % { 
    Write-Host "$(($_.name))" -NoNewline -ForegroundColor Green
    Write-Host " = " -NoNewline -ForegroundColor White
    Write-Host "$($jsonTarget.strings.($_.name))" -NoNewline -ForegroundColor Yellow
    Write-Host " -> " -NoNewline -ForegroundColor White
    Write-Host "$(($_.value))" -ForegroundColor Cyan
    $jsonTarget.strings.($_.name) = $_.value
}

Write-Host "`n기존 파일 백업 중..." -ForegroundColor White
Rename-Item -Path "$fullGameDir\$targetPath" -NewName "$fullGameDir\$targetPath".Replace('.json', "_$(Get-Date -Format "yyyyMMddHHmmssff").json.bak")

Write-Host "`n수정 사항 저장 중..." -ForegroundColor White
$jsonTarget | ConvertTo-Json -depth 2 | set-content "$fullGameDir\$targetPath"

Write-Host "`n수정 사항 반영 완료, 아무 키나 누르면 종료합니다..." -ForegroundColor Cyan
$null = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown');
Invoke-Item $([System.IO.Path]::GetDirectoryName("$fullGameDir\$targetPath"))