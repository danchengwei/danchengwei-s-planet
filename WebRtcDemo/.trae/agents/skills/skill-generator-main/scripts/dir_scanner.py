#### 2.3 Trae专属脚本适配（核心修改）
##### （1）dir_scanner.py（适配Trae路径规则）
import os
import json
import argparse

def scan_project_modules(project_root, module_root, skip_dirs):
    """Trae专属：扫描Android项目模块目录"""
    # 扫描项目根目录下的实际业务模块
    modules = []
    
    # 1. 扫描项目根目录下的主要业务模块
    for dir_name in os.listdir(project_root):
        dir_path = os.path.join(project_root, dir_name)
        if os.path.isdir(dir_path) and dir_name not in skip_dirs and not dir_name.startswith("."):
            # 检查是否是业务模块目录
            if is_business_module(dir_path):
                # Trae Skill目录名仅支持小写+短横线
                module_name = dir_name.lower().replace('_', '-')
                modules.append(module_name)
    
    # 2. 扫描指定的module_root目录（如果存在）
    if module_root:
        full_module_root = os.path.join(project_root, module_root)
        if os.path.exists(full_module_root):
            for dir_name in os.listdir(full_module_root):
                dir_path = os.path.join(full_module_root, dir_name)
                if os.path.isdir(dir_path) and dir_name not in skip_dirs and not dir_name.startswith("."):
                    module_name = dir_name.lower().replace('_', '-')
                    if module_name not in modules:
                        modules.append(module_name)
    
    # 3. 如果没有识别到模块，添加git仓库作为默认模块
    if not modules:
        # 获取git仓库名称作为模块名
        git_module_name = get_git_repo_name(project_root)
        modules.append(git_module_name)
    
    return modules

def is_business_module(dir_path):
    """判断是否是业务模块目录"""
    dir_name = os.path.basename(dir_path)
    # 常见的业务模块目录
    business_dirs = ['app', 'src', 'main', 'java', 'kotlin', 'signaling-server', 'server', 'client']
    # 检查是否包含业务相关文件
    has_business_files = any(
        os.path.exists(os.path.join(dir_path, file_name))
        for file_name in ['build.gradle', 'package.json', 'pom.xml', 'AndroidManifest.xml']
    )
    return dir_name in business_dirs or has_business_files

def get_git_repo_name(project_root):
    """获取git仓库名称"""
    # 从git remote获取仓库名称
    import subprocess
    try:
        result = subprocess.run(
            ['git', 'remote', '-v'],
            cwd=project_root,
            capture_output=True,
            text=True
        )
        if result.returncode == 0:
            for line in result.stdout.split('\n'):
                if 'origin' in line:
                    # 提取仓库名称
                    repo_url = line.split('\t')[1].split(' ')[0]
                    repo_name = repo_url.split('/')[-1].replace('.git', '')
                    return repo_name.lower().replace('_', '-')
    except Exception:
        pass
    
    # 如果无法获取git仓库名称，使用项目目录名
    return os.path.basename(project_root).lower().replace('_', '-')

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Trae模块扫描")
    parser.add_argument("--project_root", required=True, help="Trae项目根路径（绝对路径）")
    parser.add_argument("--module_root", required=True, help="模块相对路径")
    parser.add_argument("--skip_dirs", required=True, help="跳过目录（逗号分隔）")
    parser.add_argument("--output", required=True, help="输出JSON路径")
    
    args = parser.parse_args()
    skip_dirs = args.skip_dirs.split(",")
    
    try:
        modules = scan_project_modules(args.project_root, args.module_root, skip_dirs)
        with open(args.output, "w", encoding="utf-8") as f:
            json.dump(modules, f, ensure_ascii=False, indent=2)
        # Trae终端输出日志（Trae会在控制台显示）
        print(f"[Trae Skill生成器] 扫描完成：识别{len(modules)}个模块")
    except Exception as e:
        print(f"[Trae Skill生成器] 扫描失败：{str(e)}")
        with open(args.output, "w", encoding="utf-8") as f:
            json.dump([], f)
        exit(1)