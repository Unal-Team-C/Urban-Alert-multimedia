# Read by the stack servicio through terraform_remote_state. No output carries the password or the URI.
output "name" {
  value = var.name
}

output "vpc_id" {
  value = local.vpc_id
}

output "subnet_ids" {
  description = "Every private subnet of the shared platform."
  value       = local.private_subnets
}

output "lambda_security_group_id" {
  value = aws_security_group.lambda.id
}

output "docdb_cluster_id" {
  value = aws_docdb_cluster.this.id
}

output "docdb_secret_arn" {
  description = "MONGODB_URI_SECRET_ARN of the functions."
  value       = aws_secretsmanager_secret.docdb.arn
}

output "api_function_name" {
  value = local.functions.api
}

output "init_function_name" {
  value = local.functions.init
}

output "api_role_arn" {
  value = aws_iam_role.function["api"].arn
}

output "init_role_arn" {
  value = aws_iam_role.function["init"].arn
}
