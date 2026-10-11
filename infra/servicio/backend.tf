# Bootstrap bucket created by hand (infra/bootstrap/README.md). Locking with an S3 .tflock object (Terraform >= 1.10).
terraform {
  backend "s3" {
    bucket       = "urban-alert-tfstate-348364742283"
    key          = "multimedia/servicio.tfstate"
    region       = "us-east-2"
    encrypt      = true
    use_lockfile = true
  }
}
