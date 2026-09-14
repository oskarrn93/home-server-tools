terraform {
  required_version = ">= 1.16.0"

  backend "s3" {
    bucket       = "oskarrosen-terraform"
    key          = "home-server-tools/ai/terraform.tfstate"
    region       = "eu-north-1"
    encrypt      = true
    use_lockfile = true
  }

  required_providers {
    ollama = {
      source  = "kicc-akdb-de/ollama"
      version = "~> 0.1"
    }
    restapi = {
      source  = "Mastercard/restapi"
      version = "~> 3.0"
    }
  }
}

variable "ollama_host" {
  description = "Ollama API endpoint used by Terraform."
  type        = string
  default     = "http://localhost:11434"
}

provider "ollama" {
  host = var.ollama_host
}

# Local models litellm/config.yaml routes to (directly or as fallbacks for the
# desktop GPU host) - keep in sync with its `api_base: http://ollama:11434` entries.
resource "ollama_model" "qwen3_5_4b" {
  name = "qwen3.5:4b"
}

resource "ollama_model" "llava" {
  name = "llava:7b"
}

resource "ollama_model" "qwen2_5_3b_instruct" {
  name = "qwen2.5:3b-instruct"
}

resource "ollama_model" "nomic_embed_text_v2_moe" {
  name = "hf.co/nomic-ai/nomic-embed-text-v2-moe-GGUF:Q8_0"
}
