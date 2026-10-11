# terraform test with mocked providers: no AWS credentials, no real resources.
mock_provider "aws" {}

override_data {
  target = data.terraform_remote_state.almacen
  values = {
    outputs = {
      bucket_name = "urban-alert-multimedia-images-348364742283"
      cdn_url     = "https://d111111abcdef8.cloudfront.net"
    }
  }
}

override_data {
  target = data.terraform_remote_state.base
  values = {
    outputs = {
      api_function_name        = "urban-alert-multimedia"
      init_function_name       = "urban-alert-multimedia-init"
      api_role_arn             = "arn:aws:iam::348364742283:role/urban-alert-multimedia-api"
      init_role_arn            = "arn:aws:iam::348364742283:role/urban-alert-multimedia-init"
      subnet_ids               = ["subnet-priv-a", "subnet-priv-b"]
      lambda_security_group_id = "sg-lambda"
      docdb_secret_arn         = "arn:aws:secretsmanager:us-east-2:348364742283:secret:urban-alert-multimedia-docdb-AbCdEf"
    }
  }
}

variables {
  paquete_zip = "tests/fixture.zip"
  commit      = "0123456789abcdef"
}

run "api_function_runs_the_package_with_the_service_limits" {
  command = apply

  assert {
    condition = (
      aws_lambda_function.api.runtime == "python3.13" &&
      aws_lambda_function.api.architectures == tolist(["x86_64"]) &&
      aws_lambda_function.api.handler == "app.main.handler" &&
      aws_lambda_function.api.source_code_hash == filebase64sha256("tests/fixture.zip")
    )
    error_message = "The API runs the .zip on python3.13 x86_64 with the Mangum handler (RF-001)."
  }

  assert {
    condition     = aws_lambda_function.api.memory_size == 512 && aws_lambda_function.api.timeout == 15
    error_message = "512 MB and 15 s (RF-001)."
  }

  assert {
    condition     = aws_lambda_function.api.tags["Commit"] == "0123456789abcdef"
    error_message = "The deployed commit must be traceable (RNF-008)."
  }
}

run "api_uses_the_cloud_services" {
  command = apply

  assert {
    condition = (
      !contains(keys(aws_lambda_function.api.environment[0].variables), "AWS_ENDPOINT_URL_S3") &&
      !contains(keys(aws_lambda_function.api.environment[0].variables), "MONGODB_URI")
    )
    error_message = "No S3 endpoint override (native S3) and no MongoDB URI in the configuration (RF-004)."
  }

  assert {
    condition = (
      aws_lambda_function.api.environment[0].variables["MONGODB_URI_SECRET_ARN"] == "arn:aws:secretsmanager:us-east-2:348364742283:secret:urban-alert-multimedia-docdb-AbCdEf" &&
      aws_lambda_function.api.environment[0].variables["S3_BUCKET"] == "urban-alert-multimedia-images-348364742283" &&
      aws_lambda_function.api.environment[0].variables["PUBLIC_IMAGE_BASE_URL"] == "https://d111111abcdef8.cloudfront.net" &&
      aws_lambda_function.api.environment[0].variables["ENABLE_DOCS"] == "false"
    )
    error_message = "The API must use its bucket, CloudFront as imageUrl base and the DocumentDB secret (RF-002, RF-004)."
  }
}

run "connections_stay_bounded" {
  command = apply

  assert {
    condition     = aws_lambda_function.api.environment[0].variables["MONGODB_MAX_POOL_SIZE"] == "2"
    error_message = "2 connections per instance (plan D-008, RNF-002)."
  }

  assert {
    condition     = aws_lambda_function.api.reserved_concurrent_executions == -1
    error_message = "No reserved concurrency by default: the account limit (10) bounds the instances (plan D-008)."
  }
}

run "both_functions_run_in_the_private_network" {
  command = apply

  assert {
    condition = alltrue([
      for f in [aws_lambda_function.api, aws_lambda_function.init] :
      toset(f.vpc_config[0].subnet_ids) == toset(["subnet-priv-a", "subnet-priv-b"]) && toset(f.vpc_config[0].security_group_ids) == toset(["sg-lambda"])
    ])
    error_message = "Both functions run in every private subnet with the function security group (RF-006)."
  }
}

run "init_runs_the_index_handler_without_s3_settings" {
  command = apply

  assert {
    condition = (
      aws_lambda_function.init.handler == "app.admin.init_resources.handler" &&
      aws_lambda_function.init.source_code_hash == aws_lambda_function.api.source_code_hash &&
      aws_lambda_function.init.role == "arn:aws:iam::348364742283:role/urban-alert-multimedia-init"
    )
    error_message = "Init runs the same package with its own handler and role (RF-007)."
  }

  assert {
    condition     = keys(aws_lambda_function.init.environment[0].variables) == tolist(["LOG_LEVEL", "MONGODB_DATABASE", "MONGODB_URI_SECRET_ARN"])
    error_message = "Init only needs the DocumentDB settings."
  }
}

run "timeout_must_fit_the_gateway" {
  command = plan

  variables {
    timeout_s = 30
  }

  expect_failures = [var.timeout_s]
}
