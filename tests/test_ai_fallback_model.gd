extends "res://tests/test_case.gd"
## [AI_HELPER] When the chosen Ollama model is missing, Polox falls back to a model that can chat
## comfortably: not a coding model when a chat one is installed, and the smallest of those.
## Tags: [AI_HELPER]

const AIClientScript := preload("res://scripts/ai/ai_client.gd")


func test_a_missing_model_falls_back_to_a_small_chat_model() -> void:
	var installed := [
		{"name": "qwen3.6:35b-a3b-coding", "size_gb": 22.6},
		{"name": "devstral:24b", "size_gb": 14.0},
		{"name": "gemma-4:12b", "size_gb": 7.5},
		{"name": "llama3.2:3b", "size_gb": 2.0},
	]
	eq(AIClientScript.choose_model(installed, "gone:1b"), "llama3.2:3b", "the smallest chat model")
	eq(AIClientScript.choose_model(installed, "llama3.2:3b"), "gemma-4:12b", "never the missing one itself")
	eq(AIClientScript.choose_model([{"name": "devstral:24b", "size_gb": 14.0}, {"name": "gemma-4:12b", "size_gb": 7.5}], "x"), "gemma-4:12b", "avoids devstral coding model when a chat model exists")
	eq(AIClientScript.choose_model([{"name": "qwen3.6:35b-a3b-coding", "size": 22621314381}], "x"), "qwen3.6:35b-a3b-coding", "a coding model when it's all there is")
	eq(AIClientScript.choose_model([{"name": "nomic-embed-text:latest", "size_gb": 0.3}, {"name": "gemma-4:12b", "size_gb": 7.5}], "x"), "gemma-4:12b", "ignores embedding models")
	eq(AIClientScript.choose_model([], "x"), "", "none installed: none")
	var tagged := [{"name": "llama3.2:latest"}, {"name": "Gemma-4:12b"}]
	eq(AIClientScript._installed_ollama_model(tagged, "llama3.2"), "llama3.2:latest", "matches implicit :latest tag")
	eq(AIClientScript._installed_ollama_model(tagged, "gemma-4:12b"), "Gemma-4:12b", "matches case-insensitively")
	eq(AIClientScript._installed_ollama_model(tagged, "missing:1b"), "", "missing model returns empty")
