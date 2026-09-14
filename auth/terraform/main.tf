terraform {
  required_version = ">= 1.16.0"

  backend "s3" {
    bucket       = "oskarrosen-terraform"
    key          = "home-server-tools/auth/terraform.tfstate"
    region       = "eu-north-1"
    encrypt      = true
    use_lockfile = true
  }

  required_providers {
    restapi = {
      source  = "Mastercard/restapi"
      version = "~> 3.0"
    }
  }
}

variable "pocketid_base_url" {
  description = "Base URL of the Pocket ID API."
  type        = string
  default     = "https://oidc.oskarrosen.io/api"
}

variable "pocketid_api_key" {
  description = "Pocket ID API key (Settings > Admin > API Keys > Add API Key). Set via TF_VAR_pocketid_api_key."
  type        = string
  sensitive   = true
}

provider "restapi" {
  uri                  = var.pocketid_base_url
  write_returns_object = true
  id_attribute         = "id"
  headers = {
    "X-API-KEY"    = var.pocketid_api_key
    "Content-Type" = "application/json"
  }
}

# OIDC clients created here still need a secret generated once via the Pocket ID
# admin UI or API (POST /oidc/clients/{id}/secrets) - secrets are a separate,
# write-once sub-resource that Terraform doesn't manage.
locals {
  oidc_clients = {
    tinyauth = {
      id           = "e186c93c-44ba-489e-9cce-304c7a6e4d82"
      name         = "Tinyauth"
      callback_url = "https://auth.oskarrosen.io/api/oauth/callback/pocketid"
    }
    portainer = {
      id   = "6f3a9e2b-4c15-4a8d-9e6c-2a1f7b5d8c30"
      name = "Portainer"
      # Portainer's OAuth redirect is its own base URL, without a trailing
      # slash - matches the redirect_uri it actually sends (verified via
      # /api/settings/public's OAuthLoginURI), not a dedicated callback path.
      callback_url = "https://portainer.oskarrosen.io"
      # Portainer CE 2.45 doesn't implement PKCE for its OAuth client (verified
      # via strings on the portainer binary - no code_challenge support), so a
      # PKCE-required client here just makes Pocket ID reject its auth requests.
      pkce = false
    }
    litellm = {
      id           = "9d4c1a7e-3f28-4b6a-a1d5-6e0b2c9f4a17"
      name         = "LiteLLM"
      callback_url = "https://litellm.oskarrosen.io/sso/callback"
    }
    openwebui = {
      id           = "1b8e5f3a-7c94-4d21-8a6f-3d5c9e1b4a72"
      name         = "Open WebUI"
      callback_url = "https://openwebui.oskarrosen.io/oauth/oidc/callback"
    }
    grafana = {
      id           = "ce33fcb3-05cf-4f7e-a5ef-ddd29b05bbd0"
      name         = "Grafana"
      callback_url = "https://grafana.oskarrosen.io/login/generic_oauth"
    }
    pgadmin = {
      id           = "c54ae573-bd82-40f7-8a1f-1493c15d1ea3"
      name         = "pgAdmin"
      callback_url = "https://pgadmin.oskarrosen.io/oauth2/authorize"
    }
  }

  # Update DTO has no "id" field; only the create body needs it (and only when
  # a client is actually created rather than imported).
  oidc_client_settings = {
    for key, client in local.oidc_clients : key => {
      name                        = client.name
      callbackURLs                = [client.callback_url]
      isPublic                    = false
      pkceEnabled                 = try(client.pkce, true)
      isGroupRestricted           = true
      accessTokenDurationMinutes  = 60
      refreshTokenDurationMinutes = 43200
      skipConsent                 = true
    }
  }
}

resource "restapi_object" "oidc_clients" {
  for_each = local.oidc_clients

  path        = "/oidc/clients"
  data        = jsonencode(merge({ id = each.value.id }, local.oidc_client_settings[each.key]))
  update_data = jsonencode(local.oidc_client_settings[each.key])

  ignore_server_additions = true
}

moved {
  from = restapi_object.tinyauth
  to   = restapi_object.oidc_clients["tinyauth"]
}

moved {
  from = restapi_object.portainer
  to   = restapi_object.oidc_clients["portainer"]
}

moved {
  from = restapi_object.litellm
  to   = restapi_object.oidc_clients["litellm"]
}

moved {
  from = restapi_object.openwebui
  to   = restapi_object.oidc_clients["openwebui"]
}

moved {
  from = restapi_object.grafana
  to   = restapi_object.oidc_clients["grafana"]
}

moved {
  from = restapi_object.pgadmin
  to   = restapi_object.oidc_clients["pgadmin"]
}

data "restapi_object" "admin_group" {
  path         = "/user-groups"
  query_string = "search=admin"
  results_key  = "data"
  search_key   = "name"
  search_value = "admin"
}

# Pocket ID has no GET for this sub-resource, so PUT is (ab)used for create,
# read and update; destroying reverts the client to no allowed groups.
resource "restapi_object" "allowed_user_groups" {
  for_each = restapi_object.oidc_clients

  path           = "/oidc/clients/${each.value.id}/allowed-user-groups"
  object_id      = each.value.id
  create_method  = "PUT"
  read_method    = "PUT"
  update_method  = "PUT"
  destroy_method = "PUT"
  read_path      = "/oidc/clients/${each.value.id}/allowed-user-groups"
  update_path    = "/oidc/clients/${each.value.id}/allowed-user-groups"
  destroy_path   = "/oidc/clients/${each.value.id}/allowed-user-groups"

  data         = jsonencode({ userGroupIds = [data.restapi_object.admin_group.id] })
  read_data    = jsonencode({ userGroupIds = [data.restapi_object.admin_group.id] })
  update_data  = jsonencode({ userGroupIds = [data.restapi_object.admin_group.id] })
  destroy_data = jsonencode({ userGroupIds = [] })

  ignore_server_additions = true
}
