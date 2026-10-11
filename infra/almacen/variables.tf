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

variable "cdn_price_class" {
  description = "CloudFront price class (PriceClass_100 = North America and Europe, the cheapest)."
  type        = string

  validation {
    condition     = contains(["PriceClass_100", "PriceClass_200", "PriceClass_All"], var.cdn_price_class)
    error_message = "cdn_price_class must be PriceClass_100, PriceClass_200 or PriceClass_All."
  }
}

variable "abort_incomplete_upload_days" {
  description = "Days after which incomplete multipart uploads are removed."
  type        = number
}
