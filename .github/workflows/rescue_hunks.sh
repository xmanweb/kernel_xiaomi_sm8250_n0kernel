#!/bin/bash
# =====================================================================
#  终极救援脚本: 精准修复 Umi 内核 4.19 补丁应用失败的 SUSFS Hunks
# =====================================================================

set -e # 遇到错误立即退出

echo "🚀 开始修复 Umi 内核的 SUSFS 冲突..."

# ---------------------------------------------------------------------
# 1. 修复 fs/open.c
# ---------------------------------------------------------------------
FILE_OPEN="fs/open.c"
if [ -f "$FILE_OPEN" ]; then
    echo "📝 正在修复: $FILE_OPEN"
    
    # 【核心修正】使用 Hunk #2 专有的、且目前由于失败绝对不存在的特征函数名作为判断条件
    if ! grep -q "fake_filename = susfs_open_redirect_spoof_do_sys_openat" "$FILE_OPEN"; then
        
        # 1. 注入 retry: 标签
        # 在 fd = get_unused_fd_flags(flags); 之后换行插入 retry 逻辑
        sed -i '/fd = get_unused_fd_flags(flags);/a \
#ifdef CONFIG_KSU_SUSFS_OPEN_REDIRECT\nretry:\n#endif \/\/ #ifdef CONFIG_KSU_SUSFS_OPEN_REDIRECT' "$FILE_OPEN"

        # 2. 注入 open_redirect 的核心判断和劫持逻辑
        # 在 struct file *f = do_filp_open(dfd, tmp, &op); 之后换行插入判断
        sed -i '/struct file \*f = do_filp_open(dfd, tmp, &op);/a \
#ifdef CONFIG_KSU_SUSFS_OPEN_REDIRECT\n\t\tif (!is_inode_open_redirect && f && !IS_ERR(f)) {\n\t\t\tstruct inode *inode = file_inode(f);\n\t\t\tif (SUSFS_IS_INODE_OPEN_REDIRECT_WITHOUT_UID_CHECK(inode)) {\n\t\t\t\tfake_filename = susfs_open_redirect_spoof_do_sys_openat(inode);\n\t\t\t\tif (fake_filename && !IS_ERR(fake_filename)) {\n\t\t\t\t\tis_inode_open_redirect = true;\n\t\t\t\t\tfilp_close(f, NULL);\n\t\t\t\t\tputname(tmp);\n\t\t\t\t\ttmp = fake_filename;\n\t\t\t\t\tgoto retry;\n\t\t\t\t}\n\t\t\t}\n\t\t}\n#endif \/\/ #ifdef CONFIG_KSU_SUSFS_OPEN_REDIRECT' "$FILE_OPEN"
        
        echo "✅ $FILE_OPEN 的 Hunk #2 核心劫持逻辑强制注入成功。"
    else
        echo "⏭️ $FILE_OPEN 已经包含 Hunk #2 劫持逻辑，跳过。"
    fi
else
    echo "❌ 找不到文件: $FILE_OPEN" && exit 1
fi

# ---------------------------------------------------------------------
# 适配 SUSFS 核心扩展：精准修补 fs/proc/task_mmu.c
# ---------------------------------------------------------------------
FILE_TASK_MMU="fs/proc/task_mmu.c"

if [ -f "$FILE_TASK_MMU" ]; then
    echo "📝 正在全新注入 $FILE_TASK_MMU 对应的标准多模块挂钩逻辑..."

    # 1. 严格对齐官方多宏合并规范，在 #include <linux/shmem_fs.h> 后面注入完整的头文件保护块
    sed -i '/#include <linux\/shmem_fs.h>/a #if defined(CONFIG_KSU_SUSFS_SUS_KSTAT) || defined(CONFIG_KSU_SUSFS_SUS_MAP) || defined(CONFIG_KSU_SUSFS_OPEN_REDIRECT)\n#include <linux/susfs_def.h>\n#endif' "$FILE_TASK_MMU"

    # 2. 核心逻辑注入：直接全字匹配替换 4.19 的原生 walk_page_range 行
    sed -i 's/ret = walk_page_range(mm, start_vaddr, end, \&pagemap_ops, \&pm);/#ifdef CONFIG_KSU_SUSFS_SUS_MAP\n\t\t{\n\t\t\tstruct vm_area_struct *vma = find_vma(mm, start_vaddr);\n\t\t\tif (vma \&\& vma->vm_file \&\& SUSFS_IS_INODE_SUS_MAP(file_inode(vma->vm_file)))\n\t\t\t\tgoto bypass_orig_flow;\n\t\t}\n#endif\n\t\tret = walk_page_range(mm, start_vaddr, end, \&pagemap_ops, \&pm);\n#ifdef CONFIG_KSU_SUSFS_SUS_MAP\nbypass_orig_flow:\n#endif/g' "$FILE_TASK_MMU"

    # 3. 独一无二的局部变量声明特征验证
    if grep -q "struct vm_area_struct \*vma = find_vma" "$FILE_TASK_MMU"; then
        echo "✅ $FILE_TASK_MMU 头文件（多宏并列版）与核心劫持逻辑合入成功！"
    else
        echo "❌ $FILE_TASK_MMU 补丁合入踏空，请检查源码特征行是否匹配！"
    fi
fi

echo "🎉 所有补丁冲突已完美修复！"
