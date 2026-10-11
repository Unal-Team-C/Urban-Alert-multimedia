# terraform test with mocked providers: no AWS credentials, no real resources.
# Plan only: apply runs would be destroyed at the end and prevent_destroy forbids that by design.
mock_provider "aws" {
  override_during = plan

  mock_data "aws_caller_identity" {
    defaults = { account_id = "348364742283" }
  }

  mock_resource "aws_s3_bucket" {
    defaults = {
      id                          = "urban-alert-multimedia-images-348364742283"
      arn                         = "arn:aws:s3:::urban-alert-multimedia-images-348364742283"
      bucket_regional_domain_name = "urban-alert-multimedia-images-348364742283.s3.us-east-2.amazonaws.com"
    }
  }

  mock_resource "aws_cloudfront_distribution" {
    defaults = {
      id          = "E2MOCK"
      arn         = "arn:aws:cloudfront::348364742283:distribution/E2MOCK"
      domain_name = "d111111abcdef8.cloudfront.net"
    }
  }

  mock_resource "aws_cloudfront_origin_access_control" {
    defaults = { id = "E3OACMOCK" }
  }
}

run "bucket_is_private_and_encrypted" {
  command = plan

  assert {
    condition     = aws_s3_bucket.images.bucket == "urban-alert-multimedia-images-348364742283"
    error_message = "The bucket name must keep the urban-alert- prefix and the account id."
  }

  assert {
    condition = (
      aws_s3_bucket_public_access_block.images.block_public_acls &&
      aws_s3_bucket_public_access_block.images.ignore_public_acls &&
      aws_s3_bucket_public_access_block.images.block_public_policy &&
      aws_s3_bucket_public_access_block.images.restrict_public_buckets
    )
    error_message = "Every Block Public Access option must be on (RF-002, RNF-001)."
  }

  assert {
    condition     = aws_s3_bucket_ownership_controls.images.rule[0].object_ownership == "BucketOwnerEnforced"
    error_message = "ACLs must be disabled."
  }

  assert {
    condition     = one([for r in aws_s3_bucket_server_side_encryption_configuration.images.rule : one(r.apply_server_side_encryption_by_default).sse_algorithm]) == "AES256"
    error_message = "Objects must be encrypted at rest."
  }
}

run "only_the_distribution_reads_and_tls_is_required" {
  command = plan

  assert {
    condition = (
      jsondecode(aws_s3_bucket_policy.images.policy).Statement[0].Effect == "Allow" &&
      jsondecode(aws_s3_bucket_policy.images.policy).Statement[0].Principal.Service == "cloudfront.amazonaws.com" &&
      jsondecode(aws_s3_bucket_policy.images.policy).Statement[0].Action == "s3:GetObject" &&
      jsondecode(aws_s3_bucket_policy.images.policy).Statement[0].Condition.StringEquals["AWS:SourceArn"] == "arn:aws:cloudfront::348364742283:distribution/E2MOCK"
    )
    error_message = "Only the CloudFront distribution may read objects (no listing, no public read)."
  }

  assert {
    condition     = length([for s in jsondecode(aws_s3_bucket_policy.images.policy).Statement : s if s.Effect == "Allow"]) == 1
    error_message = "The bucket policy must allow nothing else."
  }

  assert {
    condition = (
      jsondecode(aws_s3_bucket_policy.images.policy).Statement[1].Effect == "Deny" &&
      jsondecode(aws_s3_bucket_policy.images.policy).Statement[1].Condition.Bool["aws:SecureTransport"] == "false"
    )
    error_message = "Requests without TLS must be denied."
  }
}

run "images_move_to_intelligent_tiering_from_day_zero" {
  command = plan

  assert {
    condition = one(flatten([
      for r in aws_s3_bucket_lifecycle_configuration.images.rule : [
        for t in r.transition : t if t.storage_class == "INTELLIGENT_TIERING" && t.days == 0
      ] if r.status == "Enabled"
    ])) != null
    error_message = "Images must transition to INTELLIGENT_TIERING on day 0 (RF-008)."
  }

  assert {
    condition = alltrue(flatten([
      for r in aws_s3_bucket_lifecycle_configuration.images.rule : [
        for t in r.transition : contains(["INTELLIGENT_TIERING"], t.storage_class)
      ]
    ]))
    error_message = "No transition to a class that needs a restore before reading (Glacier Flexible, Deep Archive)."
  }
}

run "cdn_serves_https_through_the_access_control" {
  command = plan

  assert {
    condition     = aws_cloudfront_distribution.images.default_cache_behavior[0].viewer_protocol_policy == "redirect-to-https"
    error_message = "Images must be served over HTTPS."
  }

  assert {
    condition     = toset(aws_cloudfront_distribution.images.default_cache_behavior[0].allowed_methods) == toset(["GET", "HEAD"])
    error_message = "The CDN is read-only."
  }

  assert {
    condition = (
      one(aws_cloudfront_distribution.images.origin).origin_access_control_id == "E3OACMOCK" &&
      aws_cloudfront_origin_access_control.images.signing_behavior == "always" &&
      aws_cloudfront_origin_access_control.images.origin_access_control_origin_type == "s3"
    )
    error_message = "CloudFront must sign every origin request with its origin access control."
  }

  assert {
    condition     = output.cdn_url == "https://d111111abcdef8.cloudfront.net"
    error_message = "cdn_url must be the HTTPS URL of the distribution (PUBLIC_IMAGE_BASE_URL)."
  }
}

run "name_must_keep_the_pipeline_prefix" {
  command = plan

  variables {
    name = "multimedia"
  }

  expect_failures = [var.name]
}
