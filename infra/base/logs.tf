# Created before the functions so they get a retention (otherwise Lambda creates them without one) (RNF-008).
resource "aws_cloudwatch_log_group" "function" {
  for_each = local.functions

  name              = "/aws/lambda/${each.value}"
  retention_in_days = var.log_retention_days
}
