# WSL VHDX コンパクター

PowerShellで動作するCUIユーティリティです。WSLを停止し、対象ディストロのext4.vhdxに対してDiskPartのattach、compact、detachを順番に実行します。

## 実行方法

PowerShellでプロジェクトフォルダへ移動し、次のように実行します。

    Set-ExecutionPolicy -Scope Process Bypass
    .\wsl-diskpart.ps1

起動すると検出したWSLディストロとVHDXの場所を表示し、番号で対象を選択できます。管理者権限が必要な処理では、UACを経由して自動的に管理者として再起動します。

実行時の固定メッセージはOSのUI言語に合わせて切り替わります。日本語（`ja-*`）の場合は日本語、それ以外の場合は英語で表示します。ディストロ名やパスなどの識別情報はそのまま表示します。

    # 検出結果だけを表示
    .\wsl-diskpart.ps1 -List

    # すべての対象を処理
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

1. HKCU\Software\Microsoft\Windows\CurrentVersion\Lxss のWSL登録情報
2. レジストリのBasePathとVhdFileName
3. %LOCALAPPDATA%\wsl\<登録ID>\ext4.vhdx
4. %LOCALAPPDATA%\wsl 以下のext4.vhdx

表示名はWindows Terminalのsettings.jsonにあるprofiles.list[].nameと照合します。照合できない場合はWSLのDistributionNameを使用します。JSONCのコメントと末尾カンマにも対応しています。

レジストリに登録されていないVHDXは「未登録 VHDX」として表示します。

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

- wsl --shutdownにより、起動中のすべてのWSLディストロが停止します。
- Docker DesktopやWindows TerminalのWSLタブなど、WSLを使用するアプリは事前に終了してください。
- VHDXを変更するため、重要な環境では事前にバックアップを作成してください。
- DiskPartが失敗した場合は、対象ディストロの出力を確認してから再実行してください。
- 圧縮後もゲスト側で未使用領域が解放されていない場合などは、ファイルサイズが大きく変わらないことがあります。
