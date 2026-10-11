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
}

run "bucket_is_encrypted_without_acls" {
  command = plan

  assert {
    condition     = aws_s3_bucket.images.bucket == "urban-alert-multimedia-images-348364742283"
    error_message = "The bucket name must keep the urban-alert- prefix and the account id."
  }

  assert {
    condition = (
      aws_s3_bucket_public_access_block.images.block_public_acls &&
      aws_s3_bucket_public_access_block.images.ignore_public_acls
    )
    error_message = "ACLs must stay blocked: public read only comes from the bucket policy (plan D-015)."
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

run "anyone_reads_single_objects_but_nobody_lists_or_writes" {
  command = plan

  assert {
    condition = [for st in jsondecode(aws_s3_bucket_policy.images.policy).Statement : st if st.Effect == "Allow"] == [{
      Sid       = "PublicReadSingleObjects"
      Effect    = "Allow"
      Principal = "*"
      Action    = "s3:GetObject"
      Resource  = "arn:aws:s3:::urban-alert-multimedia-images-348364742283/*"
    }]
    error_message = "The only grant is the anonymous read of single objects: no ListBucket, no writes (RF-002, HU-4 #1)."
  }

  assert {
    condition = (
      jsondecode(aws_s3_bucket_policy.images.policy).Statement[1].Effect == "Deny" &&
      jsondecode(aws_s3_bucket_policy.images.policy).Statement[1].Condition.Bool["aws:SecureTransport"] == "false"
    )
    error_message = "Requests without TLS must be denied."
  }

  assert {
    condition     = output.image_base_url == "https://urban-alert-multimedia-images-348364742283.s3.us-east-2.amazonaws.com"
    error_message = "image_base_url must be the HTTPS URL of the bucket (PUBLIC_IMAGE_BASE_URL)."
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

run "name_must_keep_the_pipeline_prefix" {
  command = plan

  variables {
    name = "multimedia"
  }

  expect_failures = [var.name]
}
