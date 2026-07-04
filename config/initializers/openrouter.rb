# Load per-task OpenRouter model config into config.x.openrouter (see config/openrouter.yml).
Rails.application.config.x.openrouter =
  YAML.safe_load_file(Rails.root.join("config/openrouter.yml")).freeze
