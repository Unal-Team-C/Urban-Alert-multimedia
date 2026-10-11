# Shared private network of the UrbanAlert platform (repo urban-alert-plataforma, contract in SSM).
# Fails with ParameterNotFound when the platform is not provisioned (the workflow checks it first).
# The function leaves through the platform NAT (Secrets Manager) and its S3 gateway endpoint; DocumentDB is only
# reachable from the function security group (spec 002 RF-003, RF-006).
data "aws_ssm_parameter" "vpc_id" {
  name = "/urban-alert/plataforma/vpc-id"
}

data "aws_ssm_parameter" "private_subnets" {
  name = "/urban-alert/plataforma/subredes-privadas"
}

# The provider marks every SSM value as sensitive; network IDs are not secrets and are needed as outputs.
locals {
  vpc_id          = nonsensitive(data.aws_ssm_parameter.vpc_id.value)
  private_subnets = split(",", nonsensitive(data.aws_ssm_parameter.private_subnets.value))
}

resource "aws_security_group" "lambda" {
  name        = "${var.name}-lambda"
  description = "Lambda functions of ${var.name} (API and init)"
  vpc_id      = local.vpc_id
}

resource "aws_vpc_security_group_egress_rule" "lambda_https" {
  security_group_id = aws_security_group.lambda.id
  description       = "HTTPS to S3 (platform gateway endpoint) and Secrets Manager (platform NAT)"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  cidr_ipv4         = "0.0.0.0/0"
}

resource "aws_vpc_security_group_egress_rule" "lambda_docdb" {
  security_group_id            = aws_security_group.lambda.id
  description                  = "MongoDB protocol to DocumentDB"
  ip_protocol                  = "tcp"
  from_port                    = var.docdb_port
  to_port                      = var.docdb_port
  referenced_security_group_id = aws_security_group.docdb.id
}

resource "aws_security_group" "docdb" {
  name        = "${var.name}-docdb"
  description = "DocumentDB of ${var.name}: only from its Lambda functions"
  vpc_id      = local.vpc_id
}

resource "aws_vpc_security_group_ingress_rule" "docdb_from_lambda" {
  security_group_id            = aws_security_group.docdb.id
  description                  = "MongoDB protocol from ${var.name} functions"
  ip_protocol                  = "tcp"
  from_port                    = var.docdb_port
  to_port                      = var.docdb_port
  referenced_security_group_id = aws_security_group.lambda.id
}
