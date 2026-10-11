# Persistent image storage (spec 002 RF-002, RF-008, RF-017; plan D-003, D-005, D-015).
# The Deprovision workflow never touches this stack and prevent_destroy makes any plan that would delete the
# bucket fail: issued imageUrl values keep working across deprovision/provision cycles.
# Images are served directly by S3 (anonymous read of single objects, like MinIO locally): CloudFront needs an
# account verified by AWS Support, which this account is not (plan D-015).
data "aws_caller_identity" "current" {}

locals {
  # Bucket names are global: the account id keeps it unique.
  bucket_name = "${var.name}-images-${data.aws_caller_identity.current.account_id}"
}

resource "aws_s3_bucket" "images" {
  bucket = local.bucket_name

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_s3_bucket_ownership_controls" "images" {
  bucket = aws_s3_bucket.images.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

# ACLs stay blocked; the public read comes only from the bucket policy below (plan D-015).
resource "aws_s3_bucket_public_access_block" "images" {
  bucket = aws_s3_bucket.images.id

  block_public_acls       = true
  ignore_public_acls      = true
  block_public_policy     = false
  restrict_public_buckets = false
}

resource "aws_s3_bucket_server_side_encryption_configuration" "images" {
  bucket = aws_s3_bucket.images.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
    bucket_key_enabled = true
  }
}

# QAS-08: Intelligent-Tiering from day 0 without the optional archive tiers (no aws_s3_bucket_intelligent_tiering_configuration),
# so every object stays readable with a plain GET and reads are never charged.
resource "aws_s3_bucket_lifecycle_configuration" "images" {
  bucket = aws_s3_bucket.images.id

  rule {
    id     = "intelligent-tiering"
    status = "Enabled"

    filter {
      prefix = ""
    }

    transition {
      days          = 0
      storage_class = "INTELLIGENT_TIERING"
    }
  }

  rule {
    id     = "abort-incomplete-uploads"
    status = "Enabled"

    filter {
      prefix = ""
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = var.abort_incomplete_upload_days
    }
  }
}

# Anyone may read a single object by its key (UUID v4, unguessable), over TLS only. No ListBucket: an unknown key
# answers 403. Nobody writes anonymously; the function writes through its IAM role (stack base).
resource "aws_s3_bucket_policy" "images" {
  bucket = aws_s3_bucket.images.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "PublicReadSingleObjects"
        Effect    = "Allow"
        Principal = "*"
        Action    = "s3:GetObject"
        Resource  = "${aws_s3_bucket.images.arn}/*"
      },
      {
        Sid       = "DenyInsecureTransport"
        Effect    = "Deny"
        Principal = "*"
        Action    = "s3:*"
        Resource  = [aws_s3_bucket.images.arn, "${aws_s3_bucket.images.arn}/*"]
        Condition = { Bool = { "aws:SecureTransport" = "false" } }
      },
    ]
  })

  # The public access block must allow public policies before this one is put.
  depends_on = [aws_s3_bucket_public_access_block.images]
}
