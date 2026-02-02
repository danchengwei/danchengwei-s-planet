{
  "knowledge_base": {
    "version": "project_v1.0",
    "modules": [
      {
        "module_name": "{{ module_name }}",
        "kb_path": "knowledge-base/project_v1.0/module-{{ module_name }}",
        "priority": 1
      }
    ],
    "mapping_rules": [
      {
        "pattern": "{{ module_name }}.*",
        "module": "{{ module_name }}",
        "confidence": 0.9
      },
      {
        "pattern": ".*{{ module_name }}.*",
        "module": "{{ module_name }}",
        "confidence": 0.7
      }
    ]
  }
}