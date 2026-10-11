variable "region" {
  description = "AWS region."
  type        = string
}

variable "paquete_zip" {
  description = "Path of the Lambda package built by scripts/build-lambda-zip.sh (the deprovision workflow passes an empty file)."
  type        = string
}

variable "commit" {
  description = "Commit SHA of the deployed package (tag Commit, RNF-008)."
  type        = string
}

variable "memory_mb" {
  type = number
}

variable "timeout_s" {
  description = "Timeout of the API function: Lambda governance limit of the service (512 MB, 15 s)."
  type        = number

  validation {
    condition     = var.timeout_s <= 29
    error_message = "timeout_s must stay below the 30 s integration timeout of the API Gateway."
  }
}

variable "init_timeout_s" {
  type = number
}

variable "concurrencia_reservada" {
  description = "Reserved concurrency of the API function; -1 = none (plan D-008: a new account has 10 in total and Lambda keeps 10 unreserved)."
  type        = number
}

variable "mongodb_max_pool_size" {
  description = "MongoDB connections per function instance (plus 2 for monitoring); see plan D-008."
  type        = number
}

variable "log_level" {
  type = string
}
