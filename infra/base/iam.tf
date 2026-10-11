# Roles of the two functions, with inline policies only (plan D-012: the pipeline may only attach ECS managed policies).
# Least privilege (spec 002 RNF-001): the API writes and deletes objects of its bucket only; init has no S3 access.
data "terraform_remote_state" "almacen" {
  backend = "s3"

  config = {
    bucket = "urban-alert-tfstate-348364742283"
    key    = "multimedia/almacen.tfstate"
    region = var.region
  }
}

locals {
  functions = {
    api  = var.name
    init = "${var.name}-init"
  }

  bucket_arn = data.terraform_remote_state.almacen.outputs.bucket_arn

  # Same permissions as AWSLambdaVPCAccessExecutionRole: ENIs in the private subnets.
  vpc_access = {
    Sid    = "VpcNetworkInterfaces"
    Effect = "Allow"
    Action = [
      "ec2:CreateNetworkInterface",
      "ec2:DescribeNetworkInterfaces",
      "ec2:DescribeSubnets",
      "ec2:DeleteNetworkInterface",
      "ec2:AssignPrivateIpAddresses",
      "ec2:UnassignPrivateIpAddresses",
    ]
    Resource = "*"
  }

  read_docdb_secret = {
    Sid      = "ReadDocumentDbUri"
    Effect   = "Allow"
    Action   = "secretsmanager:GetSecretValue"
    Resource = aws_secretsmanager_secret.docdb.arn
  }
}

resource "aws_iam_role" "function" {
  for_each = local.functions

  name        = "${var.name}-${each.key}"
  description = "Lambda function ${each.value}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "function" {
  for_each = local.functions

  name = "${each.value}-runtime"
  role = aws_iam_role.function[each.key].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = concat(
      [
        local.vpc_access,
        local.read_docdb_secret,
        {
          Sid      = "OwnLogGroup"
          Effect   = "Allow"
          Action   = ["logs:CreateLogStream", "logs:PutLogEvents"]
          Resource = "${aws_cloudwatch_log_group.function[each.key].arn}:*"
        },
      ],
      each.key == "api" ? [{
        Sid      = "WriteImages"
        Effect   = "Allow"
        Action   = ["s3:PutObject", "s3:DeleteObject"]
        Resource = "${local.bucket_arn}/*"
      }] : [],
    )
  })
}
