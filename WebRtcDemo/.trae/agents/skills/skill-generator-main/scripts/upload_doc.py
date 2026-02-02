import sys
import os

def upload_doc(file_path, module, category):
    # 核心逻辑：读取文件并写入知识库目录
    kb_dir = f"knowledge-base/project_v1.0/module-{module}/{category}/"
    os.makedirs(kb_dir, exist_ok=True)
    file_name = os.path.basename(file_path)
    with open(file_path, "r", encoding="utf-8") as f:
        content = f.read()
    with open(f"{kb_dir}/{file_name}", "w", encoding="utf-8") as f:
        f.write(content)
    print(f"✅ 文档上传成功：{kb_dir}/{file_name}")

if __name__ == "__main__":
    upload_doc(sys.argv[1], sys.argv[2], sys.argv[3])