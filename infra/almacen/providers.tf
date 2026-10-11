provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Project   = "urban-alert"
      Service   = "multimedia"
      ManagedBy = "terraform"
      Stack     = "almacen"
    }
  }
}
