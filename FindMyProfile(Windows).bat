@echo off
chcp 65001 >nul 2>&1
setlocal enabledelayedexpansion

echo ============================================================
echo  Light Damage - Data Migration / 数据迁移 (Windows)
echo  LDCombatStats → LightDamage
echo ============================================================
echo.

set "WTF="

for %%P in (
    "C:\Program Files (x86)\World of Warcraft\_retail_\WTF"
    "C:\Program Files\World of Warcraft\_retail_\WTF"
    "D:\World of Warcraft\_retail_\WTF"
    "E:\World of Warcraft\_retail_\WTF"
    "D:\Games\World of Warcraft\_retail_\WTF"
    "E:\Games\World of Warcraft\_retail_\WTF"
    "C:\Games\World of Warcraft\_retail_\WTF"
) do (
    if exist "%%~P" (
        set "WTF=%%~P"
        goto :found
    )
)

echo WoW installation not found. / 未找到 WoW 安装目录。
echo Drag your WTF folder here, or type the path, then press Enter:
echo 请将 WTF 文件夹拖到此窗口，或手动输入路径，然后按回车：
set /p "WTF="
set "WTF=%WTF:"=%"
if not exist "%WTF%" (
    echo Invalid path, exiting. / 路径无效，退出。
    pause
    exit /b 1
)

:found
echo Found WTF folder / 找到 WTF 目录: %WTF%
echo.

set COUNT=0

for /d %%A in ("%WTF%\Account\*") do (
    if exist "%%A\SavedVariables\LDCombatStats.lua" (
        call :migrate "%%A\SavedVariables"
    )
    for /d %%S in ("%%A\*") do (
        for /d %%C in ("%%S\*") do (
            if exist "%%C\SavedVariables\LDCombatStats.lua" (
                call :migrate "%%C\SavedVariables"
            )
        )
    )
)

echo.
if %COUNT% gtr 0 (
    echo Done! Migrated %COUNT% file(s). / 迁移完成！共迁移 %COUNT% 个文件。
) else (
    echo No files to migrate (already done or no old data found).
    echo 没有需要迁移的文件（可能已迁移过，或未找到旧插件数据）。
)
echo.
echo You can now launch the game. / 现在可以启动游戏了。
echo.
pause
exit /b 0

:migrate
set "DIR=%~1"
set "OLD=%DIR%\LDCombatStats.lua"
set "NEW=%DIR%\LightDamage.lua"

for %%F in ("%OLD%") do if %%~zF equ 0 goto :eof

if exist "%NEW%" (
    for %%F in ("%NEW%") do (
        if %%~zF gtr 100 (
            findstr /c:"LightDamageGlobal" "%NEW%" >nul 2>&1
            if !errorlevel! equ 0 (
                echo Skipped (data exists) / 跳过 (已有数据): %NEW%
                goto :eof
            )
        )
    )
    copy /y "%NEW%" "%NEW%.bak" >nul 2>&1
)

powershell -NoProfile -Command ^
    "(Get-Content -Path '%OLD%' -Raw -Encoding UTF8) -replace 'LDCombatStatsGlobal','LightDamageGlobal' -replace 'LDCombatStatsDB','LightDamageDB' | Set-Content -Path '%NEW%' -Encoding UTF8"

if !errorlevel! equ 0 (
    echo Migrated / 迁移成功: %OLD%
    echo          -^> %NEW%
    set /a COUNT+=1
) else (
    echo Migration failed / 迁移失败: %OLD%
)
goto :eof
