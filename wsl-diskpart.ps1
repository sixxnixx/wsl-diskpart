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

$DiskPartScriptWaitSeconds = 15
$DiskPartMaxAttempts = 3

function Get-UiLanguage {
    $cultureName = $null

    try {
        # Read the Windows user display language directly. This avoids using a
        # PowerShell process UI culture, which can differ between pwsh and
        # Windows PowerShell even when the Windows display language is the same.
        if (-not ('WslDiskPart.NativeLanguage' -as [type])) {
            [void] (Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;

namespace WslDiskPart {
    public static class NativeLanguage {
        [DllImport("kernel32.dll")]
        public static extern ushort GetUserDefaultUILanguage();
    }
}
'@)
        }

        $languageId = [WslDiskPart.NativeLanguage]::GetUserDefaultUILanguage()

        if ($languageId -gt 0) {
            $cultureName = [string] ([Globalization.CultureInfo]::GetCultureInfo([int] $languageId).Name)
        }
    }
    catch {
    }

    if ([string]::IsNullOrWhiteSpace($cultureName)) {
        try {
            $preferredUiLanguages = @(
                (Get-ItemProperty `
                    -LiteralPath 'HKCU:\Control Panel\Desktop\MuiCached' `
                    -Name 'MachinePreferredUILanguages' `
                    -ErrorAction Stop).MachinePreferredUILanguages
            )

            if ($preferredUiLanguages.Count -gt 0) {
                $cultureName = [string] $preferredUiLanguages[0]
            }
        }
        catch {
        }
    }

    if ([string]::IsNullOrWhiteSpace($cultureName)) {
        try {
            $languageList = @(Get-WinUserLanguageList | Select-Object -First 1)

            if ($languageList.Count -gt 0) {
                $cultureName = [string] $languageList[0].LanguageTag
            }
        }
        catch {
        }
    }

    if ([string]::IsNullOrWhiteSpace($cultureName)) {
        try {
            $cultureName = [string] ((Get-UICulture).Name)
        }
        catch {
        }
    }

    if ([string]::IsNullOrWhiteSpace($cultureName)) {
        try {
            $cultureName = [string] ([Globalization.CultureInfo]::CurrentUICulture.Name)
        }
        catch {
        }
    }

    if ([string]::IsNullOrWhiteSpace($cultureName)) {
        try {
            $cultureName = [string] ([Globalization.CultureInfo]::InstalledUICulture.Name)
        }
        catch {
        }
    }

    if ($cultureName -match '^(?i:ja)(?:-|$)') {
        return 'ja'
    }

    return 'en'
}

$script:UiLanguage = Get-UiLanguage

$script:Messages = @{
    en = @{
        ScriptPathMissing             = 'Cannot relaunch as administrator because the script path could not be determined.'
        ElevationCanceled             = 'The user canceled the administrator elevation request.'
        ElevationFailedWin32          = 'Failed to relaunch as administrator (Win32 error {0}).'
        ElevationFailed               = 'Failed to relaunch as administrator.'
        DetectedTargets               = 'Detected targets:'
        TerminalLabel                 = 'Terminal: {0}'
        TerminalProfileUnavailable    = 'Terminal profile name unavailable'
        UnknownState                  = 'Unknown state'
        WslVersion                    = 'WSL {0}'
        UnknownWslVersion             = 'Unknown WSL version'
        WslNameLabel                  = '     WSL name: {0}'
        VhdxLabel                     = '     VHDX: {0}'
        SizeLabel                     = '     Size: {0}'
        SelectTargets                 = 'Select targets (numbers such as 1,3; name; A=all; Q=quit)'
        NumberOutOfRange              = 'Number {0} is out of range.'
        DistributionNotFound          = 'Distribution "{0}" was not found.'
        DiskPartReturnedError         = 'DiskPart returned an error.'
        ExitCode                      = 'Exit code {0}'
        DiskPartInvokeFailed          = 'Failed to invoke DiskPart.'
        Retry                         = '  Waiting for the VHDX to be released; retrying ({0}/{1}).'
        CompactConfirmed              = 'Confirmed that DiskPart compacted and detached the VHDX successfully.'
        AttachSuccessEvent            = 'Attach success event'
        CompactSuccessEvent           = 'Compact success event'
        DetachSuccessEvent            = 'Detach success event'
        ListSeparator                 = ', '
        CompletionUnconfirmed         = 'Could not confirm DiskPart completion: {0}'
        DiskPartExecutionFailed       = 'DiskPart execution failed: {0}; missing completion events: {1}'
        EventLogUnavailable           = 'Exit code 0 (VHDMP event log was unavailable)'
        DiskPartCouldNotExecute       = 'DiskPart could not be executed.'
        InvalidParameters             = 'Do not combine -All, -List, and -Distro.'
        Title                         = 'WSL VHDX Compactor'
        Subtitle                      = 'Compacts WSL 2 ext4.vhdx files with DiskPart.'
        NoTargets                     = 'No WSL distributions with ext4.vhdx were found.'
        Canceled                      = 'Operation canceled.'
        ExecutionTargets              = 'Execution targets:'
        ExecutionTargetItem           = '  - {0}: {1}'
        DryRun                        = 'Dry run: no changes were made.'
        AdminRequired                 = 'DiskPart requires administrator privileges. Start PowerShell as administrator and try again.'
        StopWarning                   = 'Running this operation will stop all WSL distributions first.'
        RunPrompt                     = 'Run it? [y/N]'
        ShuttingDown                  = 'Shutting down WSL...'
        ShutdownFailed                = 'wsl --shutdown failed (exit code {0}).'
        ShutdownCompleted             = 'WSL shutdown completed. Waiting {0} seconds for VHDX release...'
        PreviousDiskPartWait          = 'Waiting {0} seconds for the previous DiskPart operation to finish...'
        Compressing                   = 'Compressing...'
        BeforeReadFailed              = 'Could not read the VHDX before processing.'
        UnexpectedCompactionFailure   = 'The compaction operation failed unexpectedly.'
        Failed                        = 'Failed: {0}'
        NativeDetails                 = 'See the Microsoft-Windows-VHDMP-Operational event log for native operation details.'
        AfterReadFailed               = 'Could not read the VHDX size after processing.'
        Verified                      = '  Verified: {0}'
        Completed                     = '  Completed.'
        SizeChange                    = '  Size: {0} -> {1}'
        SummaryFailed                 = '{0} target(s), {1} failed.'
        AllSucceeded                  = 'All target distributions were processed successfully.'
        UnregisteredVhdx              = 'Unregistered VHDX ({0})'
        Running                       = 'Running'
        Stopped                       = 'Stopped'
        Installing                   = 'Installing'
        Unknown                      = 'Unknown'
    }
    ja = @{
        ScriptPathMissing             = 'スクリプトのパスを取得できないため、管理者として再起動できません。'
        ElevationCanceled             = 'ユーザーが管理者権限への昇格をキャンセルしました。'
        ElevationFailedWin32          = '管理者としての再起動に失敗しました（Win32エラー {0}）。'
        ElevationFailed               = '管理者としての再起動に失敗しました。'
        DetectedTargets               = '検出した対象:'
        TerminalLabel                 = 'Terminal: {0}'
        TerminalProfileUnavailable    = 'Terminal設定名なし'
        UnknownState                  = '状態不明'
        WslVersion                    = 'WSL {0}'
        UnknownWslVersion             = 'WSLバージョン不明'
        WslNameLabel                  = '     WSL名: {0}'
        VhdxLabel                     = '     VHDX: {0}'
        SizeLabel                     = '     サイズ: {0}'
        SelectTargets                 = '対象を選択してください（番号、例: 1,3、名前、A=全て、Q=終了）'
        NumberOutOfRange              = '番号 {0} は範囲外です。'
        DistributionNotFound          = 'ディストロ名「{0}」が見つかりません。'
        DiskPartReturnedError         = 'DiskPartがエラーを返しました。'
        ExitCode                      = '終了コード {0}'
        DiskPartInvokeFailed          = 'DiskPartを実行できませんでした。'
        Retry                         = '  VHDXの解放を待って再試行します（{0}/{1}）。'
        CompactConfirmed              = 'DiskPartの圧縮成功と切り離し成功を確認しました。'
        AttachSuccessEvent            = 'Attach成功イベント'
        CompactSuccessEvent           = 'Compact成功イベント'
        DetachSuccessEvent            = 'Detach成功イベント'
        ListSeparator                 = '、'
        CompletionUnconfirmed         = 'DiskPartの完了を確認できませんでした: {0}'
        DiskPartExecutionFailed       = 'DiskPartの実行に失敗しました: {0}; 完了イベント不足: {1}'
        EventLogUnavailable           = '終了コード 0（VHDMPイベントログは利用できませんでした）'
        DiskPartCouldNotExecute       = 'DiskPartを実行できませんでした。'
        InvalidParameters             = '-All、-List、-Distroは同時に指定できません。'
        Title                         = 'WSL VHDX コンパクター'
        Subtitle                      = 'WSL 2のext4.vhdxをDiskPartで圧縮します。'
        NoTargets                     = 'ext4.vhdxを持つWSLディストロが見つかりませんでした。'
        Canceled                      = '処理をキャンセルしました。'
        ExecutionTargets              = '実行対象:'
        ExecutionTargetItem           = '  - {0}: {1}'
        DryRun                        = 'dry-runのため、変更は行いません。'
        AdminRequired                 = 'DiskPartを実行するには管理者権限が必要です。管理者としてPowerShellを起動して再実行してください。'
        StopWarning                   = '実行すると、最初に全てのWSLディストロを停止します。'
        RunPrompt                     = '実行しますか？ [y/N]'
        ShuttingDown                  = 'WSLをシャットダウンしています...'
        ShutdownFailed                = 'wsl --shutdownに失敗しました（終了コード {0}）。'
        ShutdownCompleted             = 'WSLのシャットダウンが完了しました。VHDXの解放を{0}秒待機しています...'
        PreviousDiskPartWait          = '前のDiskPart処理の終了を待機しています（{0}秒）...'
        Compressing                   = '圧縮しています...'
        BeforeReadFailed              = '開始前にVHDXを読み取れませんでした。'
        UnexpectedCompactionFailure   = '圧縮処理で予期しないエラーが発生しました。'
        Failed                        = '失敗: {0}'
        NativeDetails                 = 'ネイティブ処理の詳細はMicrosoft-Windows-VHDMP-Operationalイベントログを確認してください。'
        AfterReadFailed               = '処理後にVHDXのサイズを確認できませんでした。'
        Verified                      = '  確認: {0}'
        Completed                     = '  完了しました。'
        SizeChange                    = '  サイズ: {0} → {1}'
        SummaryFailed                 = '{0}件中{1}件の処理に失敗しました。'
        AllSucceeded                  = '全ての対象ディストロの圧縮が完了しました。'
        UnregisteredVhdx              = '未登録 VHDX ({0})'
        Running                       = '実行中'
        Stopped                       = '停止'
        Installing                   = 'インストール中'
        Unknown                      = '状態不明'
    }
}

function Get-Message {
    param(
        [Parameter(Mandatory)]
        [string] $Key
    )

    $message = $script:Messages[$script:UiLanguage][$Key]

    if ($null -eq $message) {
        $message = $script:Messages.en[$Key]
    }

    return [string] $message
}

function Test-Administrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Quote-ProcessArgument {
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string] $Value
    )

    if ($Value.Length -eq 0) {
        return '""'
    }

    if ($Value -notmatch '[\s"]') {
        return $Value
    }

    return '"' + $Value.Replace('"', '\"') + '"'
}

function Convert-NativeBytesToText {
    param(
        [AllowNull()]
        [byte[]] $Bytes
    )

    if ($null -eq $Bytes -or $Bytes.Length -eq 0) {
        return ''
    }

    if ($Bytes.Length -ge 2 -and $Bytes[0] -eq 0xFF -and $Bytes[1] -eq 0xFE) {
        return [Text.Encoding]::Unicode.GetString($Bytes, 2, $Bytes.Length - 2)
    }

    if ($Bytes.Length -ge 2 -and $Bytes[0] -eq 0xFE -and $Bytes[1] -eq 0xFF) {
        return [Text.Encoding]::BigEndianUnicode.GetString($Bytes, 2, $Bytes.Length - 2)
    }

    if ($Bytes.Length -ge 3 -and $Bytes[0] -eq 0xEF -and $Bytes[1] -eq 0xBB -and $Bytes[2] -eq 0xBF) {
        return [Text.Encoding]::UTF8.GetString($Bytes, 3, $Bytes.Length - 3)
    }

    # wsl.exe and diskpart.exe emit UTF-16LE when their output is redirected.
    return [Text.Encoding]::Unicode.GetString($Bytes)
}

function Get-DiskPartScriptEncoding {
    # DiskPart's /s reader expects a legacy text script. UTF-16LE inserts NUL
    # bytes between ASCII command characters and can make the script a no-op.
    try {
        $codePage = [int] (Get-ItemProperty -LiteralPath 'HKLM:\SYSTEM\CurrentControlSet\Control\Nls\CodePage' -Name ACP -ErrorAction Stop).ACP

        return [Text.Encoding]::GetEncoding(
            $codePage,
            [Text.EncoderFallback]::ExceptionFallback,
            [Text.DecoderFallback]::ExceptionFallback
        )
    }
    catch {
        return [Text.Encoding]::GetEncoding(
            20127,
            [Text.EncoderFallback]::ExceptionFallback,
            [Text.DecoderFallback]::ExceptionFallback
        )
    }
}

function Invoke-NativeCommandCapture {
    param(
        [Parameter(Mandatory)]
        [string] $FilePath,

        [string[]] $ArgumentList = @()
    )

    $tempRoot = Join-Path ([IO.Path]::GetTempPath()) ('wsl-diskpart-native-{0}' -f ([Guid]::NewGuid().ToString('N')))
    $stdoutPath = $tempRoot + '.out'
    $stderrPath = $tempRoot + '.err'

    try {
        $argumentString = @(
            $ArgumentList |
                Where-Object { $null -ne $_ } |
                ForEach-Object { Quote-ProcessArgument ([string] $_) }
        ) -join ' '

        $process = Start-Process `
            -FilePath $FilePath `
            -ArgumentList $argumentString `
            -NoNewWindow `
            -Wait `
            -PassThru `
            -RedirectStandardOutput $stdoutPath `
            -RedirectStandardError $stderrPath

        $stdout = ''
        $stderr = ''

        if (Test-Path -LiteralPath $stdoutPath -PathType Leaf) {
            $stdout = Convert-NativeBytesToText ([IO.File]::ReadAllBytes($stdoutPath))
        }

        if (Test-Path -LiteralPath $stderrPath -PathType Leaf) {
            $stderr = Convert-NativeBytesToText ([IO.File]::ReadAllBytes($stderrPath))
        }

        return [pscustomobject] @{
            ExitCode       = [int] $process.ExitCode
            StandardOutput = $stdout
            StandardError  = $stderr
        }
    }
    catch {
        return [pscustomobject] @{
            ExitCode       = 1
            StandardOutput = ''
            StandardError  = $_.Exception.Message
        }
    }
    finally {
        foreach ($path in @($stdoutPath, $stderrPath)) {
            if (Test-Path -LiteralPath $path) {
                Remove-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue
            }
        }
    }
}

function Start-ElevatedSelf {
    if ([string]::IsNullOrWhiteSpace($PSCommandPath)) {
        throw (Get-Message 'ScriptPathMissing')
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
        if ($null -ne $name) {
            $rawArguments += @('-Distro', $name)
        }
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
            Write-Error (Get-Message 'ElevationCanceled')
        }
        else {
            Write-Error ((Get-Message 'ElevationFailedWin32') -f $_.Exception.NativeErrorCode)
        }

        return 1
    }
    catch {
        Write-Error (Get-Message 'ElevationFailed')
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

function Convert-WslState {
    param(
        [AllowNull()]
        [string] $State
    )

    if ([string]::IsNullOrWhiteSpace($State)) {
        return $null
    }

    switch -Regex ($State.Trim()) {
        '^(?i:running)$|^(実行中|起動中)$' { return (Get-Message 'Running') }
        '^(?i:stopped)$|^(停止|停止中|停止済み)$' { return (Get-Message 'Stopped') }
        '^(?i:installing)$|^インストール中$' { return (Get-Message 'Installing') }
        default { return (Get-Message 'Unknown') }
    }
}

function Get-WslStatuses {
    try {
        $nativeResult = Invoke-NativeCommandCapture -FilePath 'wsl.exe' -ArgumentList @('--list', '--verbose')

        if ($nativeResult.ExitCode -ne 0) {
            return @()
        }

        $text = ([string] $nativeResult.StandardOutput).Trim()

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
                    State   = Convert-WslState $Matches.State
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
            $unregisteredName = (Get-Message 'UnregisteredVhdx') -f $folder

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

    Write-Host (Get-Message 'DetectedTargets')
    Write-Host ''

    for ($i = 0; $i -lt $Items.Count; $i++) {
        $item = $Items[$i]

        if ($item.TerminalName) {
            $terminal = (Get-Message 'TerminalLabel') -f $item.TerminalName
        }
        else {
            $terminal = Get-Message 'TerminalProfileUnavailable'
        }

        if ($item.State) {
            $state = $item.State
        }
        else {
            $state = Get-Message 'UnknownState'
        }

        if ($item.Version) {
            $version = (Get-Message 'WslVersion') -f $item.Version
        }
        else {
            $version = Get-Message 'UnknownWslVersion'
        }

        Write-Host ('  {0}. {1}' -f ($i + 1), $item.DisplayName)

        if ($item.DisplayName -ine $item.WslName) {
            Write-Host ((Get-Message 'WslNameLabel') -f $item.WslName)
        }

        Write-Host ('     {0} / {1} / {2}' -f $terminal, $state, $version)
        Write-Host ((Get-Message 'VhdxLabel') -f $item.VhdxPath)
        Write-Host ((Get-Message 'SizeLabel') -f (Format-Bytes $item.SizeBytes))
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
            $inputValue = Read-Host (Get-Message 'SelectTargets')

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
                    Write-Host ((Get-Message 'NumberOutOfRange') -f $number)
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
                Write-Host ((Get-Message 'DistributionNotFound') -f $selector)
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

function Invoke-DiskPartCommands {
    param(
        [Parameter(Mandatory)]
        [string[]] $Commands,

        [AllowNull()]
        [string] $VhdxPath
    )

    $diskPartScript = Join-Path ([IO.Path]::GetTempPath()) ('wsl-diskpart-{0}.txt' -f ([Guid]::NewGuid().ToString('N')))

    try {
        $content = ($Commands -join [Environment]::NewLine) + [Environment]::NewLine
        [IO.File]::WriteAllText($diskPartScript, $content, (Get-DiskPartScriptEncoding))

        $nativeResult = Invoke-NativeCommandCapture -FilePath 'diskpart.exe' -ArgumentList @('/s', $diskPartScript)
        $outputParts = @()

        if (-not [string]::IsNullOrWhiteSpace($nativeResult.StandardOutput)) {
            $outputParts += [string] $nativeResult.StandardOutput
        }

        if (-not [string]::IsNullOrWhiteSpace($nativeResult.StandardError)) {
            $outputParts += [string] $nativeResult.StandardError
        }

        $output = ($outputParts -join [Environment]::NewLine).Trim()
        $errorText = $output

        if (-not [string]::IsNullOrWhiteSpace($VhdxPath)) {
            $errorText = $errorText.Replace($VhdxPath, '')
        }

        $hasError = $errorText -match '(?i)error|failed|failure|cannot|could not|not found|access is denied|エラー|失敗|見つかりません|アクセスが拒否'

        if ($hasError) {
            $message = Get-Message 'DiskPartReturnedError'
        }
        else {
            $message = (Get-Message 'ExitCode') -f $nativeResult.ExitCode
        }

        return [pscustomobject] @{
            Succeeded = ($nativeResult.ExitCode -eq 0 -and -not $hasError)
            Message   = $message
            Output    = $output
        }
    }
    catch {
        return [pscustomobject] @{
            Succeeded = $false
            Message   = Get-Message 'DiskPartInvokeFailed'
            Output    = ''
        }
    }
    finally {
        if (Test-Path -LiteralPath $diskPartScript) {
            Remove-Item -LiteralPath $diskPartScript -Force -ErrorAction SilentlyContinue
        }
    }
}

function Get-VhdmpEventValidation {
    param(
        [Parameter(Mandatory)]
        [string] $VhdxPath,

        [Parameter(Mandatory)]
        [datetime] $StartTime
    )

    $logName = 'Microsoft-Windows-VHDMP-Operational'
    $result = [pscustomobject] @{
        QuerySucceeded = $false
        AttachSuccess  = $false
        CompactSuccess = $false
        DetachSuccess  = $false
    }

    try {
        Get-WinEvent -ListLog $logName -ErrorAction Stop | Out-Null
    }
    catch {
        return $result
    }

    try {
        $events = @(
            Get-WinEvent -FilterHashtable @{
                LogName   = $logName
                Id        = @(1, 2, 51)
                StartTime = $StartTime
                EndTime   = (Get-Date)
            } -ErrorAction Stop |
                Where-Object { $_.Message -like ('*{0}*' -f $VhdxPath) }
        )

        $result.QuerySucceeded = $true
        $result.AttachSuccess = @($events | Where-Object { $_.Id -eq 1 }).Count -gt 0
        $result.CompactSuccess = @($events | Where-Object { $_.Id -eq 51 }).Count -gt 0
        $result.DetachSuccess = @($events | Where-Object { $_.Id -eq 2 }).Count -gt 0
    }
    catch {
        if ($_.Exception.Message -match '(?i)no events were found|イベントが見つかりません') {
            $result.QuerySucceeded = $true
        }
    }

    return $result
}

function Invoke-DiskPartDetachBestEffort {
    param(
        [Parameter(Mandatory)]
        [string] $VhdxPath
    )

    $selectCommand = 'select vdisk file="{0}"' -f $VhdxPath

    return Invoke-DiskPartCommands -Commands @(
        $selectCommand
        'detach vdisk noerr'
        'exit'
    ) -VhdxPath $VhdxPath
}

function Invoke-DiskPartCompact {
    param(
        [Parameter(Mandatory)]
        [string] $VhdxPath
    )

    $selectCommand = 'select vdisk file="{0}"' -f $VhdxPath

    $commands = @(
        $selectCommand
        'attach vdisk readonly'
        'compact vdisk'
        'detach vdisk'
        'exit'
    )

    $lastResult = [pscustomobject] @{
        Succeeded = $false
        Message   = Get-Message 'DiskPartCouldNotExecute'
        Output    = ''
    }

    for ($attempt = 1; $attempt -le $DiskPartMaxAttempts; $attempt++) {
        if ($attempt -gt 1) {
            Write-Host ((Get-Message 'Retry') -f $attempt, $DiskPartMaxAttempts)
            Start-Sleep -Seconds $DiskPartScriptWaitSeconds
        }

        $startedAt = Get-Date
        $diskPartResult = Invoke-DiskPartCommands -Commands $commands -VhdxPath $VhdxPath
        $eventValidation = Get-VhdmpEventValidation -VhdxPath $VhdxPath -StartTime $startedAt

        if ($eventValidation.QuerySucceeded) {
            if ($eventValidation.AttachSuccess -and $eventValidation.CompactSuccess -and $eventValidation.DetachSuccess) {
                return [pscustomobject] @{
                    Succeeded = $true
                    Message   = Get-Message 'CompactConfirmed'
                    Output    = $diskPartResult.Output
                }
            }

            $missing = @()

            if (-not $eventValidation.AttachSuccess) {
                $missing += Get-Message 'AttachSuccessEvent'
            }

            if (-not $eventValidation.CompactSuccess) {
                $missing += Get-Message 'CompactSuccessEvent'
            }

            if (-not $eventValidation.DetachSuccess) {
                $missing += Get-Message 'DetachSuccessEvent'
            }

            if ($diskPartResult.Succeeded) {
                $message = (Get-Message 'CompletionUnconfirmed') -f ($missing -join (Get-Message 'ListSeparator'))
            }
            else {
                $message = (Get-Message 'DiskPartExecutionFailed') -f $diskPartResult.Message, ($missing -join (Get-Message 'ListSeparator'))
            }

            $lastResult = [pscustomobject] @{
                Succeeded = $false
                Message   = $message
                Output    = $diskPartResult.Output
            }
        }
        elseif ($diskPartResult.Succeeded) {
            return [pscustomobject] @{
                Succeeded = $true
                Message   = Get-Message 'EventLogUnavailable'
                Output    = $diskPartResult.Output
            }
        }
        else {
            $lastResult = $diskPartResult
        }

        $cleanupNeeded = -not $eventValidation.QuerySucceeded -or $eventValidation.AttachSuccess

        if ($attempt -lt $DiskPartMaxAttempts -and $cleanupNeeded) {
            Start-Sleep -Seconds $DiskPartScriptWaitSeconds
            Invoke-DiskPartDetachBestEffort -VhdxPath $VhdxPath | Out-Null
        }
    }

    return $lastResult
}

$distroCount = if ($null -eq $Distro) { 0 } else { $Distro.Count }

if (
    ($All -and $distroCount -gt 0) -or
    ($List -and ($All -or $distroCount -gt 0))
) {
    throw (Get-Message 'InvalidParameters')
}

if (
    -not $List -and
    -not $DryRun -and
    -not $NoElevation -and
    -not (Test-Administrator)
) {
    exit (Start-ElevatedSelf)
}

Write-Host (Get-Message 'Title')
Write-Host (Get-Message 'Subtitle')
Write-Host ''

$items = @(Get-WslDistributions)

if ($items.Count -eq 0) {
    Write-Host (Get-Message 'NoTargets')
    exit 1
}

Show-Distributions $items

if ($List) {
    exit 0
}

$selected = @(Resolve-Selection -Items $items -Selectors @($Distro) -SelectAll:$All)

if ($selected.Count -eq 0) {
    Write-Host (Get-Message 'Canceled')
    exit 0
}

Write-Host (Get-Message 'ExecutionTargets')
$selected | ForEach-Object {
    Write-Host ((Get-Message 'ExecutionTargetItem') -f $_.DisplayName, $_.VhdxPath)
}

if ($DryRun) {
    Write-Host (Get-Message 'DryRun')
    exit 0
}

if (-not (Test-Administrator)) {
    Write-Error (Get-Message 'AdminRequired')
    exit 1
}

Write-Host ''
Write-Host (Get-Message 'StopWarning')

if (-not $Yes) {
    $answer = Read-Host (Get-Message 'RunPrompt')

    if ($answer -notmatch '^(?i:y|yes)$') {
        Write-Host (Get-Message 'Canceled')
        exit 0
    }
}

Write-Host (Get-Message 'ShuttingDown')
$shutdownOutput = (& wsl.exe --shutdown 2>&1 | Out-String).Trim()

if ($LASTEXITCODE -ne 0) {
    Write-Error ((Get-Message 'ShutdownFailed') -f $LASTEXITCODE)

    exit 1
}

Write-Host ((Get-Message 'ShutdownCompleted') -f $DiskPartScriptWaitSeconds)
Start-Sleep -Seconds $DiskPartScriptWaitSeconds

$failed = 0
$processedCount = 0

foreach ($item in $selected) {
    if ($processedCount -gt 0) {
        Write-Host ((Get-Message 'PreviousDiskPartWait') -f $DiskPartScriptWaitSeconds)
        Start-Sleep -Seconds $DiskPartScriptWaitSeconds
    }

    $processedCount++
    Write-Host ('[{0}] {1}' -f $item.DisplayName, (Get-Message 'Compressing'))

    try {
        $before = (Get-Item -LiteralPath $item.VhdxPath -ErrorAction Stop).Length
    }
    catch {
        $failed++
        Write-Error (Get-Message 'BeforeReadFailed')
        continue
    }

    try {
        $result = Invoke-DiskPartCompact -VhdxPath $item.VhdxPath
    }
    catch {
        $result = [pscustomobject] @{
            Succeeded = $false
            Message   = Get-Message 'UnexpectedCompactionFailure'
            Output    = ''
        }
    }

    if (-not $result.Succeeded) {
        $failed++
        Write-Error ((Get-Message 'Failed') -f $result.Message)
        Write-Error (Get-Message 'NativeDetails')

        continue
    }

    try {
        $after = (Get-Item -LiteralPath $item.VhdxPath -ErrorAction Stop).Length
    }
    catch {
        $failed++
        Write-Error (Get-Message 'AfterReadFailed')
        continue
    }

    if (-not [string]::IsNullOrWhiteSpace($result.Message)) {
        Write-Host ((Get-Message 'Verified') -f $result.Message)
    }

    Write-Host (Get-Message 'Completed')
    Write-Host ((Get-Message 'SizeChange') -f (Format-Bytes $before), (Format-Bytes $after))
}

if ($failed -gt 0) {
    Write-Error ((Get-Message 'SummaryFailed') -f $selected.Count, $failed)
    exit 1
}

Write-Host (Get-Message 'AllSucceeded')
exit 0
