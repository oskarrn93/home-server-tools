terraform {
  required_version = ">= 1.16.0"

  required_providers {
    ollama = {
      source  = "kicc-akdb-de/ollama"
      version = "~> 0.1"
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

resource "ollama_model" "qwen3_vl" {
  name = "qwen3-vl:4b-thinking-q4_K_M"
}
