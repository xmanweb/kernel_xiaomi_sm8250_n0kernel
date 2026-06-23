#!/bin/bash
# =====================================================================
#  救援脚本: 修复 Umi 内核 4.19 补丁应用失败的 SUSFS Hunks
# =====================================================================

set -e # 遇到错误立即退出

echo "🚀 开始修复 Umi 内核的 SUSFS 冲突..."

# ---------------------------------------------------------------------
# 1. 修复 fs/open.c
# ---------------------------------------------------------------------
FILE_OPEN="fs/open.c"
if [ -f "$FILE_OPEN" ]; then
    echo "📝 正在修复: $FILE_OPEN"
    
    # 检查是否已经应用过，防止重复注入
    if ! grep -q "retry:" "$FILE_OPEN"; then
        # 在 fd = get_unused_fd_flags(flags); 之后插入 retry 标签
        sed -i '/fd = get_unused_fd_flags(flags);/a \
#ifdef CONFIG_KSU_SUSFS_OPEN_REDIRECT\nretry:\n#endif \/\/ #ifdef CONFIG_KSU_SUSFS_OPEN_REDIRECT' "$FILE_OPEN"

        # 在 struct file *f = do_filp_open(dfd, tmp, &op); 之后插入 open_redirect 的核心判断逻辑
        sed -i '/struct file \*f = do_filp_open(dfd, tmp, &op);/a \
#ifdef CONFIG_KSU_SUSFS_OPEN_REDIRECT\n\t\tif (!is_inode_open_redirect && f && !IS_ERR(f)) {\n\t\t\tstruct inode *inode = file_inode(f);\n\t\t\tif (SUSFS_IS_INODE_OPEN_REDIRECT_WITHOUT_UID_CHECK(inode)) {\n\t\t\t\tfake_filename = susfs_open_redirect_spoof_do_sys_openat(inode);\n\t\t\t\tif (fake_filename && !IS_ERR(fake_filename)) {\n\t\t\t\t\tis_inode_open_redirect = true;\n\t\t\t\t\tfilp_close(f, NULL);\n\t\t\t\t\tputname(tmp);\n\t\t\t\t\ttmp = fake_filename;\n\t\t\t\t\tgoto retry;\n\t\t\t\t}\n\t\t\t}\n\t\t}\n#endif \/\/ #ifdef CONFIG_KSU_SUSFS_OPEN_REDIRECT' "$FILE_OPEN"
        echo "✅ $FILE_OPEN 修复成功。"
    else
        echo "⏭️ $FILE_OPEN 似乎已经修复过，跳过。"
    fi
else
    echo "❌ 找不到文件: $FILE_OPEN" && exit 1
fi

# ---------------------------------------------------------------------
# 2. 修复 fs/proc/task_mmu.c
# ---------------------------------------------------------------------
FILE_MMU="fs/proc/task_mmu.c"
if [ -f "$FILE_MMU" ]; then
    echo "📝 正在修复: $FILE_MMU"

    # Hunk #1: 头部添加头文件
    if ! grep -q "susfs_def.h" "$FILE_MMU"; then
        sed -i '/#include <linux\/ctype.h>/a \
#if defined(CONFIG_KSU_SUSFS_SUS_KSTAT) || defined(CONFIG_KSU_SUSFS_SUS_MAP) || defined(CONFIG_KSU_SUSFS_OPEN_REDIRECT)\n#include <linux/susfs_def.h>\n#endif \/\/ #if defined(CONFIG_KSU_SUSFS_SUS_KSTAT) || defined(CONFIG_KSU_SUSFS_SUS_MAP) || defined(CONFIG_KSU_SUSFS_OPEN_REDIRECT)' "$FILE_MMU"
        echo "  - 头文件添加成功"
    fi

    # Hunk #8: pagemap_read 逻辑注入
    if ! grep -q "goto bypass_orig_flow;" "$FILE_MMU"; then
        # 在 if (ret) goto out_free; 之后插入判断和跳转
        sed -i '/if (ret)/,/goto out_free;/ {
            /goto out_free;/a \
#ifdef CONFIG_KSU_SUSFS_SUS_MAP\n\t\tvma = find_vma(mm, start_vaddr);\n\t\tif (vma && vma->vm_file && SUSFS_IS_INODE_SUS_MAP(file_inode(vma->vm_file)))\n\t\t\tgoto bypass_orig_flow;\n#endif \/\/ #ifdef CONFIG_KSU_SUSFS_SUS_MAP
        }' "$FILE_MMU"

        # 在 walk_page_range 之后插入绕过标签
        sed -i '/ret = walk_page_range(start_vaddr, end, &pagemap_walk);/a \
#ifdef CONFIG_KSU_SUSFS_SUS_MAP\nbypass_orig_flow:\n#endif \/\/ #ifdef CONFIG_KSU_SUSFS_SUS_MAP' "$FILE_MMU"
        echo "  - pagemap_read 劫持逻辑修复成功"
    fi
    echo "✅ $FILE_MMU 修复成功。"
else
    echo "❌ 找不到文件: $FILE_MMU" && exit 1
fi

# ---------------------------------------------------------------------
# 清理废弃的临时残留文件
# ---------------------------------------------------------------------
echo "🧹 清理补丁错误残留文件 (.rej)..."
rm -f fs/open.c.rej fs/proc/task_mmu.c.rej

echo "🎉 所有补丁冲突已完美修复！你可以继续后续的编译流程了。"
