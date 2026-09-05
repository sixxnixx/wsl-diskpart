# WSL VHDX Compactor

A CUI utility that runs in PowerShell. It shuts down WSL and executes DiskPart's `attach`, `compact`, and `detach` commands in sequence for each target distribution's `ext4.vhdx`.

## Usage

Move to the project directory in PowerShell and run the following commands.

    Set-ExecutionPolicy -Scope Process Bypass
    .\wsl-diskpart.ps1

When launched, the utility displays detected WSL distributions and their VHDX locations, and lets you select targets by number. For operations that require administrator privileges, it automatically restarts as administrator through UAC.

Fixed runtime messages follow the OS UI language. Japanese (`ja-*`) displays Japanese; all other languages display English. Distribution names, paths, and other identifiers are left unchanged.

    # Display detected targets only
    .\wsl-diskpart.ps1 -List

    # Process all registered targets
    .\wsl-diskpart.ps1 -All

    # Specify a Windows Terminal display name or WSL name
    .\wsl-diskpart.ps1 -Distro Ubuntu

    # Specify multiple targets by number
    .\wsl-diskpart.ps1 -Distro 1,3

    # Check targets only without making changes
    .\wsl-diskpart.ps1 -All -DryRun

    # Skip the final confirmation
    .\wsl-diskpart.ps1 -All -Yes

## Distribution and VHDX Mapping

VHDX paths are searched in the following order.

1. WSL registration information under `HKCU\Software\Microsoft\Windows\CurrentVersion\Lxss`
2. `BasePath` and `VhdFileName` in the registry
3. `%LOCALAPPDATA%\wsl\<registration ID>\ext4.vhdx`
4. `ext4.vhdx` files under `%LOCALAPPDATA%\wsl`

Display names are matched against `profiles.list[].name` in Windows Terminal's `settings.json`. If no match is found, the WSL `DistributionName` is used. JSONC comments and trailing commas are supported.

VHDX files that are not registered in the registry are displayed as `Unregistered VHDX`. `-All` and interactive `A` exclude them; select them explicitly by number or name. Only local `.vhdx` files without reparse points are eligible. The utility verifies the discovered file identity again before processing.

## DiskPart Commands

After target confirmation, the utility creates a temporary script for each distribution and executes the following commands.

    wsl.exe --shutdown
    select vdisk file="<absolute path to ext4.vhdx>"
    attach vdisk readonly
    compact vdisk
    detach vdisk
    exit

All DiskPart commands for a target are executed in one script. The temporary script loaded with `/s` is generated using the system ANSI code page supported by DiskPart. The utility waits 15 seconds after shutting down WSL and between multiple distribution operations so that the VHDX can be released. If the file is in use, it retries up to three times and verifies attach, compact, and detach completion in the VHDMP event log.

## Notes

Development checks (no WSL shutdown or DiskPart execution):

    Invoke-ScriptAnalyzer -Path . -Recurse -Settings .\PSScriptAnalyzerSettings.psd1
    Invoke-Pester -Script .\tests\wsl-diskpart.Tests.ps1

The analyzer settings exclude only `PSAvoidUsingWriteHost`, because this utility intentionally uses host output for its interactive interface. The regression tests mock DiskPart and event queries; they do not replace an elevated compaction integration test.

- `wsl --shutdown` stops all running WSL distributions.
- Close applications that use WSL, such as Docker Desktop and WSL tabs in Windows Terminal, before running the utility.
- Back up important environments beforehand because the utility modifies VHDX files.
- If DiskPart fails, review the output for the target distribution before running the utility again.
- The file size may not change significantly if unused space has not been released inside the guest environment, for example.

# WSL VHDX コンパクター

PowerShellで動作するCUIユーティリティです。WSLを停止し、対象ディストロの`ext4.vhdx`に対してDiskPartの`attach`、`compact`、`detach`を順番に実行します。

## 実行方法

PowerShellでプロジェクトフォルダへ移動し、次のように実行します。

    Set-ExecutionPolicy -Scope Process Bypass
    .\wsl-diskpart.ps1

起動すると検出したWSLディストロとVHDXの場所を表示し、番号で対象を選択できます。管理者権限が必要な処理では、UACを経由して自動的に管理者として再起動します。

実行時の固定メッセージはOSのUI言語に合わせて切り替わります。日本語（`ja-*`）の場合は日本語、それ以外の場合は英語で表示します。ディストロ名やパスなどの識別情報はそのまま表示します。

    # 検出結果だけを表示
    .\wsl-diskpart.ps1 -List

    # 登録済みの対象をすべて処理
    .\wsl-diskpart.ps1 -All

    # Windows Terminalの表示名またはWSL名で指定
    .\wsl-diskpart.ps1 -Distro Ubuntu

    # 番号で複数指定
    .\wsl-diskpart.ps1 -Distro 1,3

    # 対象確認だけ行い、変更しない
    .\wsl-diskpart.ps1 -All -DryRun

    # 最終確認を省略
    .\wsl-diskpart.ps1 -All -Yes

## ディストロとVHDXの対応

VHDXのパスは次の順番で探索します。

1. `HKCU\Software\Microsoft\Windows\CurrentVersion\Lxss` のWSL登録情報
2. レジストリの`BasePath`と`VhdFileName`
3. `%LOCALAPPDATA%\wsl\<登録ID>\ext4.vhdx`
4. `%LOCALAPPDATA%\wsl` 以下の`ext4.vhdx`

表示名はWindows Terminalの`settings.json`にある`profiles.list[].name`と照合します。照合できない場合はWSLの`DistributionName`を使用します。JSONCのコメントと末尾カンマにも対応しています。

レジストリに登録されていないVHDXは「未登録 VHDX」として表示します。`-All`と対話選択の`A`からは除外するため、処理する場合は番号または名前で明示的に選択してください。対象はreparse pointを含まないローカルの`.vhdx`ファイルに限定し、処理前に検出時と同じファイルであることを再確認します。

## 実行するDiskPartコマンド

対象確認後、ディストロごとに一時スクリプトを作成して、次の処理を実行します。

    wsl.exe --shutdown
    select vdisk file="<ext4.vhdxの絶対パス>"
    attach vdisk readonly
    compact vdisk
    detach vdisk
    exit

DiskPartの各コマンドは1つのスクリプトで実行します。`/s`で読み込ませる一時スクリプトは、DiskPartが扱えるシステムANSIコードページで生成します。WSLの停止後と複数ディストロの処理間には、VHDXの解放を待つため15秒の待機を入れます。ファイルが使用中の場合は最大3回まで再試行し、VHDMPイベントログでアタッチ、圧縮、デタッチの完了を確認します。

## 注意事項

開発時の検証（WSL停止・DiskPart実行なし）:

    Invoke-ScriptAnalyzer -Path . -Recurse -Settings .\PSScriptAnalyzerSettings.psd1
    Invoke-Pester -Script .\tests\wsl-diskpart.Tests.ps1

静的解析では、対話画面の表示に使用する`PSAvoidUsingWriteHost`だけを設定で除外しています。回帰テストではDiskPartとイベント取得をモック化しているため、管理者権限での実圧縮の結合テストは別途必要です。

- `wsl --shutdown`により、起動中のすべてのWSLディストロが停止します。
- Docker DesktopやWindows TerminalのWSLタブなど、WSLを使用するアプリは事前に終了してください。
- VHDXを変更するため、重要な環境では事前にバックアップを作成してください。
- DiskPartが失敗した場合は、対象ディストロの出力を確認してから再実行してください。
- 圧縮後もゲスト側で未使用領域が解放されていない場合などは、ファイルサイズが大きく変わらないことがあります。
