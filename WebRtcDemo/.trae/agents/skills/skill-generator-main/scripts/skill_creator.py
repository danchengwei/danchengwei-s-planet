import os
import jinja2
import json

def generate_skill(module, template_dir, output_dir):
    """
    根据模块信息生成子Skill
    :param module: 模块信息
    :param template_dir: 模板目录
    :param output_dir: 输出目录
    """
    # 创建模块对应的Skill目录
    skill_dir = os.path.join(output_dir, f"skill-{module['name']}")
    os.makedirs(skill_dir, exist_ok=True)
    
    # 初始化Jinja2环境
    env = jinja2.Environment(
        loader=jinja2.FileSystemLoader(template_dir),
        autoescape=False
    )
    
    # 渲染skill.json模板
    skill_json_template = env.get_template("skill.json.tpl")
    skill_json_content = skill_json_template.render(
        module_name=module['name'],
        module_path=module['path'],
        files=module['files']
    )
    with open(os.path.join(skill_dir, "skill.json"), "w", encoding="utf-8") as f:
        f.write(skill_json_content)
    
    # 渲染workflow.md模板
    workflow_template = env.get_template("workflow.md.tpl")
    workflow_content = workflow_template.render(
        module_name=module['name'],
        module_path=module['path'],
        files=module['files']
    )
    with open(os.path.join(skill_dir, "workflow.md"), "w", encoding="utf-8") as f:
        f.write(workflow_content)
    
    # 渲染kb_mapping.json模板
    kb_mapping_template = env.get_template("kb_mapping.json.tpl")
    kb_mapping_content = kb_mapping_template.render(
        module_name=module['name']
    )
    with open(os.path.join(skill_dir, "kb_mapping.json"), "w", encoding="utf-8") as f:
        f.write(kb_mapping_content)
    
    print(f"生成子Skill: {skill_dir}")

def generate_skills(modules, template_dir, output_dir):
    """
    批量生成子Skill
    :param modules: 模块列表
    :param template_dir: 模板目录
    :param output_dir: 输出目录
    """
    for module in modules:
        generate_skill(module, template_dir, output_dir)
    
    print(f"共生成 {len(modules)} 个子Skill")

if __name__ == "__main__":
    # 测试生成功能
    import dir_scanner
    
    # 获取项目根路径（上四级目录）
    script_dir = os.path.dirname(os.path.abspath(__file__))
    skill_generator_dir = os.path.dirname(script_dir)
    agents_skills_dir = os.path.dirname(skill_generator_dir)
    agents_dir = os.path.dirname(agents_skills_dir)
    trae_dir = os.path.dirname(agents_dir)
    project_root = os.path.dirname(trae_dir)
    
    template_dir = os.path.join(skill_generator_dir, "templates")
    output_dir = os.path.join(agents_skills_dir)  # 输出到skills目录
    
    # 配置参数
    module_root = "app/src/main/java/com/example/webrtctest/"
    skip_dirs = [".git", "venv", "build", "test"]
    
    print(f"项目根路径: {project_root}")
    print(f"模块根路径: {module_root}")
    
    # 扫描模块
    try:
        module_names = dir_scanner.scan_project_modules(project_root, module_root, skip_dirs)
        print(f"扫描到的模块: {module_names}")
        
        # 转换为模块对象列表
        modules = []
        for module_name in module_names:
            # 移除 "module-" 前缀
            clean_name = module_name.replace("module-", "")
            module_path = os.path.join(project_root, module_root, clean_name)
            
            # 获取模块中的文件
            files = []
            if os.path.exists(module_path):
                for file in os.listdir(module_path):
                    if os.path.isfile(os.path.join(module_path, file)):
                        files.append(file)
            
            modules.append({
                "name": clean_name,
                "path": module_path,
                "files": files
            })
        
        print(f"模块对象: {modules}")
        
        # 生成Skill
        generate_skills(modules, template_dir, output_dir)
    except Exception as e:
        print(f"错误: {e}")
        import traceback
        traceback.print_exc()