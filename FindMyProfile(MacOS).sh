#!/bin/bash
# ============================================================
# Light Damage - SavedVariables Migration / 数据迁移脚本 (macOS)
# LDCombatStats → LightDamage
# ============================================================

echo "============================================================"
echo " Light Damage - Data Migration / 数据迁移"
echo " LDCombatStats → LightDamage"
echo "============================================================"
echo ""

WOW_PATHS=(
    "/Applications/World of Warcraft/_retail_"
    "$HOME/Applications/World of Warcraft/_retail_"
)

WTF=""
for p in "${WOW_PATHS[@]}"; do
    if [ -d "$p/WTF" ]; then
        WTF="$p/WTF"
        break
    fi
done

if [ -z "$WTF" ]; then
    echo "❌ WoW installation not found / 未找到 WoW 安装目录"
    echo "   Please enter the full path to your _retail_ folder:"
    echo "   请输入 _retail_ 文件夹的完整路径："
    read -r INPUT
    if [ -d "$INPUT/WTF" ]; then
        WTF="$INPUT/WTF"
    elif [ -d "$INPUT" ] && [[ "$INPUT" == */WTF ]]; then
        WTF="$INPUT"
    else
        echo "❌ Invalid path, exiting / 路径无效，退出"
        exit 1
    fi
fi

echo "✅ WTF folder found / 找到 WTF 目录: $WTF"
echo ""

COUNTFILE=$(mktemp)
echo 0 > "$COUNTFILE"

migrate_file() {
    local old_file="$1"
    local dir
    dir=$(dirname "$old_file")
    local new_file="$dir/LightDamage.lua"

    if [ ! -s "$old_file" ]; then
        return
    fi

    if [ -f "$new_file" ] && [ -s "$new_file" ]; then
        local size
        size=$(wc -c < "$new_file" | tr -d ' ')
        if [ "$size" -gt 100 ] && grep -q "LightDamageGlobal" "$new_file" 2>/dev/null; then
            echo "⏭  Skipped (data exists) / 跳过 (已有数据): $new_file"
            return
        fi
    fi

    if [ -f "$new_file" ]; then
        cp "$new_file" "$new_file.bak"
    fi

    sed \
        -e 's/LDCombatStatsGlobal/LightDamageGlobal/g' \
        -e 's/LDCombatStatsDB/LightDamageDB/g' \
        "$old_file" > "$new_file"

    echo "✅ Migrated / 迁移成功: $old_file"
    echo "   → $new_file"
    local c
    c=$(cat "$COUNTFILE")
    echo $((c + 1)) > "$COUNTFILE"
}

find "$WTF/Account" -name "LDCombatStats.lua" -path "*/SavedVariables/*" 2>/dev/null | while read -r f; do
    migrate_file "$f"
done

COUNT=$(cat "$COUNTFILE")
rm -f "$COUNTFILE"

echo ""
if [ "$COUNT" -gt 0 ]; then
    echo "🎉 Done! Migrated $COUNT file(s). / 迁移完成！共迁移 $COUNT 个文件。"
else
    echo "ℹ️  No files to migrate (already done or no old data found)."
    echo "   没有需要迁移的文件（可能已迁移过，或未找到旧插件数据）。"
fi
echo ""
echo "   You can now launch the game. / 现在可以启动游戏了。"
