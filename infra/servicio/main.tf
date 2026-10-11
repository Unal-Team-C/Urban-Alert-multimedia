# The two functions of the service, from the same .zip (spec 002 RF-001, RF-006; plan D-007, D-010).
# No function URL: the API is only invoked by the shared API Gateway (stack rutas).
data "terraform_remote_state" "almacen" {
  backend = "s3"

  config = {
    bucket = "urban-alert-tfstate-348364742283"
    key    = "multimedia/almacen.tfstate"
    region = var.region
  }
}

data "terraform_remote_state" "base" {
  backend = "s3"

  config = {
    bucket = "urban-alert-tfstate-348364742283"
    key    = "multimedia/base.tfstate"
    region = var.region
  }
}

locals {
  almacen = data.terraform_remote_state.almacen.outputs
  base    = data.terraform_remote_state.base.outputs

  # Cloud configuration of the service (plan §7.2): no AWS_ENDPOINT_URL_S3 (native S3) and no MONGODB_URI
  # (read from Secrets Manager); imageUrl values start with the CloudFront URL.
  api_environment = {
    S3_BUCKET              = local.almacen.bucket_name
    PUBLIC_IMAGE_BASE_URL  = local.almacen.cdn_url
    MONGODB_URI_SECRET_ARN = local.base.docdb_secret_arn
    MONGODB_DATABASE       = "multimedia"
    MONGODB_MAX_POOL_SIZE  = tostring(var.mongodb_max_pool_size)
    ENABLE_DOCS            = "false"
    LOG_LEVEL              = var.log_level
  }

  init_environment = {
    MONGODB_URI_SECRET_ARN = local.base.docdb_secret_arn
    MONGODB_DATABASE       = "multimedia"
    LOG_LEVEL              = var.log_level
  }

  package_hash = filebase64sha256(var.paquete_zip)
}

resource "aws_lambda_function" "api" {
  function_name = local.base.api_function_name
  description   = "UrbanAlert Multimedia: UploadImage and GetImageMetadata"
  role          = local.base.api_role_arn

  runtime          = "python3.13"
  architectures    = ["x86_64"]
  handler          = "app.main.handler"
  filename         = var.paquete_zip
  source_code_hash = local.package_hash

  memory_size                    = var.memory_mb
  timeout                        = var.timeout_s
  reserved_concurrent_executions = var.concurrencia_reservada

  vpc_config {
    subnet_ids         = local.base.subnet_ids
    security_group_ids = [local.base.lambda_security_group_id]
  }

  environment {
    variables = local.api_environment
  }

  tags = {
    Commit = var.commit
  }
}

resource "aws_lambda_function" "init" {
  function_name = local.base.init_function_name
  description   = "UrbanAlert Multimedia: creates the DocumentDB indexes (invoked by the Provision workflow)"
  role          = local.base.init_role_arn

  runtime          = "python3.13"
  architectures    = ["x86_64"]
  handler          = "app.admin.init_resources.handler"
  filename         = var.paquete_zip
  source_code_hash = local.package_hash

  memory_size = var.memory_mb
  timeout     = var.init_timeout_s

  vpc_config {
    subnet_ids         = local.base.subnet_ids
    security_group_ids = [local.base.lambda_security_group_id]
  }

  environment {
    variables = local.init_environment
  }

  tags = {
    Commit = var.commit
  }
}
