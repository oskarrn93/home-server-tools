terraform {
  required_version = ">= 1.16.0"

  required_providers {
    null = {
      source  = "hashicorp/null"
      version = "~> 3.1"
    }
  }
}

variable "mariadb_endpoint" {
  description = "MariaDB endpoint used by Terraform."
  type        = string
  default     = "127.0.0.1:3306"
}

locals {
  ansible_database_vars   = yamldecode(file("${path.module}/../ansible/vars/local-databases.yml"))
  mariadb_root_user       = local.ansible_database_vars.mariadb_root_user
  mariadb_root_password   = sensitive(local.ansible_database_vars.mariadb_root_password)
  uptime_kuma_db_name     = local.ansible_database_vars.uptime_kuma_db_name
  uptime_kuma_db_user     = local.ansible_database_vars.uptime_kuma_db_user
  uptime_kuma_db_password = sensitive(local.ansible_database_vars.uptime_kuma_db_password)
}

resource "null_resource" "uptime_kuma_database" {
  triggers = {
    database_name = local.uptime_kuma_db_name
    database_user = local.uptime_kuma_db_user
    database_pass = local.uptime_kuma_db_password
    root_user     = local.mariadb_root_user
    root_pass     = local.mariadb_root_password
    endpoint      = var.mariadb_endpoint
  }

  provisioner "local-exec" {
    command = <<-EOT
      mysql \
        --protocol=TCP \
        --host="${split(":", var.mariadb_endpoint)[0]}" \
        --port="${split(":", var.mariadb_endpoint)[1]}" \
        --user="${local.mariadb_root_user}" \
        --password="${local.mariadb_root_password}" \
        --execute="CREATE DATABASE IF NOT EXISTS ${local.uptime_kuma_db_name} CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci; CREATE USER IF NOT EXISTS '${local.uptime_kuma_db_user}'@'%' IDENTIFIED BY '${local.uptime_kuma_db_password}'; GRANT ALL PRIVILEGES ON ${local.uptime_kuma_db_name}.* TO '${local.uptime_kuma_db_user}'@'%'; FLUSH PRIVILEGES;"
    EOT
  }
}

output "uptime_kuma_connection" {
  value     = "mysql://${local.uptime_kuma_db_user}:${local.uptime_kuma_db_password}@127.0.0.1:3306/${local.uptime_kuma_db_name}"
  sensitive = true
}
