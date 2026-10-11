output "gateway_url" {
  description = "Public URL of the shared gateway (api-endpoint published by the platform)."
  value       = nonsensitive(data.aws_ssm_parameter.api_endpoint.value)
}

output "routes" {
  value = [for r in aws_apigatewayv2_route.this : r.route_key]
}
