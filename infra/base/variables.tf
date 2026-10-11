variable "region" {
  description = "AWS region."
  type        = string
}

variable "name" {
  description = "Prefix for every resource of this service. Must start with urban-alert- (IAM policies of the pipeline are scoped to it)."
  type        = string

  validation {
    condition     = startswith(var.name, "urban-alert-")
    error_message = "name must start with \"urban-alert-\"."
  }
}

variable "allow_destroy" {
  description = "Only the deprovision workflow sets it: disables the DocumentDB deletion protection."
  type        = bool
  default     = false
}

variable "final_snapshot_suffix" {
  description = "Suffix of the final DocumentDB snapshot taken on destroy (the deprovision workflow passes its run id)."
  type        = string
  default     = "manual"
}

variable "docdb_engine_version" {
  description = "DocumentDB engine version (MongoDB 5.0 API)."
  type        = string
}

variable "docdb_instance_class" {
  description = "Class of the single DocumentDB instance."
  type        = string
}

variable "docdb_master_user" {
  description = "Master user of the cluster, used by the function (plan D-002)."
  type        = string
}

variable "docdb_backup_retention_days" {
  type = number

  validation {
    condition     = var.docdb_backup_retention_days >= 7
    error_message = "Backups must be kept at least 7 days (RNF-007)."
  }
}

variable "docdb_port" {
  type    = number
  default = 27017
}

variable "docdb_ca_file" {
  description = "Path of the DocumentDB CA bundle inside the Lambda package (scripts/build-lambda-zip.sh)."
  type        = string
  default     = "/var/task/certs/global-bundle.pem"
}
