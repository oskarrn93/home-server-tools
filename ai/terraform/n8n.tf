variable "n8n_base_url" {
  description = "Base URL of the n8n instance's REST API."
  type        = string
  default     = "http://172.17.0.1:5678"
}

variable "n8n_api_key" {
  description = "n8n API key (Settings > n8n API > Create an API key). Set via TF_VAR_n8n_api_key."
  type        = string
  sensitive   = true
}

variable "pushover_api_token" {
  description = "Pushover application API token used by the n8n Pushover credential."
  type        = string
  sensitive   = true
}

variable "pushover_user_key" {
  description = "Pushover user key used by the n8n Pushover credential."
  type        = string
  sensitive   = true
}

provider "restapi" {
  uri                  = var.n8n_base_url
  write_returns_object = true
  id_attribute         = "id"
  headers = {
    "X-N8N-API-KEY" = var.n8n_api_key
    "Content-Type"  = "application/json"
  }
}

resource "restapi_object" "pushover_credential" {
  path = "/api/v1/credentials"
  data = jsonencode({
    name = "Pushover account"
    type = "pushoverApi"
    data = {
      apiKey = var.pushover_api_token
    }
  })

  # n8n never returns decrypted credential data on read, so ignore drift on it.
  ignore_changes_to       = ["data"]
  ignore_server_additions = true
}

locals {
  # The three *arr diskspace nodes share one fetch-and-map shape, so their code
  # lives in a single parameterized template (see workflows/disk-space-watchdog/)
  # rather than duplicated per node or inlined in the workflow JSON.
  disk_space_watchdog_fetch = "${path.module}/workflows/disk-space-watchdog/diskspace-fetch.js.tftpl"

  disk_space_watchdog_json = templatefile("${path.module}/workflows/disk-space-watchdog/workflow.json.tftpl", {
    sonarr_js = templatefile(local.disk_space_watchdog_fetch, {
      service  = "Sonarr"
      env_url  = "SONARR_URL"
      env_key  = "SONARR_API_KEY"
      api_path = "/api/v3/diskspace"
      label    = "hdd1"
    })
    radarr_js = templatefile(local.disk_space_watchdog_fetch, {
      service  = "Radarr"
      env_url  = "RADARR_URL"
      env_key  = "RADARR_API_KEY"
      api_path = "/api/v3/diskspace"
      label    = "hdd1"
    })
    readarr_js = templatefile(local.disk_space_watchdog_fetch, {
      service  = "Readarr"
      env_url  = "READARR_URL"
      env_key  = "READARR_API_KEY"
      api_path = "/api/v1/diskspace"
      label    = "hdd3"
    })
    evaluate_js = file("${path.module}/workflows/disk-space-watchdog/evaluate-thresholds.js")
  })

  workflow_json = {
    download_cleanup      = file("${path.module}/workflows/download-cleanup.json")
    seerr_request_digest  = file("${path.module}/workflows/seerr-request-digest.json")
    tautulli_watch_digest = file("${path.module}/workflows/tautulli-watch-digest.json")
    disk_space_watchdog   = local.disk_space_watchdog_json
  }
}

resource "restapi_object" "workflows" {
  for_each = local.workflow_json

  path = "/api/v1/workflows"
  data = replace(
    replace(
      each.value,
      "__PUSHOVER_CREDENTIAL_ID__",
      restapi_object.pushover_credential.id
    ),
    "__PUSHOVER_USER_KEY__",
    var.pushover_user_key
  )

  ignore_server_additions = true
  ignore_changes_to       = ["active", "createdAt", "updatedAt", "versionId", "tags", "shared"]
}
