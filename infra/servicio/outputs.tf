# Read by the stack rutas (terraform_remote_state) and by the workflows (init invocation, summary).
output "api_function_name" {
  value = aws_lambda_function.api.function_name
}

output "api_function_arn" {
  value = aws_lambda_function.api.arn
}

output "api_invoke_arn" {
  value = aws_lambda_function.api.invoke_arn
}

output "init_function_name" {
  value = aws_lambda_function.init.function_name
}

output "image_base_url" {
  value = local.almacen.image_base_url
}
