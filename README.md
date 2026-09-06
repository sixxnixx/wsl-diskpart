# WSL VHDX Compactor / WSL VHDX コンパクター

[English](#english) · [日本語](#日本語)

## English

### Overview

WSL VHDX Compactor is a PowerShell utility for compacting WSL 2 virtual hard disk files (`ext4.vhdx`) with Windows DiskPart.

The utility detects available WSL 2 VHDX files, lets you choose one or more targets, shuts down WSL, runs DiskPart, and verifies that the operation completed successfully.

> **Warning:** The utility stops all WSL distributions and modifies VHDX files. Back up important environments before running it.

### Requirements

- Windows with WSL 2 installed.
- PowerShell 5.1 or later.
- Windows DiskPart.
- Administrator privileges for compaction. The utility requests elevation through UAC when needed.

`-List` and `-DryRun` only inspect and display targets. They do not shut down WSL or modify VHDX files.

### Quick start

Open PowerShell in the project directory and run:

```powershell
.\wsl-diskpart.cmd
```

The wrapper automatically uses `pwsh.exe` when it is available and otherwise uses Windows PowerShell.

To run the PowerShell script directly, use a process-scoped execution-policy override if your current policy blocks scripts:

```powershell
Set-ExecutionPolicy -Scope Process Bypass
.\wsl-diskpart.ps1
```

The utility displays the detected targets and then asks you to select the targets to process. It asks for confirmation before shutting down WSL. When administrator privileges are required, Windows displays a UAC prompt.

### Select targets

When no target option is supplied, select targets interactively at the prompt:

- Enter a number such as `1`.
- Enter multiple numbers separated by commas, such as `1,3`.
- Enter a Windows Terminal display name or a WSL distribution name, such as `Ubuntu-26.04`.
- Enter `A` to select all registered targets.
- Enter `Q` to cancel.

Registered WSL 2 VHDX files are shown with their distribution information. Additional local `ext4.vhdx` files that are not registered with WSL may also be shown as `Unregistered VHDX`.

`-All` and interactive `A` select registered targets only. Select an unregistered VHDX explicitly by its number or displayed name if you are certain that it is the intended file. Only local, regular `.vhdx` files are eligible.

### Command-line options

Use one target selector: interactive selection, `-Distro`, or `-All`. Do not combine `-List`, `-Distro`, and `-All`.

| Option | Description |
| --- | --- |
| *(none)* | Display targets and select them interactively. |
| `-List` | Display detected targets and exit without changing anything. |
| `-Distro <target>` | Process the specified distribution name or target number. Use commas for multiple targets, for example `-Distro 1,3`. |
| `-All` | Process all registered targets. Unregistered VHDX files are excluded. |
| `-DryRun` | Display the selected targets without shutting down WSL or changing any files. |
| `-Yes` | Skip the final confirmation prompt. WSL is still shut down when processing starts. |

Examples:

```powershell
# Display detected targets only
.\wsl-diskpart.ps1 -List

# Process one distribution by name
.\wsl-diskpart.ps1 -Distro Ubuntu-26.04

# Process targets 1 and 3
.\wsl-diskpart.ps1 -Distro 1,3

# Preview all registered targets
.\wsl-diskpart.ps1 -All -DryRun

# Process all registered targets without the final prompt
.\wsl-diskpart.ps1 -All -Yes
```

### What happens during processing

During processing, the utility:

1. Stops all WSL distributions once with `wsl.exe --shutdown`.
2. Waits for WSL to release the VHDX.
3. For each selected target, attaches the VHDX as read-only with DiskPart.
4. Runs `compact vdisk`.
5. Detaches the VHDX.
6. Confirms the attach, compact, and detach operations using the VHDMP event log.
7. Reports the VHDX size before and after processing.

If a VHDX is temporarily in use, the utility waits and retries the operation up to three times. Processing multiple targets also includes a wait between targets.

### Notes and troubleshooting

- `wsl.exe --shutdown` stops every running WSL distribution, not only the selected one.
- Close applications that can use or restart WSL, including Docker Desktop, Windows Terminal WSL tabs, IDE integrations, and file-management tools that have the VHDX open.
- VHDX files are modified during compaction. Keep a backup of important environments.
- A successful compaction does not guarantee a smaller file. The size may remain unchanged when the guest filesystem has not released unused blocks or there is little reclaimable space.
- If the file size does not decrease, remove unnecessary data inside the distribution and, when supported by the guest filesystem, run `sudo fstrim -av` before trying again.
- If processing fails, review the displayed DiskPart output and the `Microsoft-Windows-VHDMP/Operational` event log, then close remaining WSL clients and retry.

---

## 日本語

### 概要

WSL VHDX コンパクターは、WindowsのDiskPartを使用してWSL 2の仮想ハードディスクファイル（`ext4.vhdx`）を圧縮するPowerShellユーティリティです。

利用可能なWSL 2のVHDXファイルを検出し、処理する対象を1つ以上選択すると、WSLを停止してDiskPartを実行し、処理が正常に完了したことを確認します。

> **警告:** このユーティリティは、すべてのWSLディストロを停止し、VHDXファイルを変更します。実行前に重要な環境をバックアップしてください。

### 必要条件

- WSL 2がインストールされたWindows。
- PowerShell 5.1以降。
- WindowsのDiskPart。
- 圧縮処理に必要な管理者権限。必要な場合はUACを通じて昇格を要求します。

`-List`と`-DryRun`は対象の確認と表示だけを行います。WSLの停止やVHDXファイルの変更は行いません。

### はじめに

PowerShellでプロジェクトフォルダに移動し、次を実行します。

```powershell
.\wsl-diskpart.cmd
```

このラッパーは、`pwsh.exe`が利用可能な場合はそれを使用し、利用できない場合はWindows PowerShellを使用します。

PowerShellの実行ポリシーによってスクリプトの実行がブロックされる場合は、プロセス単位で実行ポリシーを変更して、PowerShellスクリプトを直接実行できます。

```powershell
Set-ExecutionPolicy -Scope Process Bypass
.\wsl-diskpart.ps1
```

ユーティリティは検出した対象を表示し、処理する対象を選択するよう求めます。WSLを停止する前に確認を求めます。管理者権限が必要な場合は、WindowsがUACの確認画面を表示します。

### 対象の選択

対象オプションを指定しない場合は、プロンプトで対話的に対象を選択します。

- `1`のように番号を入力する。
- `1,3`のようにカンマで区切って複数の番号を入力する。
- `Ubuntu-26.04`のように、Windows Terminalの表示名またはWSLディストロ名を入力する。
- `A`を入力して、登録済みの対象をすべて選択する。
- `Q`を入力してキャンセルする。

登録済みのWSL 2 VHDXファイルは、ディストロ情報とともに表示されます。WSLに登録されていないローカルの`ext4.vhdx`ファイルが、`Unregistered VHDX`として表示される場合もあります。

`-All`と対話選択の`A`では、登録済みの対象だけを選択します。未登録VHDXを処理する場合は、意図したファイルであることを確認したうえで、番号または表示名で明示的に選択してください。対象になるのは、ローカルにある通常の`.vhdx`ファイルだけです。

### コマンドラインオプション

対象の指定方法は、対話選択、`-Distro`、`-All`のいずれか1つを使用します。`-List`、`-Distro`、`-All`は同時に指定できません。

| オプション | 説明 |
| --- | --- |
| （なし） | 対象を表示し、対話的に選択する。 |
| `-List` | 検出した対象を表示して終了する。変更は行わない。 |
| `-Distro <target>` | 指定したディストロ名または対象番号を処理する。複数の場合は`-Distro 1,3`のようにカンマで区切る。 |
| `-All` | 登録済みの対象をすべて処理する。未登録VHDXは除外する。 |
| `-DryRun` | WSLを停止したりファイルを変更したりせず、選択した対象だけを表示する。 |
| `-Yes` | 最終確認を省略する。処理を開始するとWSLは停止する。 |

使用例:

```powershell
# 検出した対象だけを表示
.\wsl-diskpart.ps1 -List

# 名前で1つのディストロを処理
.\wsl-diskpart.ps1 -Distro Ubuntu-26.04

# 1番と3番の対象を処理
.\wsl-diskpart.ps1 -Distro 1,3

# 登録済みの全対象を事前確認
.\wsl-diskpart.ps1 -All -DryRun

# 最終確認なしで登録済みの全対象を処理
.\wsl-diskpart.ps1 -All -Yes
```

### 処理の流れ

処理中、ユーティリティは次の処理を行います。

1. `wsl.exe --shutdown`を1回実行して、すべてのWSLディストロを停止する。
2. WSLがVHDXを解放するまで待機する。
3. 選択した対象ごとに、DiskPartでVHDXを読み取り専用としてアタッチする。
4. `compact vdisk`を実行する。
5. VHDXをデタッチする。
6. VHDMPイベントログを使って、アタッチ、圧縮、デタッチの完了を確認する。
7. 処理前後のVHDXサイズを表示する。

VHDXが一時的に使用中の場合は、解放を待って最大3回まで処理を再試行します。複数の対象を処理する場合も、対象ごとに待機時間を入れます。

### 注意事項とトラブルシューティング

- `wsl.exe --shutdown`は、選択したディストロだけでなく、実行中のすべてのWSLディストロを停止します。
- Docker Desktop、Windows TerminalのWSLタブ、IDEのWSL連携、VHDXを開いているファイル管理ツールなど、WSLを使用または再起動する可能性があるアプリを終了してください。
- 圧縮処理中にVHDXファイルが変更されるため、重要な環境のバックアップを保管してください。
- 圧縮が成功しても、ファイルサイズが小さくなるとは限りません。ゲストファイルシステムが未使用ブロックを解放していない場合や、回収できる領域が少ない場合は、サイズが変わらないことがあります。
- ファイルサイズが小さくならない場合は、ディストロ内で不要なデータを削除し、ゲストファイルシステムが対応していれば、再実行前に`sudo fstrim -av`を実行してください。
- 処理に失敗した場合は、表示されたDiskPartの出力と`Microsoft-Windows-VHDMP/Operational`イベントログを確認し、残っているWSLクライアントを終了してから再実行してください。
