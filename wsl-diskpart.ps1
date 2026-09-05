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
$VhdmpEventWaitSeconds = 30
$VhdmpEventPollMilliseconds = 500

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
        Write-Verbose 'Could not read the Windows user interface language from the native API.'
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
            Write-Verbose 'Could not read the cached Windows user interface language.'
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
            Write-Verbose 'Could not read the Windows user language list.'
        }
    }

    if ([string]::IsNullOrWhiteSpace($cultureName)) {
        try {
            $cultureName = [string] ((Get-UICulture).Name)
        }
        catch {
            Write-Verbose 'Could not read the PowerShell UI culture.'
        }
    }

    if ([string]::IsNullOrWhiteSpace($cultureName)) {
        try {
            $cultureName = [string] ([Globalization.CultureInfo]::CurrentUICulture.Name)
        }
        catch {
            Write-Verbose 'Could not read the current UI culture.'
        }
    }

    if ([string]::IsNullOrWhiteSpace($cultureName)) {
        try {
            $cultureName = [string] ([Globalization.CultureInfo]::InstalledUICulture.Name)
        }
        catch {
            Write-Verbose 'Could not read the installed UI culture.'
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
        AllSkipsUnregistered           = '  -All skips unregistered VHDX files. Select one explicitly by number or name to process it.'
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
        EventLogUnavailable           = 'DiskPart exited with code 0, but the VHDMP event log was unavailable, so completion could not be verified.'
        DetachUnconfirmed             = 'DiskPart detach completion could not be confirmed.'
        DetachCleanupFailed           = 'Best-effort VHDX detach failed: {0}'
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
        AllSkipsUnregistered           = '  -Allでは未登録VHDXを処理しません。処理する場合は番号または名前で明示的に選択してください。'
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
        EventLogUnavailable           = 'DiskPartは終了コード0を返しましたが、VHDMPイベントログを利用できないため完了を確認できませんでした。'
        DetachUnconfirmed             = 'DiskPartによる切り離し完了を確認できませんでした。'
        DetachCleanupFailed           = 'VHDXの切り離し再試行に失敗しました: {0}'
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

function ConvertTo-ProcessArgument {
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
    $started = $false

    try {
        if (-not (Test-NoReparsePointPath -Path ([IO.Path]::GetTempPath()))) {
            throw 'The temporary directory is a reparse point or could not be validated.'
        }

        $argumentString = @(
            $ArgumentList |
                Where-Object { $null -ne $_ } |
                ForEach-Object { ConvertTo-ProcessArgument ([string] $_) }
        ) -join ' '

        $process = Start-Process `
            -FilePath $FilePath `
            -ArgumentList $argumentString `
            -NoNewWindow `
            -Wait `
            -PassThru `
            -RedirectStandardOutput $stdoutPath `
            -RedirectStandardError $stderrPath
        $started = $true

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
            Started        = $started
        }
    }
    catch {
        return [pscustomobject] @{
            ExitCode       = 1
            StandardOutput = ''
            StandardError  = $_.Exception.Message
            Started        = $started
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
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([int])]
    param()

    if ([string]::IsNullOrWhiteSpace($PSCommandPath)) {
        throw (Get-Message 'ScriptPathMissing')
    }

    $hostPath = $null

    try {
        $hostPath = (Get-Process -Id $PID -ErrorAction Stop).Path
    }
    catch {
        Write-Verbose 'Could not determine the current host process path.'
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

    $distroArguments = @($Distro | Where-Object { $null -ne $_ })

    if ($distroArguments.Count -gt 0) {
        $rawArguments += @('-Distro', ($distroArguments -join ','))
    }

    $argumentString = ($rawArguments | ForEach-Object {
        ConvertTo-ProcessArgument ([string] $_)
    }) -join ' '

    try {
        if (-not $PSCmdlet.ShouldProcess($hostPath, 'Relaunch the script as administrator')) {
            return 0
        }

        $child = Start-Process -FilePath $hostPath -ArgumentList $argumentString -Verb RunAs -Wait -PassThru
        return $child.ExitCode
    }
    catch [System.ComponentModel.Win32Exception] {
        if ($_.Exception.NativeErrorCode -eq 1223) {
            Write-Error -Message (Get-Message 'ElevationCanceled') -ErrorAction Continue
        }
        else {
            Write-Error -Message ((Get-Message 'ElevationFailedWin32') -f $_.Exception.NativeErrorCode) -ErrorAction Continue
        }

        return 1
    }
    catch {
        Write-Error -Message (Get-Message 'ElevationFailed') -ErrorAction Continue
        return 1
    }
}

function ConvertTo-NormalizedIdentifier {
    param(
        [AllowNull()]
        [string] $Value
    )

    if ($null -eq $Value) {
        return ''
    }

    return (($Value -replace '[{}-]', '').ToUpperInvariant())
}

function ConvertTo-NormalizedPath {
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

function Test-NoReparsePointPath {
    param(
        [Parameter(Mandatory)]
        [string] $Path
    )

    try {
        $current = Get-Item -LiteralPath $Path -Force -ErrorAction Stop
        $reparsePoint = [IO.FileAttributes]::ReparsePoint

        while ($null -ne $current) {
            if (($current.Attributes -band $reparsePoint) -ne 0) {
                return $false
            }

            $parent = if ($current -is [IO.FileInfo]) { $current.Directory } else { $current.Parent }

            if ($null -eq $parent -or [string]::Equals($parent.FullName, $current.FullName, [StringComparison]::OrdinalIgnoreCase)) {
                break
            }

            $current = $parent
        }

        return $true
    }
    catch {
        Write-Verbose ('Could not validate the path for reparse points: {0}' -f $Path)
        return $false
    }
}

function Test-SafeVhdxPath {
    param(
        [Parameter(Mandatory)]
        [string] $Path
    )

    if ($Path -notmatch '^[A-Za-z]:\\' -or $Path -match '[\x00-\x1f"]' -or
        $Path.Substring(2).Contains(':') -or [IO.Path]::GetExtension($Path) -ine '.vhdx') {
        return $false
    }

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return $false
    }

    return Test-NoReparsePointPath -Path $Path
}

function Get-FileIdentity {
    param(
        [Parameter(Mandatory)]
        [IO.FileStream] $Stream
    )

    if (-not ('WslDiskPart.NativeFileIdentity' -as [type])) {
        [void] (Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;

namespace WslDiskPart {
    [StructLayout(LayoutKind.Sequential)]
    public struct ByHandleFileInformation {
        public uint FileAttributes;
        public System.Runtime.InteropServices.ComTypes.FILETIME CreationTime;
        public System.Runtime.InteropServices.ComTypes.FILETIME LastAccessTime;
        public System.Runtime.InteropServices.ComTypes.FILETIME LastWriteTime;
        public uint VolumeSerialNumber;
        public uint FileSizeHigh;
        public uint FileSizeLow;
        public uint NumberOfLinks;
        public uint FileIndexHigh;
        public uint FileIndexLow;
    }

    public static class NativeFileIdentity {
        [DllImport("kernel32.dll", SetLastError = true)]
        public static extern bool GetFileInformationByHandle(
            IntPtr handle,
            out ByHandleFileInformation information);
    }
}
'@)
    }

    $information = New-Object 'WslDiskPart.ByHandleFileInformation'
    $handle = $Stream.SafeFileHandle.DangerousGetHandle()

    if (-not [WslDiskPart.NativeFileIdentity]::GetFileInformationByHandle($handle, [ref] $information)) {
        throw 'Could not read the file identity.'
    }

    return '{0:X8}:{1:X8}:{2:X8}' -f `
        $information.VolumeSerialNumber, `
        $information.FileIndexHigh, `
        $information.FileIndexLow
}

function Get-FileIdentityAtPath {
    param(
        [Parameter(Mandatory)]
        [string] $Path
    )

    $stream = $null

    try {
        $stream = [IO.File]::Open(
            $Path,
            [IO.FileMode]::Open,
            [IO.FileAccess]::Read,
            ([IO.FileShare]::ReadWrite -bor [IO.FileShare]::Delete)
        )

        return Get-FileIdentity -Stream $stream
    }
    catch {
        Write-Verbose ('Could not read the file identity: {0}' -f $Path)
        return $null
    }
    finally {
        if ($null -ne $stream) {
            $stream.Dispose()
        }
    }
}

function Open-VhdxLease {
    param(
        [Parameter(Mandatory)]
        [string] $Path,

        [AllowNull()]
        [string] $ExpectedIdentity
    )

    if (-not (Test-SafeVhdxPath -Path $Path)) {
        throw 'The VHDX path is not a regular, non-reparse .vhdx file.'
    }

    $stream = $null

    try {
        # Deny delete/rename while DiskPart resolves the same path. ReadWrite
        # sharing still allows DiskPart to open the VHDX for compaction.
        $stream = [IO.File]::Open(
            $Path,
            [IO.FileMode]::Open,
            [IO.FileAccess]::Read,
            [IO.FileShare]::ReadWrite
        )
        $identity = Get-FileIdentity -Stream $stream

        if (-not [string]::IsNullOrWhiteSpace($ExpectedIdentity) -and $identity -ne $ExpectedIdentity) {
            throw 'The VHDX file identity changed after target discovery.'
        }

        return [pscustomobject] @{
            Identity = $identity
            Length   = $stream.Length
            Stream   = $stream
        }
    }
    catch {
        if ($null -ne $stream) {
            $stream.Dispose()
        }

        throw
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
            if ((ConvertTo-NormalizedIdentifier $directory.Name) -eq (ConvertTo-NormalizedIdentifier $RegistryId)) {
                $candidates += Join-Path $directory.FullName 'ext4.vhdx'
            }
        }
    }

    foreach ($candidate in @($candidates | Select-Object -Unique)) {
        $path = ConvertTo-NormalizedPath $candidate

        if ($null -ne $path -and (Test-SafeVhdxPath -Path $path)) {
            return $path
        }
    }

    return $null
}

function ConvertTo-JsonComment {
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

function ConvertTo-TrailingJsonComma {
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

function Get-TerminalProfile {
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
            $jsonText = ConvertTo-JsonComment $jsonText
            $jsonText = ConvertTo-TrailingJsonComma $jsonText
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

            foreach ($terminalProfileEntry in $entries) {
                $name = [string] $terminalProfileEntry.name

                if ([string]::IsNullOrWhiteSpace($name)) {
                    continue
                }

                $item = [pscustomobject] @{
                    Name        = $name
                    Guid        = [string] $terminalProfileEntry.guid
                    Source      = [string] $terminalProfileEntry.source
                    CommandLine = [string] $terminalProfileEntry.commandline
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
            Write-Verbose ('Could not parse Windows Terminal settings: {0}' -f $path)
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

function Get-WslStatus {
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

function Get-WslDistribution {
    $registryRoot = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Lxss'
    $profiles = @(Get-TerminalProfile)
    $statuses = @(Get-WslStatus)
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

                $basePath = ConvertTo-NormalizedPath ([string] $properties.BasePath)
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
                            (ConvertTo-NormalizedIdentifier $_.Guid) -eq (ConvertTo-NormalizedIdentifier $key.PSChildName)
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

                $file = Get-Item -LiteralPath $vhdxPath -Force -ErrorAction Stop
                $fileIdentity = Get-FileIdentityAtPath -Path $vhdxPath
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
                    FileIdentity = $fileIdentity
                    Unknown      = $false
                }

                $knownPaths[$vhdxPath.ToLowerInvariant()] = $true
            }
            catch {
                Write-Verbose ('Skipping WSL registry entry: {0}' -f $key.PSChildName)
            }
        }
    }

    $wslRoot = Join-Path ([Environment]::GetFolderPath([Environment+SpecialFolder]::LocalApplicationData)) 'wsl'

    if (Test-Path -LiteralPath $wslRoot -PathType Container) {
        foreach ($file in @(Get-ChildItem -LiteralPath $wslRoot -Filter 'ext4.vhdx' -File -Recurse -ErrorAction SilentlyContinue)) {
            $vhdxPath = ConvertTo-NormalizedPath $file.FullName

            if ($null -eq $vhdxPath -or -not (Test-SafeVhdxPath -Path $vhdxPath)) {
                continue
            }

            if ($knownPaths.ContainsKey($vhdxPath.ToLowerInvariant())) {
                continue
            }

            $folder = Split-Path $vhdxPath -Parent | Split-Path -Leaf
            $unregisteredName = (Get-Message 'UnregisteredVhdx') -f $folder
            $fileIdentity = Get-FileIdentityAtPath -Path $vhdxPath

            $items += [pscustomobject] @{
                WslName      = $unregisteredName
                DisplayName  = $unregisteredName
                TerminalName = $null
                VhdxPath     = $vhdxPath
                SizeBytes    = [int64] $file.Length
                Version      = 2
                State        = $null
                RegistryId   = $folder
                FileIdentity = $fileIdentity
                Unknown      = $true
            }
        }
    }

    return @($items | Sort-Object DisplayName)
}

function Format-Byte {
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

function Show-Distribution {
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
        Write-Host ((Get-Message 'SizeLabel') -f (Format-Byte $item.SizeBytes))
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
        $unregistered = @($Items | Where-Object { $_.Unknown })

        if ($unregistered.Count -gt 0) {
            Write-Host (Get-Message 'AllSkipsUnregistered')
        }

        return @($Items | Where-Object { -not $_.Unknown })
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
                return @(Resolve-Selection -Items $Items -Selectors @() -SelectAll)
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

            $nameMatches = @(
                $Items |
                    Where-Object {
                        $_.DisplayName -ieq $selector -or $_.WslName -ieq $selector
                    }
            )

            if ($nameMatches.Count -eq 0) {
                Write-Host ((Get-Message 'DistributionNotFound') -f $selector)
                $valid = $false
                break
            }

            $selected += $nameMatches
        }

        if ($valid) {
            return @($selected | Sort-Object VhdxPath -Unique)
        }

        $expanded = @()
    }
}

function Invoke-DiskPartCommand {
    param(
        [Parameter(Mandatory)]
        [string[]] $Commands,

        [AllowNull()]
        [string] $VhdxPath
    )

    $diskPartScript = Join-Path ([IO.Path]::GetTempPath()) ('wsl-diskpart-{0}.txt' -f ([Guid]::NewGuid().ToString('N')))
    $diskPartScriptStream = $null
    $started = $false

    try {
        if (-not (Test-NoReparsePointPath -Path ([IO.Path]::GetTempPath()))) {
            throw 'The temporary directory is a reparse point or could not be validated.'
        }

        $content = ($Commands -join [Environment]::NewLine) + [Environment]::NewLine
        $encoding = Get-DiskPartScriptEncoding
        $diskPartScriptStream = [IO.File]::Open(
            $diskPartScript,
            [IO.FileMode]::CreateNew,
            [IO.FileAccess]::ReadWrite,
            [IO.FileShare]::Read
        )
        $bytes = $encoding.GetBytes($content)
        $diskPartScriptStream.Write($bytes, 0, $bytes.Length)
        $diskPartScriptStream.Flush($true)
        $diskPartScriptStream.Dispose()
        # Hold only read access so DiskPart can use its normal read sharing.
        # Verify the exact bytes under this lock after reopening.
        $diskPartScriptStream = [IO.File]::Open($diskPartScript, 'Open', 'Read', 'Read')
        $verifiedBytes = New-Object byte[] $bytes.Length
        $readCount = $diskPartScriptStream.Read($verifiedBytes, 0, $verifiedBytes.Length)
        if ($readCount -ne $bytes.Length -or $diskPartScriptStream.Length -ne $bytes.Length -or
            [Convert]::ToBase64String($verifiedBytes) -cne [Convert]::ToBase64String($bytes)) {
            throw 'The temporary DiskPart script changed before execution.'
        }

        $nativeResult = Invoke-NativeCommandCapture -FilePath 'diskpart.exe' -ArgumentList @('/s', $diskPartScript)
        $started = [bool] $nativeResult.Started
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
            Started   = $started
        }
    }
    catch {
        Write-Verbose $_.Exception.Message
        return [pscustomobject] @{
            Succeeded = $false
            Message   = Get-Message 'DiskPartInvokeFailed'
            Output    = ''
            Started   = $started
        }
    }
    finally {
        if ($null -ne $diskPartScriptStream) {
            $diskPartScriptStream.Dispose()
        }

        try {
            if ([IO.File]::Exists($diskPartScript)) {
                [IO.File]::Delete($diskPartScript)
            }
        }
        catch {
            Write-Verbose ('Could not remove the temporary DiskPart script: {0}' -f $diskPartScript)
        }
    }
}

function Get-VhdmpEventPropertyValue {
    param(
        [Parameter(Mandatory)]
        [object] $EventRecord,

        [Parameter(Mandatory)]
        [int] $Index
    )

    if ($null -eq $EventRecord.Properties -or $EventRecord.Properties.Count -le $Index) {
        return $null
    }

    return [string] $EventRecord.Properties[$Index].Value
}

function Get-VhdmpEventPath {
    param(
        [Parameter(Mandatory)]
        [object] $EventRecord
    )

    $pathIndex = if ($EventRecord.Id -eq 51) { 1 } else { 0 }
    return Get-VhdmpEventPropertyValue -EventRecord $EventRecord -Index $pathIndex
}

function Get-VhdmpEventOperation {
    param(
        [Parameter(Mandatory)]
        [object] $EventRecord
    )

    if ($EventRecord.Id -ne 51) {
        return $null
    }

    return Get-VhdmpEventPropertyValue -EventRecord $EventRecord -Index 0
}

function Test-VhdmpEventSuccess {
    param(
        [Parameter(Mandatory)]
        [object] $EventRecord
    )

    return (Get-VhdmpEventPropertyValue -EventRecord $EventRecord -Index 2) -eq '0'
}

function Get-VhdmpEventValidation {
    param(
        [Parameter(Mandatory)]
        [string] $VhdxPath,

        [Parameter(Mandatory)]
        [datetime] $StartTime,

        [switch] $DetachOnly
    )

    $logName = 'Microsoft-Windows-VHDMP-Operational'
    $eventIds = if ($DetachOnly) { @(2) } else { @(1, 2, 51) }
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

    $deadline = (Get-Date).AddSeconds([Math]::Max(0, $VhdmpEventWaitSeconds))

    do {
        $result.QuerySucceeded = $false
        $result.AttachSuccess = $false
        $result.CompactSuccess = $false
        $result.DetachSuccess = $false

        try {
            $events = @(
                Get-WinEvent -FilterHashtable @{
                    LogName   = $logName
                    Id        = $eventIds
                    StartTime = $StartTime
                    EndTime   = (Get-Date)
                } -ErrorAction Stop |
                    Where-Object {
                        $eventPath = Get-VhdmpEventPath -EventRecord $_
                        [string]::Equals($eventPath, $VhdxPath, [StringComparison]::OrdinalIgnoreCase) -and
                            (Test-VhdmpEventSuccess -EventRecord $_)
                    } |
                    Sort-Object RecordId
            )

            $result.QuerySucceeded = $true
        }
        catch {
            if ($_.FullyQualifiedErrorId -like 'NoMatchingEventsFound,*') {
                $result.QuerySucceeded = $true
                $events = @()
            }
            else {
                return $result
            }
        }

        if ($DetachOnly) {
            $result.DetachSuccess = @($events | Where-Object { $_.Id -eq 2 }).Count -gt 0

            if ($result.DetachSuccess) {
                return $result
            }
        }
        else {
            $attachEvent = $events | Where-Object { $_.Id -eq 1 } | Select-Object -First 1

            if ($null -ne $attachEvent) {
                $result.AttachSuccess = $true
                $compactEvent = $events |
                    Where-Object {
                        $_.Id -eq 51 -and
                        $_.RecordId -gt $attachEvent.RecordId -and
                        (Get-VhdmpEventOperation -EventRecord $_) -ieq 'Compact'
                    } |
                    Select-Object -First 1

                if ($null -ne $compactEvent) {
                    $result.CompactSuccess = $true
                    $detachEvent = $events |
                        Where-Object { $_.Id -eq 2 -and $_.RecordId -gt $compactEvent.RecordId } |
                        Select-Object -First 1

                    if ($null -ne $detachEvent) {
                        $result.DetachSuccess = $true
                        return $result
                    }
                }
            }
        }

        if ((Get-Date) -ge $deadline) {
            break
        }

        Start-Sleep -Milliseconds $VhdmpEventPollMilliseconds
    } while ($true)

    return $result
}

function Invoke-DiskPartDetachBestEffort {
    param(
        [Parameter(Mandatory)]
        [string] $VhdxPath
    )

    $selectCommand = 'select vdisk file="{0}"' -f $VhdxPath
    $startedAt = Get-Date
    $diskPartResult = Invoke-DiskPartCommand -Commands @(
        $selectCommand
        'detach vdisk noerr'
        'exit'
    ) -VhdxPath $VhdxPath
    $eventValidation = Get-VhdmpEventValidation -VhdxPath $VhdxPath -StartTime $startedAt -DetachOnly

    if ($diskPartResult.Succeeded -and $eventValidation.QuerySucceeded -and $eventValidation.DetachSuccess) {
        return $diskPartResult
    }

    if (-not $diskPartResult.Succeeded) {
        return $diskPartResult
    }

    return [pscustomobject] @{
        Succeeded = $false
        Message   = Get-Message 'DetachUnconfirmed'
        Output    = $diskPartResult.Output
    }
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
        $stopRetrying = $false
        $startedAt = Get-Date
        $diskPartResult = Invoke-DiskPartCommand -Commands $commands -VhdxPath $VhdxPath
        $eventValidation = Get-VhdmpEventValidation -VhdxPath $VhdxPath -StartTime $startedAt

        if ($eventValidation.QuerySucceeded) {
            if ($diskPartResult.Started -and $diskPartResult.Succeeded -and $eventValidation.AttachSuccess -and $eventValidation.CompactSuccess -and $eventValidation.DetachSuccess) {
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
            $lastResult = [pscustomobject] @{
                Succeeded = $false
                Message   = Get-Message 'EventLogUnavailable'
                Output    = $diskPartResult.Output
            }
            $stopRetrying = $true
        }
        else {
            $lastResult = $diskPartResult
        }

        $cleanupNeeded = $diskPartResult.Started -and (
            -not $eventValidation.QuerySucceeded -or -not $eventValidation.DetachSuccess
        )
        $willRetry = $attempt -lt $DiskPartMaxAttempts -and -not $stopRetrying

        if ($willRetry) {
            Write-Host ((Get-Message 'Retry') -f ($attempt + 1), $DiskPartMaxAttempts)
        }

        if ($cleanupNeeded -or $willRetry) {
            Start-Sleep -Seconds $DiskPartScriptWaitSeconds
        }

        if ($cleanupNeeded) {
            $cleanupResult = Invoke-DiskPartDetachBestEffort -VhdxPath $VhdxPath

            if (-not $cleanupResult.Succeeded) {
                $lastResult.Message = '{0} {1}' -f $lastResult.Message, ((Get-Message 'DetachCleanupFailed') -f $cleanupResult.Message)
                $stopRetrying = $true
            }
        }

        if ($stopRetrying) {
            break
        }
    }

    return $lastResult
}

if ($MyInvocation.InvocationName -eq '.') { return }

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

$items = @(Get-WslDistribution)

if ($items.Count -eq 0) {
    Write-Host (Get-Message 'NoTargets')
    exit 1
}

Show-Distribution $items

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
    Write-Error -Message (Get-Message 'AdminRequired') -ErrorAction Continue
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
    if (-not [string]::IsNullOrWhiteSpace($shutdownOutput)) {
        Write-Error -Message $shutdownOutput -ErrorAction Continue
    }
    Write-Error -Message ((Get-Message 'ShutdownFailed') -f $LASTEXITCODE) -ErrorAction Continue

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

    $vhdxLease = $null
    try {
        if ([string]::IsNullOrWhiteSpace($item.FileIdentity)) {
            throw 'The target file identity could not be established during discovery.'
        }
        $vhdxLease = Open-VhdxLease -Path $item.VhdxPath -ExpectedIdentity $item.FileIdentity
        $before = $vhdxLease.Length
    }
    catch {
        $failed++
        Write-Error -Message (Get-Message 'BeforeReadFailed') -ErrorAction Continue
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
    finally {
        if ($null -ne $vhdxLease) { $vhdxLease.Stream.Dispose() }
    }

    if (-not $result.Succeeded) {
        $failed++
        Write-Error -Message ((Get-Message 'Failed') -f $result.Message) -ErrorAction Continue
        Write-Error -Message (Get-Message 'NativeDetails') -ErrorAction Continue

        continue
    }

    try {
        $afterLease = Open-VhdxLease -Path $item.VhdxPath -ExpectedIdentity $item.FileIdentity
        try { $after = $afterLease.Length }
        finally { $afterLease.Stream.Dispose() }
    }
    catch {
        $failed++
        Write-Error -Message (Get-Message 'AfterReadFailed') -ErrorAction Continue
        continue
    }

    if (-not [string]::IsNullOrWhiteSpace($result.Message)) {
        Write-Host ((Get-Message 'Verified') -f $result.Message)
    }

    Write-Host (Get-Message 'Completed')
    Write-Host ((Get-Message 'SizeChange') -f (Format-Byte $before), (Format-Byte $after))
}

if ($failed -gt 0) {
    Write-Error -Message ((Get-Message 'SummaryFailed') -f $selected.Count, $failed) -ErrorAction Continue
    exit 1
}

Write-Host (Get-Message 'AllSucceeded')
exit 0
