output "kms_key_id" {
  description = "ID of the KMS key used for encryption"
  value       = aws_kms_key.encryption_key.key_id
}

output "kms_key_arn" {
  description = "ARN of the KMS key used for encryption"
  value       = aws_kms_key.encryption_key.arn
}

output "kms_key_alias" {
  description = "Alias of the KMS key used for encryption"
  value       = aws_kms_alias.encryption_key_alias.name
}

output "vpc_id" {
  description = "ID of the VPC"
  value       = aws_vpc.main.id
}

output "public_subnet_ids" {
  description = "IDs of the public subnets"
  value       = aws_subnet.public[*].id
}

output "private_subnet_ids" {
  description = "IDs of the private subnets"
  value       = aws_subnet.private[*].id
}

output "s3_bucket_name" {
  description = "Name of the encrypted S3 bucket"
  value       = aws_s3_bucket.encrypted_data.bucket
}

output "s3_bucket_arn" {
  description = "ARN of the encrypted S3 bucket"
  value       = aws_s3_bucket.encrypted_data.arn
}

output "s3_bucket_domain_name" {
  description = "Domain name of the encrypted S3 bucket"
  value       = aws_s3_bucket.encrypted_data.bucket_domain_name
}

output "cloudtrail_bucket_name" {
  description = "Name of the CloudTrail S3 bucket"
  value       = var.enable_cloudtrail ? aws_s3_bucket.cloudtrail[0].bucket : null
}

output "cloudtrail_name" {
  description = "Name of the CloudTrail"
  value       = var.enable_cloudtrail ? aws_cloudtrail.encryption_events[0].name : null
}

output "rds_endpoint" {
  description = "RDS instance endpoint"
  value       = aws_db_instance.encrypted_db.endpoint
}

output "rds_port" {
  description = "RDS instance port"
  value       = aws_db_instance.encrypted_db.port
}

output "rds_db_name" {
  description = "RDS database name"
  value       = aws_db_instance.encrypted_db.db_name
}

output "rds_username" {
  description = "RDS master username"
  value       = aws_db_instance.encrypted_db.username
  sensitive   = true
}

output "secrets_manager_secret_arn" {
  description = "ARN of the Secrets Manager secret containing database credentials"
  value       = aws_secretsmanager_secret.db_credentials.arn
}

output "secrets_manager_secret_name" {
  description = "Name of the Secrets Manager secret containing database credentials"
  value       = aws_secretsmanager_secret.db_credentials.name
}

output "ec2_instance_id" {
  description = "ID of the EC2 instance"
  value       = aws_instance.encrypted_ec2.id
}

output "ec2_public_ip" {
  description = "Public IP address of the EC2 instance"
  value       = aws_instance.encrypted_ec2.public_ip
}

output "ec2_private_ip" {
  description = "Private IP address of the EC2 instance"
  value       = aws_instance.encrypted_ec2.private_ip
}

output "ec2_security_group_id" {
  description = "ID of the EC2 security group"
  value       = aws_security_group.ec2.id
}

output "rds_security_group_id" {
  description = "ID of the RDS security group"
  value       = aws_security_group.rds.id
}

output "acm_certificate_arn" {
  description = "ARN of the ACM certificate"
  value       = var.enable_certificate_request && var.domain_name != "" ? aws_acm_certificate.main[0].arn : null
}

output "acm_certificate_domain_validation_options" {
  description = "Domain validation options for the ACM certificate"
  value       = var.enable_certificate_request && var.domain_name != "" ? aws_acm_certificate.main[0].domain_validation_options : null
}

output "cloudwatch_log_group_name" {
  description = "Name of the CloudWatch log group"
  value       = aws_cloudwatch_log_group.app_logs.name
}

output "cloudwatch_log_group_arn" {
  description = "ARN of the CloudWatch log group"
  value       = aws_cloudwatch_log_group.app_logs.arn
}

output "iam_role_arn" {
  description = "ARN of the IAM role for EC2 instance"
  value       = aws_iam_role.ec2_role.arn
}

output "iam_instance_profile_name" {
  description = "Name of the IAM instance profile"
  value       = aws_iam_instance_profile.ec2_profile.name
}

# Connection information
output "ssh_connection_command" {
  description = "SSH command to connect to the EC2 instance"
  value       = var.enable_ssh_access ? "ssh -i ~/.ssh/id_rsa ec2-user@${aws_instance.encrypted_ec2.public_ip}" : "SSH access is disabled"
}

output "mysql_connection_command" {
  description = "MySQL command to connect to the RDS instance"
  value       = "mysql -h ${aws_db_instance.encrypted_db.endpoint} -u admin -p ${aws_db_instance.encrypted_db.db_name}"
}

# Security validation commands
output "validation_commands" {
  description = "Commands to validate encryption implementation"
  value = {
    kms_key_details = "aws kms describe-key --key-id ${aws_kms_key.encryption_key.key_id}"
    s3_encryption_check = "aws s3api get-bucket-encryption --bucket ${aws_s3_bucket.encrypted_data.bucket}"
    rds_encryption_check = "aws rds describe-db-instances --db-instance-identifier ${aws_db_instance.encrypted_db.identifier} --query 'DBInstances[0].[StorageEncrypted,KmsKeyId]'"
    secrets_manager_check = "aws secretsmanager get-secret-value --secret-id ${aws_secretsmanager_secret.db_credentials.name}"
    ec2_volume_encryption_check = "aws ec2 describe-volumes --volume-ids $(aws ec2 describe-instances --instance-ids ${aws_instance.encrypted_ec2.id} --query 'Reservations[0].Instances[0].BlockDeviceMappings[0].Ebs.VolumeId' --output text) --query 'Volumes[0].[Encrypted,KmsKeyId]'"
  }
}

# Cost estimation information
output "estimated_monthly_cost" {
  description = "Estimated monthly cost breakdown (USD)"
  value = {
    kms_key = "1.00 (per key)"
    s3_storage = "0.023 per GB"
    rds_t3_micro = "13.00 (MySQL)"
    ec2_t3_micro = "7.50"
    ebs_storage = "0.10 per GB"
    cloudtrail = "2.00 per 100,000 events"
    secrets_manager = "0.40 per secret"
    acm_certificate = "0.00 (free for AWS services)"
    estimated_total = "25.00 - 35.00 (depending on usage)"
  }
}