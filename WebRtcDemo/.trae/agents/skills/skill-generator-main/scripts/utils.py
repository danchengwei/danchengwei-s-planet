import os
import chardet
import argparse

def read_file_safely(file_path):
    """Trae专属：安全读取文件，适配Trae编码规则"""
    try:
        with open(file_path, "rb") as f:
            raw_data = f.read()
            encoding = chardet.detect(raw_data)["encoding"] or "utf-8"
        return raw_data.decode(encoding, errors="ignore")
    except Exception as e:
        raise Exception(f"读取失败：{file_path}，错误：{str(e)}")

def write_file_safely(file_path, content):
    """Trae专属：安全写入文件，自动创建Trae目录"""
    try:
        os.makedirs(os.path.dirname(file_path), exist_ok=True)
        with open(file_path, "w", encoding="utf-8") as f:
            f.write(content)
    except Exception as e:
        raise Exception(f"写入失败：{file_path}，错误：{str(e)}")

def refresh_trae_skills():
    """Trae专属：触发Skill列表刷新（Trae识别.refresh文件自动刷新）"""
    refresh_file = ".trae/agents/skills/.refresh"
    with open(refresh_file, "w") as f:
        f.write(str(os.time()))
    print("[Trae Skill生成器] 已刷新Skill列表，子Skill可立即使用")

if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--action", required=True, help="执行动作：refresh_skills")
    parser.add_argument("--ide_type", default="trae", help="IDE类型")
    
    args = parser.parse_args()
    if args.action == "refresh_skills" and args.ide_type == "trae":
        refresh_trae_skills()