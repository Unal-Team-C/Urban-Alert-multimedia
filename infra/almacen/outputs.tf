# Read by the stacks base (role permissions) and servicio (PUBLIC_IMAGE_BASE_URL) through terraform_remote_state.
output "bucket_name" {
  value = aws_s3_bucket.images.bucket
}

output "bucket_arn" {
  value = aws_s3_bucket.images.arn
}

output "cdn_domain" {
  value = aws_cloudfront_distribution.images.domain_name
}

output "cdn_url" {
  description = "Base of every imageUrl (PUBLIC_IMAGE_BASE_URL of the function)."
  value       = "https://${aws_cloudfront_distribution.images.domain_name}"
}

output "distribution_id" {
  value = aws_cloudfront_distribution.images.id
}
