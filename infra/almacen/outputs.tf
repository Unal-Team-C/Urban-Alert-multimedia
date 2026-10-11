# Read by the stacks base (role permissions) and servicio (PUBLIC_IMAGE_BASE_URL) through terraform_remote_state.
output "bucket_name" {
  value = aws_s3_bucket.images.bucket
}

output "bucket_arn" {
  value = aws_s3_bucket.images.arn
}

output "image_base_url" {
  description = "Base of every imageUrl (PUBLIC_IMAGE_BASE_URL of the function): the HTTPS URL of the bucket."
  value       = "https://${aws_s3_bucket.images.bucket_regional_domain_name}"
}
