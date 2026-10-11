# Routes of the Multimedia service in the shared API Gateway of urban-alert-plataforma (spec 002 RF-005; plan D-009).
# The gateway invokes the function directly (AWS_PROXY, payload 2.0, the event Mangum expects); the platform VPC link is
# only for the ECS Express load balancers. No path rewrite: the service already serves /api/v1/multimedia/*.
# Applied after the init function created the indexes, so the service is published only when it is ready (plan §4.3).
data "aws_ssm_parameter" "api_id" {
  name = "/urban-alert/plataforma/api-id"
}

data "aws_ssm_parameter" "api_execution_arn" {
  name = "/urban-alert/plataforma/api-execution-arn"
}

data "aws_ssm_parameter" "api_endpoint" {
  name = "/urban-alert/plataforma/api-endpoint"
}

data "terraform_remote_state" "servicio" {
  backend = "s3"

  config = {
    bucket = "urban-alert-tfstate-348364742283"
    key    = "multimedia/servicio.tfstate"
    region = var.region
  }
}

locals {
  # The provider marks SSM values as sensitive; these IDs are not secrets.
  api_id            = nonsensitive(data.aws_ssm_parameter.api_id.value)
  api_execution_arn = nonsensitive(data.aws_ssm_parameter.api_execution_arn.value)
  servicio          = data.terraform_remote_state.servicio.outputs

  # Public, as every route of the platform (no client authentication in the gateway). Nothing else is published:
  # /docs, /openapi.json and any other path keep answering 404 from the gateway.
  routes = {
    upload   = "POST /api/v1/multimedia/images"
    metadata = "GET /api/v1/multimedia/images/{imageId}/metadata"
  }
}

resource "aws_apigatewayv2_integration" "api" {
  api_id                 = local.api_id
  description            = "Lambda ${local.servicio.api_function_name}"
  integration_type       = "AWS_PROXY"
  integration_method     = "POST"
  integration_uri        = local.servicio.api_invoke_arn
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_route" "this" {
  for_each = local.routes

  api_id             = local.api_id
  route_key          = each.value
  authorization_type = "NONE"
  target             = "integrations/${aws_apigatewayv2_integration.api.id}"
}

# Only the shared gateway, and only for paths under the Multimedia prefix, may invoke the function.
resource "aws_lambda_permission" "gateway" {
  statement_id  = "AllowSharedGatewayMultimediaRoutes"
  action        = "lambda:InvokeFunction"
  function_name = local.servicio.api_function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${local.api_execution_arn}/*/*/api/v1/multimedia/*"
}
