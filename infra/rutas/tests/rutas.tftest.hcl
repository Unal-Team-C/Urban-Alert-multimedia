# terraform test with mocked providers and a fake platform contract: no AWS credentials, no real resources.
mock_provider "aws" {
  mock_resource "aws_apigatewayv2_integration" {
    defaults = { id = "integ123" }
  }
}

override_data {
  target = data.aws_ssm_parameter.api_id
  values = { value = "api123" }
}

override_data {
  target = data.aws_ssm_parameter.api_execution_arn
  values = { value = "arn:aws:execute-api:us-east-2:348364742283:api123" }
}

override_data {
  target = data.aws_ssm_parameter.api_endpoint
  values = { value = "https://api123.execute-api.us-east-2.amazonaws.com" }
}

override_data {
  target = data.terraform_remote_state.servicio
  values = {
    outputs = {
      api_function_name = "urban-alert-multimedia"
      api_invoke_arn    = "arn:aws:apigateway:us-east-2:lambda:path/2015-03-31/functions/arn:aws:lambda:us-east-2:348364742283:function:urban-alert-multimedia/invocations"
    }
  }
}

run "exactly_the_two_public_routes_of_rf005" {
  command = apply

  assert {
    condition = toset([for r in aws_apigatewayv2_route.this : r.route_key]) == toset([
      "POST /api/v1/multimedia/images",
      "GET /api/v1/multimedia/images/{imageId}/metadata",
    ])
    error_message = "Only the two routes of RF-005 may be registered (no $default, no /docs)."
  }

  assert {
    condition     = alltrue([for r in aws_apigatewayv2_route.this : r.authorization_type == "NONE" && r.api_id == "api123" && r.target == "integrations/integ123"])
    error_message = "Public routes of the shared gateway read from SSM, all to the Lambda integration."
  }
}

run "the_gateway_invokes_the_function_with_payload_2" {
  command = apply

  assert {
    condition = (
      aws_apigatewayv2_integration.api.integration_type == "AWS_PROXY" &&
      aws_apigatewayv2_integration.api.payload_format_version == "2.0" &&
      aws_apigatewayv2_integration.api.integration_uri == "arn:aws:apigateway:us-east-2:lambda:path/2015-03-31/functions/arn:aws:lambda:us-east-2:348364742283:function:urban-alert-multimedia/invocations"
    )
    error_message = "Lambda proxy integration with the API Gateway v2 event Mangum expects (plan D-009)."
  }

  assert {
    condition     = aws_apigatewayv2_integration.api.connection_type != "VPC_LINK"
    error_message = "The platform VPC link is for load balancers, not for Lambda."
  }
}

run "only_the_shared_gateway_may_invoke_the_function" {
  command = apply

  assert {
    condition = (
      aws_lambda_permission.gateway.principal == "apigateway.amazonaws.com" &&
      aws_lambda_permission.gateway.action == "lambda:InvokeFunction" &&
      aws_lambda_permission.gateway.function_name == "urban-alert-multimedia" &&
      aws_lambda_permission.gateway.source_arn == "arn:aws:execute-api:us-east-2:348364742283:api123/*/*/api/v1/multimedia/*"
    )
    error_message = "Invocation is limited to the Multimedia paths of the shared gateway (RF-006)."
  }

  assert {
    condition     = output.gateway_url == "https://api123.execute-api.us-east-2.amazonaws.com"
    error_message = "gateway_url must be the api-endpoint published by the platform."
  }
}
