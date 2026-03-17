output "bucket_id" {
  description = "The ID (name) of the S3 bucket."
  value       = aws_s3_bucket.this.id
}

output "bucket_arn" {
  description = "The ARN of the S3 bucket."
  value       = aws_s3_bucket.this.arn
}

output "versioning_status" {
  description = "The versioning status of the bucket."
  value       = aws_s3_bucket_versioning.this.versioning_configuration[0].status
}