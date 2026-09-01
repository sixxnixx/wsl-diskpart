#requires -Version 5.1
[CmdletBinding()]
param(
    [Alias('d')]
    [string[]] $Distro,

    [Alias('a')]
    [switch] $All,

    [switch] $List,

    [Alias('y')]
    [switch] $Yes,

    [switch] $DryRun,

    [switch] $NoElevation
)

$ErrorActionPreference = 'Stop'

function Test-Administrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Quote-ProcessArgument {
    param(
        [Parameter(Mandatory)]
        [string] $Value
    )

    if ($Value -notmatch '[\s"]') {
        return $Value
    }

    return '"' + $Value.Replace('"', '\"') + '"'
}

function Start-ElevatedSelf {
    if ([string]::IsNullOrWhiteSpace($PSCommandPath)) {
        throw 'スクリプトのパスを取得できないため、管理者として再起動できません。'
    }

    $hostPath = $null

    try {
        $hostPath = (Get-Process -Id $PID -ErrorAction Stop).Path
    }
    catch {
    }

    if ([string]::IsNullOrWhiteSpace($hostPath) -or -not (Test-Path -LiteralPath $hostPath)) {
        $hostPath = (Get-Command pwsh.exe -ErrorAction SilentlyContinue).Source
    }

    if ([string]::IsNullOrWhiteSpace($hostPath)) {
        $hostPath = (Get-Command powershell.exe -ErrorAction Stop).Source
    }

    $rawArguments = @(
        '-NoProfile'
        '-ExecutionPolicy'
        'Bypass'
        '-File'
        $PSCommandPath
    )

    if ($All) {
        $rawArguments += '-All'
    }

    if ($List) {
        $rawArguments += '-List'
    }

    if ($Yes) {
        $rawArguments += '-Yes'
    }

    if ($DryRun) {
        $rawArguments += '-DryRun'
    }

    foreach ($name in @($Distro)) {
        $rawArguments += @('-Distro', $name)
    }

    $argumentString = ($rawArguments | ForEach-Object {
        Quote-ProcessArgument ([string] $_)
    }) -join ' '

    try {
        $child = Start-Process -FilePath $hostPath -ArgumentList $argumentString -Verb RunAs -Wait -PassThru
        return $child.ExitCode
    }
    catch [System.ComponentModel.Win32Exception] {
        if ($_.Exception.NativeErrorCode -eq 1223) {
            Write-Error 'ユーザーが管理者権限への昇格をキャンセルしました。'
        }
        else {
            Write-Error ('管理者としての再起動に失敗しました: {0}' -f $_.Exception.Message)
        }

        return 1
    }
}

function Normalize-Identifier {
    param(
        [AllowNull()]
        [string] $Value
    )

    if ($null -eq $Value) {
        return ''
    }

    return (($Value -replace '[{}-]', '').ToUpperInvariant())
}

function Normalize-PathValue {
    param(
        [AllowNull()]
        [string] $Value
    )

    if ([string]::IsNullOrWhiteSpace($Value)) {
        return $null
    }

    $path = [Environment]::ExpandEnvironmentVariables($Value.Trim())

    if ($path.StartsWith('\\?\UNC\', [StringComparison]::OrdinalIgnoreCase)) {
        $path = '\\' + $path.Substring(8)
    }
    elseif ($path.StartsWith('\\?\', [StringComparison]::OrdinalIgnoreCase)) {
        $path = $path.Substring(4)
    }

    try {
        return [IO.Path]::GetFullPath($path)
    }
    catch {
        return $path
    }
}

function Find-VhdxPath {
    param(
        [Parameter(Mandatory)]
        [string] $RegistryId,

        [AllowNull()]
        [string] $BasePath,

        [AllowNull()]
        [string] $VhdFileName
    )

    $candidates = @()

    if (-not [string]::IsNullOrWhiteSpace($VhdFileName)) {
        if ([IO.Path]::IsPathRooted($VhdFileName)) {
            $candidates += $VhdFileName
        }
        elseif (-not [string]::IsNullOrWhiteSpace($BasePath)) {
            $candidates += Join-Path $BasePath $VhdFileName
        }
    }

    if (-not [string]::IsNullOrWhiteSpace($BasePath)) {
        $candidates += Join-Path $BasePath 'ext4.vhdx'
    }

    $localAppData = [Environment]::GetFolderPath([Environment+SpecialFolder]::LocalApplicationData)
    $wslRoot = Join-Path $localAppData 'wsl'
    $candidates += Join-Path (Join-Path $wslRoot $RegistryId) 'ext4.vhdx'
    $candidates += Join-Path (Join-Path $wslRoot ('{{{0}}}' -f $RegistryId)) 'ext4.vhdx'

    if (Test-Path -LiteralPath $wslRoot -PathType Container) {
        foreach ($directory in @(Get-ChildItem -LiteralPath $wslRoot -Directory -ErrorAction SilentlyContinue)) {
            if ((Normalize-Identifier $directory.Name) -eq (Normalize-Identifier $RegistryId)) {
                $candidates += Join-Path $directory.FullName 'ext4.vhdx'
            }
        }
    }

    foreach ($candidate in @($candidates | Select-Object -Unique)) {
        $path = Normalize-PathValue $candidate

        if ($null -ne $path -and (Test-Path -LiteralPath $path -PathType Leaf)) {
            return $path
        }
    }

    return $null
}

function Remove-JsonComments {
    param(
        [Parameter(Mandatory)]
        [string] $Text
    )

    $builder = New-Object Text.StringBuilder
    $inString = $false
    $escaped = $false
    $lineComment = $false
    $blockComment = $false

    for ($i = 0; $i -lt $Text.Length; $i++) {
        $current = $Text[$i]
        $next = [char] 0

        if ($i + 1 -lt $Text.Length) {
            $next = $Text[$i + 1]
        }

        if ($lineComment) {
            if ($current -eq [char] 13 -or $current -eq [char] 10) {
                $lineComment = $false
                [void] $builder.Append($current)
            }

            continue
        }

        if ($blockComment) {
            if ($current -eq '*' -and $next -eq '/') {
                $blockComment = $false
                $i++
            }
            elseif ($current -eq [char] 13 -or $current -eq [char] 10) {
                [void] $builder.Append($current)
            }

            continue
        }

        if ($inString) {
            [void] $builder.Append($current)

            if ($escaped) {
                $escaped = $false
            }
            elseif ($current -eq '\') {
                $escaped = $true
            }
            elseif ($current -eq '"') {
                $inString = $false
            }

            continue
        }

        if ($current -eq '"') {
            $inString = $true
            [void] $builder.Append($current)
        }
        elseif ($current -eq '/' -and $next -eq '/') {
            $lineComment = $true
            $i++
        }
        elseif ($current -eq '/' -and $next -eq '*') {
            $blockComment = $true
            $i++
        }
        else {
            [void] $builder.Append($current)
        }
    }

    return $builder.ToString()
}

function Remove-TrailingJsonCommas {
    param(
        [Parameter(Mandatory)]
        [string] $Text
    )

    $builder = New-Object Text.StringBuilder
    $inString = $false
    $escaped = $false

    for ($i = 0; $i -lt $Text.Length; $i++) {
        $current = $Text[$i]

        if ($inString) {
            [void] $builder.Append($current)

            if ($escaped) {
                $escaped = $false
            }
            elseif ($current -eq '\') {
                $escaped = $true
            }
            elseif ($current -eq '"') {
                $inString = $false
            }

            continue
        }

        if ($current -eq '"') {
            $inString = $true
            [void] $builder.Append($current)
            continue
        }

        if ($current -ne ',') {
            [void] $builder.Append($current)
            continue
        }

        $lookahead = $i + 1

        while ($lookahead -lt $Text.Length -and [char]::IsWhiteSpace($Text[$lookahead])) {
            $lookahead++
        }

        if ($lookahead -ge $Text.Length -or ($Text[$lookahead] -ne '}' -and $Text[$lookahead] -ne ']')) {
            [void] $builder.Append($current)
        }
    }

    return $builder.ToString()
}

function Get-TerminalProfiles {
    $localAppData = [Environment]::GetFolderPath([Environment+SpecialFolder]::LocalApplicationData)
    $packageRoot = Join-Path $localAppData 'Packages'
    $paths = @()

    if (Test-Path -LiteralPath $packageRoot -PathType Container) {
        $paths += @(
            Get-ChildItem -LiteralPath $packageRoot -Directory -ErrorAction SilentlyContinue |
                Where-Object { $_.Name -like 'Microsoft.WindowsTerminal*_*' } |
                ForEach-Object { Join-Path $_.FullName 'LocalState\settings.json' }
        )
    }

    $paths += Join-Path $localAppData 'Microsoft\Windows Terminal\settings.json'
    $profiles = @()

    foreach ($path in @($paths | Select-Object -Unique)) {
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
            continue
        }

        try {
            $jsonText = [IO.File]::ReadAllText($path)
            $jsonText = Remove-JsonComments $jsonText
            $jsonText = Remove-TrailingJsonCommas $jsonText
            $json = $jsonText | ConvertFrom-Json

            if ($json.profiles -is [Array]) {
                $entries = @($json.profiles)
            }
            elseif ($null -ne $json.profiles.list) {
                $entries = @($json.profiles.list)
            }
            else {
                $entries = @()
            }

            foreach ($profile in $entries) {
                $name = [string] $profile.name

                if ([string]::IsNullOrWhiteSpace($name)) {
                    continue
                }

                $item = [pscustomobject] @{
                    Name        = $name
                    Guid        = [string] $profile.guid
                    Source      = [string] $profile.source
                    CommandLine = [string] $profile.commandline
                }

                $duplicate = @(
                    $profiles |
                        Where-Object {
                            $_.Name -ieq $item.Name -and $_.Guid -ieq $item.Guid
                        }
                )

                if ($duplicate.Count -eq 0) {
                    $profiles += $item
                }
            }
        }
        catch {
        }
    }

    return @($profiles)
}

function Get-WslStatuses {
    try {
        $text = (& wsl.exe --list --verbose 2>&1 | Out-String).Trim()
        $text = $text.Replace(([char] 0).ToString(), '')

        if ($LASTEXITCODE -ne 0) {
            return @()
        }

        $result = @()

        foreach ($line in ($text -split '\r?\n')) {
            $line = $line.Trim()

            if (
                $line -and
                $line -notmatch '^NAME\s+' -and
                $line -match '^\*?\s*(?<Name>.+?)\s{2,}(?<State>\S+)\s+(?<Version>[12])\s*$'
            ) {
                $result += [pscustomobject] @{
                    Name    = $Matches.Name.Trim()
                    State   = $Matches.State
                    Version = [int] $Matches.Version
                }
            }
        }

        return @($result)
    }
    catch {
        return @()
    }
}

function Get-WslDistributions {
    $registryRoot = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Lxss'
    $profiles = @(Get-TerminalProfiles)
    $statuses = @(Get-WslStatuses)
    $items = @()
    $knownPaths = @{}

    if (Test-Path -LiteralPath $registryRoot) {
        foreach ($key in @(Get-ChildItem -LiteralPath $registryRoot -ErrorAction SilentlyContinue)) {
            try {
                $properties = Get-ItemProperty -LiteralPath $key.PSPath
                $wslName = [string] $properties.DistributionName

                if ([string]::IsNullOrWhiteSpace($wslName)) {
                    continue
                }

                $basePath = Normalize-PathValue ([string] $properties.BasePath)
                $vhdFileName = [string] $properties.VhdFileName

                if ([string]::IsNullOrWhiteSpace($vhdFileName)) {
                    $vhdFileName = [string] $properties.VHDFileName
                }

                $vhdxPath = Find-VhdxPath -RegistryId $key.PSChildName -BasePath $basePath -VhdFileName $vhdFileName

                if ($null -eq $vhdxPath) {
                    continue
                }

                $terminalProfile = $profiles |
                    Where-Object { $_.Name -ieq $wslName } |
                    Select-Object -First 1

                if ($null -eq $terminalProfile) {
                    $terminalProfile = $profiles |
                        Where-Object {
                            (Normalize-Identifier $_.Guid) -eq (Normalize-Identifier $key.PSChildName)
                        } |
                        Select-Object -First 1
                }

                $status = $statuses |
                    Where-Object { $_.Name -ieq $wslName } |
                    Select-Object -First 1

                $version = $null
                $parsedVersion = 0

                if ([int]::TryParse([string] $properties.Version, [ref] $parsedVersion)) {
                    $version = $parsedVersion
                }
                elseif ($null -ne $status) {
                    $version = $status.Version
                }

                $file = Get-Item -LiteralPath $vhdxPath
                $displayName = $wslName
                $terminalName = $null
                $state = $null

                if ($null -ne $terminalProfile) {
                    $displayName = $terminalProfile.Name
                    $terminalName = $terminalProfile.Name
                }

                if ($null -ne $status) {
                    $state = $status.State
                }

                $items += [pscustomobject] @{
                    WslName      = $wslName
                    DisplayName  = $displayName
                    TerminalName = $terminalName
                    VhdxPath     = $vhdxPath
                    SizeBytes    = [int64] $file.Length
                    Version      = $version
                    State        = $state
                    RegistryId   = $key.PSChildName
                    Unknown      = $false
                }

                $knownPaths[$vhdxPath.ToLowerInvariant()] = $true
            }
            catch {
            }
        }
    }

    $wslRoot = Join-Path ([Environment]::GetFolderPath([Environment+SpecialFolder]::LocalApplicationData)) 'wsl'

    if (Test-Path -LiteralPath $wslRoot -PathType Container) {
        foreach ($file in @(Get-ChildItem -LiteralPath $wslRoot -Filter 'ext4.vhdx' -File -Recurse -ErrorAction SilentlyContinue)) {
            if ($knownPaths.ContainsKey($file.FullName.ToLowerInvariant())) {
                continue
            }

            $folder = Split-Path $file.DirectoryName -Leaf
            $unregisteredName = '未登録 VHDX ({0})' -f $folder

            $items += [pscustomobject] @{
                WslName      = $unregisteredName
                DisplayName  = $unregisteredName
                TerminalName = $null
                VhdxPath     = $file.FullName
                SizeBytes    = [int64] $file.Length
                Version      = 2
                State        = $null
                RegistryId   = $folder
                Unknown      = $true
            }
        }
    }

    return @($items | Sort-Object DisplayName)
}

function Format-Bytes {
    param(
        [Int64] $Bytes
    )

    $value = [double] $Bytes
    $units = @('B', 'KB', 'MB', 'GB', 'TB')
    $unit = 0

    while ($value -ge 1024 -and $unit -lt ($units.Count - 1)) {
        $value /= 1024
        $unit++
    }

    if ($unit -eq 0) {
        return '{0:N0} {1}' -f $Bytes, $units[$unit]
    }

    return '{0:N2} {1}' -f $value, $units[$unit]
}

function Show-Distributions {
    param(
        [object[]] $Items
    )

    Write-Host '検出した対象:'
    Write-Host ''

    for ($i = 0; $i -lt $Items.Count; $i++) {
        $item = $Items[$i]

        if ($item.TerminalName) {
            $terminal = 'Terminal: {0}' -f $item.TerminalName
        }
        else {
            $terminal = 'Terminal設定名なし'
        }

        if ($item.State) {
            $state = $item.State
        }
        else {
            $state = '状態不明'
        }

        if ($item.Version) {
            $version = 'WSL {0}' -f $item.Version
        }
        else {
            $version = 'WSLバージョン不明'
        }

        Write-Host ('  {0}. {1}' -f ($i + 1), $item.DisplayName)

        if ($item.DisplayName -ine $item.WslName) {
            Write-Host ('     WSL名: {0}' -f $item.WslName)
        }

        Write-Host ('     {0} / {1} / {2}' -f $terminal, $state, $version)
        Write-Host ('     VHDX: {0}' -f $item.VhdxPath)
        Write-Host ('     サイズ: {0}' -f (Format-Bytes $item.SizeBytes))
        Write-Host ''
    }
}

function Resolve-Selection {
    param(
        [object[]] $Items,
        [string[]] $Selectors,
        [switch] $SelectAll
    )

    if ($SelectAll) {
        return @($Items)
    }

    $expanded = @(
        $Selectors |
            ForEach-Object { $_ -split ',' } |
            Where-Object { $_ } |
            ForEach-Object { $_.Trim() }
    )

    while ($true) {
        if ($expanded.Count -eq 0) {
            $inputValue = Read-Host '対象を選択してください（番号、1,3、名前、A=全て、Q=終了）'

            if ($inputValue -match '^(?i:q)$') {
                return @()
            }

            if ($inputValue -match '^(?i:a|all)$') {
                return @($Items)
            }

            $expanded = @(
                $inputValue -split ',' |
                    ForEach-Object { $_.Trim() } |
                    Where-Object { $_ }
            )
        }

        $selected = @()
        $valid = $true

        foreach ($selector in $expanded) {
            $number = 0

            if ([int]::TryParse($selector, [ref] $number)) {
                if ($number -lt 1 -or $number -gt $Items.Count) {
                    Write-Host ('番号 {0} は範囲外です。' -f $number)
                    $valid = $false
                    break
                }

                $selected += $Items[$number - 1]
                continue
            }

            $matches = @(
                $Items |
                    Where-Object {
                        $_.DisplayName -ieq $selector -or $_.WslName -ieq $selector
                    }
            )

            if ($matches.Count -eq 0) {
                Write-Host ('ディストロ名「{0}」が見つかりません。' -f $selector)
                $valid = $false
                break
            }

            $selected += $matches
        }

        if ($valid) {
            return @($selected | Sort-Object VhdxPath -Unique)
        }

        $expanded = @()
    }
}

function Invoke-DiskPartCompact {
    param(
        [Parameter(Mandatory)]
        [string] $VhdxPath
    )

    $diskPartScript = Join-Path ([IO.Path]::GetTempPath()) ('wsl-diskpart-{0}.txt' -f ([Guid]::NewGuid().ToString('N')))

    $commands = @(
        ('select vdisk file="{0}"' -f $VhdxPath)
        'attach vdisk readonly'
        'compact vdisk'
        'detach vdisk'
        'exit'
    )

    try {
        $content = ($commands -join [Environment]::NewLine) + [Environment]::NewLine
        [IO.File]::WriteAllText($diskPartScript, $content, [Text.Encoding]::Unicode)

        $output = (& diskpart.exe /s $diskPartScript 2>&1 | Out-String).Trim()
        $exitCode = $LASTEXITCODE
        $hasError = $output -match '(?i)error|failed|failure|cannot|could not|not found|access is denied|エラー|失敗|見つかりません|アクセスが拒否'

        if ($hasError) {
            $message = 'DiskPartがエラーを返しました。'
        }
        else {
            $message = '終了コード {0}' -f $exitCode
        }

        return [pscustomobject] @{
            Succeeded = ($exitCode -eq 0 -and -not $hasError)
            Message   = $message
            Output    = $output
        }
    }
    catch {
        return [pscustomobject] @{
            Succeeded = $false
            Message   = $_.Exception.Message
            Output    = ''
        }
    }
    finally {
        if (Test-Path -LiteralPath $diskPartScript) {
            Remove-Item -LiteralPath $diskPartScript -Force -ErrorAction SilentlyContinue
        }
    }
}

$distroCount = if ($null -eq $Distro) { 0 } else { $Distro.Count }

if (
    ($All -and $distroCount -gt 0) -or
    ($List -and ($All -or $distroCount -gt 0))
) {
    throw '-All、-List、-Distroは同時に指定できません。'
}

if (
    -not $List -and
    -not $DryRun -and
    -not $NoElevation -and
    -not (Test-Administrator)
) {
    exit (Start-ElevatedSelf)
}

Write-Host 'WSL VHDX コンパクター'
Write-Host 'WSL 2のext4.vhdxをDiskPartで圧縮します。'
Write-Host ''

$items = @(Get-WslDistributions)

if ($items.Count -eq 0) {
    Write-Host 'ext4.vhdxを持つWSLディストロが見つかりませんでした。'
    exit 1
}

Show-Distributions $items

if ($List) {
    exit 0
}

$selected = @(Resolve-Selection -Items $items -Selectors @($Distro) -SelectAll:$All)

if ($selected.Count -eq 0) {
    Write-Host '処理をキャンセルしました。'
    exit 0
}

Write-Host '実行対象:'
$selected | ForEach-Object {
    Write-Host ('  - {0}: {1}' -f $_.DisplayName, $_.VhdxPath)
}

if ($DryRun) {
    Write-Host 'dry-runのため、変更は行いません。'
    exit 0
}

Write-Host ''
Write-Host '実行すると、最初に全てのWSLディストロを停止します。'

if (-not $Yes) {
    $answer = Read-Host '実行しますか？ [y/N]'

    if ($answer -notmatch '^(?i:y|yes)$') {
        Write-Host '処理をキャンセルしました。'
        exit 0
    }
}

Write-Host 'WSLをシャットダウンしています...'
$shutdownOutput = (& wsl.exe --shutdown 2>&1 | Out-String).Trim()

if ($LASTEXITCODE -ne 0) {
    Write-Error 'wsl --shutdownに失敗しました。'

    if ($shutdownOutput) {
        Write-Error $shutdownOutput
    }

    exit 1
}

Start-Sleep -Seconds 1
Write-Host 'WSLのシャットダウンが完了しました。'

$failed = 0

foreach ($item in $selected) {
    Write-Host ('[{0}] 圧縮しています...' -f $item.DisplayName)
    $before = (Get-Item -LiteralPath $item.VhdxPath).Length
    $result = Invoke-DiskPartCompact -VhdxPath $item.VhdxPath

    if (-not $result.Succeeded) {
        $failed++
        Write-Error ('失敗: {0}' -f $result.Message)

        if ($result.Output) {
            Write-Error $result.Output
        }

        continue
    }

    $after = (Get-Item -LiteralPath $item.VhdxPath).Length
    Write-Host '  完了しました。'
    Write-Host ('  サイズ: {0} → {1}' -f (Format-Bytes $before), (Format-Bytes $after))
}

if ($failed -gt 0) {
    Write-Error ('{0}件中{1}件の処理に失敗しました。' -f $selected.Count, $failed)
    exit 1
}

Write-Host '全ての対象ディストロの圧縮が完了しました。'
exit 0

