# terraform test with mocked providers: no AWS credentials, no real resources.
mock_provider "aws" {
  mock_resource "aws_docdb_cluster" {
    defaults = {
      id       = "urban-alert-multimedia-docdb"
      endpoint = "urban-alert-multimedia-docdb.cluster-mock.us-east-2.docdb.amazonaws.com"
    }
  }

  mock_resource "aws_secretsmanager_secret" {
    defaults = {
      arn = "arn:aws:secretsmanager:us-east-2:348364742283:secret:urban-alert-multimedia-docdb-AbCdEf"
    }
  }
}

mock_provider "random" {}

override_data {
  target = data.terraform_remote_state.almacen
  values = {
    outputs = {
      bucket_arn = "arn:aws:s3:::urban-alert-multimedia-images-348364742283"
    }
  }
}

# Platform contract (SSM). StringList values are comma-separated.
override_data {
  target = data.aws_ssm_parameter.vpc_id
  values = { value = "vpc-plataforma" }
}

override_data {
  target = data.aws_ssm_parameter.private_subnets
  values = { value = "subnet-priv-a,subnet-priv-b" }
}

run "defaults_protect_the_metadata" {
  command = apply

  assert {
    condition     = aws_docdb_cluster.this.deletion_protection
    error_message = "DocumentDB must have deletion protection unless allow_destroy is set (RF-012, RNF-007)."
  }

  assert {
    condition     = !aws_docdb_cluster.this.skip_final_snapshot
    error_message = "A final snapshot must always be taken (RF-011)."
  }

  assert {
    condition     = aws_docdb_cluster.this.backup_retention_period >= 7
    error_message = "Backups must be kept at least 7 days (RNF-007)."
  }
}

run "metadata_store_is_private_encrypted_and_requires_tls" {
  command = apply

  assert {
    condition     = aws_docdb_cluster.this.storage_encrypted
    error_message = "DocumentDB storage must be encrypted (RF-003)."
  }

  assert {
    condition = (
      aws_docdb_cluster_parameter_group.this.family == "docdb5.0" &&
      one([for p in aws_docdb_cluster_parameter_group.this.parameter : p.value if p.name == "tls"]) == "enabled" &&
      aws_docdb_cluster.this.db_cluster_parameter_group_name == aws_docdb_cluster_parameter_group.this.name
    )
    error_message = "The cluster must use a parameter group that enforces TLS (RF-003)."
  }

  assert {
    condition     = aws_docdb_cluster_instance.this.instance_class == "db.t4g.medium" && aws_docdb_cluster_instance.this.cluster_identifier == aws_docdb_cluster.this.id
    error_message = "A single instance of the smallest class (RNF-006)."
  }
}

run "only_the_functions_reach_the_metadata_store" {
  command = apply

  assert {
    condition = (
      aws_vpc_security_group_ingress_rule.docdb_from_lambda.referenced_security_group_id == aws_security_group.lambda.id &&
      aws_vpc_security_group_ingress_rule.docdb_from_lambda.cidr_ipv4 == null
    )
    error_message = "DocumentDB must only accept the function security group, never a CIDR (RNF-001)."
  }

  assert {
    condition = (
      aws_vpc_security_group_ingress_rule.docdb_from_lambda.from_port == 27017 &&
      aws_vpc_security_group_ingress_rule.docdb_from_lambda.to_port == 27017
    )
    error_message = "Only the MongoDB port is open."
  }

  assert {
    condition     = toset(aws_docdb_cluster.this.vpc_security_group_ids) == toset([aws_security_group.docdb.id])
    error_message = "The cluster must only have its own security group."
  }
}

run "uses_the_shared_private_network" {
  command = apply

  assert {
    condition     = aws_security_group.lambda.vpc_id == "vpc-plataforma" && aws_security_group.docdb.vpc_id == "vpc-plataforma"
    error_message = "Security groups must live in the platform VPC read from SSM (RF-006)."
  }

  assert {
    condition     = toset(aws_docdb_subnet_group.this.subnet_ids) == toset(["subnet-priv-a", "subnet-priv-b"])
    error_message = "DocumentDB must use every private subnet of the platform."
  }

  assert {
    condition     = output.subnet_ids == tolist(["subnet-priv-a", "subnet-priv-b"])
    error_message = "The functions must get every private subnet."
  }
}

run "the_secret_holds_a_tls_uri_and_is_recreatable" {
  command = apply

  assert {
    condition = (
      startswith(aws_secretsmanager_secret_version.docdb.secret_string, "mongodb://multimedia:") &&
      strcontains(aws_secretsmanager_secret_version.docdb.secret_string, "@urban-alert-multimedia-docdb.cluster-mock.us-east-2.docdb.amazonaws.com:27017/") &&
      strcontains(aws_secretsmanager_secret_version.docdb.secret_string, "tls=true") &&
      strcontains(aws_secretsmanager_secret_version.docdb.secret_string, "tlsCAFile=/var/task/certs/global-bundle.pem") &&
      strcontains(aws_secretsmanager_secret_version.docdb.secret_string, "retryWrites=false")
    )
    error_message = "The URI must point to the cluster with TLS, the packaged CA and no retryable writes (RF-003, RF-004)."
  }

  assert {
    condition     = aws_secretsmanager_secret.docdb.recovery_window_in_days == 0
    error_message = "The secret must be deleted immediately so it can be recreated after deprovisioning."
  }

  assert {
    condition     = output.docdb_secret_arn == "arn:aws:secretsmanager:us-east-2:348364742283:secret:urban-alert-multimedia-docdb-AbCdEf"
    error_message = "The functions get the secret ARN, not its value."
  }
}

run "allow_destroy_lifts_protection_and_names_the_snapshot" {
  command = apply

  variables {
    allow_destroy         = true
    final_snapshot_suffix = "123456"
  }

  assert {
    condition     = !aws_docdb_cluster.this.deletion_protection
    error_message = "allow_destroy must disable deletion protection."
  }

  assert {
    condition     = aws_docdb_cluster.this.final_snapshot_identifier == "urban-alert-multimedia-final-123456"
    error_message = "The final snapshot must be named after the workflow run."
  }
}

run "the_api_only_writes_its_bucket_and_init_has_no_s3" {
  command = apply

  assert {
    condition = one([
      for st in jsondecode(aws_iam_role_policy.function["api"].policy).Statement : st if st.Sid == "WriteImages"
      ]) == {
      Sid      = "WriteImages"
      Effect   = "Allow"
      Action   = ["s3:PutObject", "s3:DeleteObject"]
      Resource = "arn:aws:s3:::urban-alert-multimedia-images-348364742283/*"
    }
    error_message = "The API may only put and delete objects of its bucket (RNF-001)."
  }

  assert {
    condition = alltrue(flatten([
      for k, p in aws_iam_role_policy.function : [
        for st in jsondecode(p.policy).Statement : !anytrue([for a in flatten([st.Action]) : endswith(a, ":*") || a == "*"])
      ]
    ]))
    error_message = "No wildcard actions in the function policies."
  }

  assert {
    condition = length(flatten([
      for st in jsondecode(aws_iam_role_policy.function["init"].policy).Statement : [for a in flatten([st.Action]) : a if startswith(a, "s3:")]
    ])) == 0
    error_message = "The init function must not access S3 (plan D-007)."
  }

  assert {
    condition = alltrue([
      for k, p in aws_iam_role_policy.function :
      one([for st in jsondecode(p.policy).Statement : st.Resource if st.Sid == "ReadDocumentDbUri"]) == "arn:aws:secretsmanager:us-east-2:348364742283:secret:urban-alert-multimedia-docdb-AbCdEf"
    ])
    error_message = "Each function may only read the DocumentDB secret."
  }
}

run "functions_have_their_own_roles_and_log_groups" {
  command = apply

  assert {
    condition = (
      aws_iam_role.function["api"].name == "urban-alert-multimedia-api" &&
      aws_iam_role.function["init"].name == "urban-alert-multimedia-init" &&
      jsondecode(aws_iam_role.function["api"].assume_role_policy).Statement[0].Principal.Service == "lambda.amazonaws.com"
    )
    error_message = "Roles keep the urban-alert- prefix (pipeline PassRole) and trust Lambda only."
  }

  assert {
    condition = (
      aws_cloudwatch_log_group.function["api"].name == "/aws/lambda/urban-alert-multimedia" &&
      aws_cloudwatch_log_group.function["init"].name == "/aws/lambda/urban-alert-multimedia-init" &&
      alltrue([for g in aws_cloudwatch_log_group.function : g.retention_in_days == 30])
    )
    error_message = "Each function has its log group with a 30-day retention (RNF-008)."
  }
}

run "backups_below_seven_days_are_rejected" {
  command = plan

  variables {
    docdb_backup_retention_days = 1
  }

  expect_failures = [var.docdb_backup_retention_days]
}

run "name_must_keep_the_pipeline_prefix" {
  command = plan

  variables {
    name = "multimedia"
  }

  expect_failures = [var.name]
}
