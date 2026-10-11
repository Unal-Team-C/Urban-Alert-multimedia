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

variable "abort_incomplete_upload_days" {
  description = "Days after which incomplete multipart uploads are removed."
  type        = number
}
