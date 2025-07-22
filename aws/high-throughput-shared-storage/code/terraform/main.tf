# main.tf - High-Performance File Systems with Amazon FSx
#
# This Terraform configuration creates a comprehensive high-performance file system
# solution using Amazon FSx, including Lustre, Windows File Server, and NetApp ONTAP.
# The infrastructure is designed for HPC workloads, enterprise applications, and
# multi-protocol access patterns.

# =============================================================================
# Data Sources for Environment Information
# =============================================================================

# Get current AWS region and account information
data "aws_region" "current" {}
data "aws_caller_identity" "current" {}

# Get available availability zones in the region
data "aws_availability_zones" "available" {
  state = "available"
  filter {
    name   = "zone-type"
    values = ["availability-zone"]
  }
}

# Get default VPC if not creating a new one
data "aws_vpc" "default" {
  count   = var.create_vpc ? 0 : 1
  default = var.vpc_id == null ? true : false
  id      = var.vpc_id
}

# Get subnets in the VPC if not creating new ones
data "aws_subnets" "default" {
  count = var.create_vpc ? 0 : 1
  filter {
    name   = "vpc-id"
    values = [var.create_vpc ? aws_vpc.main[0].id : data.aws_vpc.default[0].id]
  }
  filter {
    name   = "state"
    values = ["available"]
  }
}

# Get latest Amazon Linux 2 AMI for test instances
data "aws_ami" "amazon_linux" {
  count       = var.create_test_instances ? 1 : 0
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# =============================================================================
# Random Resources for Unique Naming
# =============================================================================

# Generate random suffix for resource names to ensure uniqueness
resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
}

# Generate random password for ONTAP admin if not provided
resource "random_password" "ontap_admin" {
  count   = var.create_ontap_filesystem && var.ontap_admin_password == null ? 1 : 0
  length  = 16
  special = true
}

# =============================================================================
# Networking Infrastructure
# =============================================================================

# Create VPC if requested
resource "aws_vpc" "main" {
  count                = var.create_vpc ? 1 : 0
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "${var.project_prefix}-vpc"
  }
}

# Create Internet Gateway for VPC
resource "aws_internet_gateway" "main" {
  count  = var.create_vpc ? 1 : 0
  vpc_id = aws_vpc.main[0].id

  tags = {
    Name = "${var.project_prefix}-igw"
  }
}

# Create public subnets for FSx file systems
resource "aws_subnet" "public" {
  count             = var.create_vpc ? 2 : 0
  vpc_id            = aws_vpc.main[0].id
  cidr_block        = cidrsubnet(var.vpc_cidr, 8, count.index)
  availability_zone = length(var.availability_zones) > 0 ? var.availability_zones[count.index] : data.aws_availability_zones.available.names[count.index]

  map_public_ip_on_launch = true

  tags = {
    Name = "${var.project_prefix}-public-subnet-${count.index + 1}"
    Type = "Public"
  }
}

# Create route table for public subnets
resource "aws_route_table" "public" {
  count  = var.create_vpc ? 1 : 0
  vpc_id = aws_vpc.main[0].id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main[0].id
  }

  tags = {
    Name = "${var.project_prefix}-public-rt"
  }
}

# Associate public subnets with route table
resource "aws_route_table_association" "public" {
  count          = var.create_vpc ? 2 : 0
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public[0].id
}

# =============================================================================
# Security Groups
# =============================================================================

# Security group for FSx file systems
resource "aws_security_group" "fsx" {
  name_prefix = "${var.project_prefix}-fsx-"
  vpc_id      = var.create_vpc ? aws_vpc.main[0].id : data.aws_vpc.default[0].id
  description = "Security group for Amazon FSx file systems"

  # Lustre traffic (port 988)
  ingress {
    description = "FSx Lustre traffic"
    from_port   = 988
    to_port     = 988
    protocol    = "tcp"
    cidr_blocks = var.allowed_cidr_blocks
  }

  # SMB traffic for Windows File Server (port 445)
  ingress {
    description = "SMB traffic for Windows File Server"
    from_port   = 445
    to_port     = 445
    protocol    = "tcp"
    cidr_blocks = var.allowed_cidr_blocks
  }

  # NFS traffic for ONTAP (port 2049)
  ingress {
    description = "NFS traffic for ONTAP"
    from_port   = 2049
    to_port     = 2049
    protocol    = "tcp"
    cidr_blocks = var.allowed_cidr_blocks
  }

  # Additional NFS and management ports for ONTAP
  ingress {
    description = "NFS and management traffic for ONTAP"
    from_port   = 111
    to_port     = 111
    protocol    = "tcp"
    cidr_blocks = var.allowed_cidr_blocks
  }

  # iSCSI traffic for ONTAP (port 3260)
  ingress {
    description = "iSCSI traffic for ONTAP"
    from_port   = 3260
    to_port     = 3260
    protocol    = "tcp"
    cidr_blocks = var.allowed_cidr_blocks
  }

  # ONTAP management traffic
  ingress {
    description = "ONTAP management traffic"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = var.allowed_cidr_blocks
  }

  # Allow all outbound traffic
  egress {
    description = "All outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_prefix}-fsx-sg"
  }

  lifecycle {
    create_before_destroy = true
  }
}

# Security group for test EC2 instances
resource "aws_security_group" "test_instances" {
  count       = var.create_test_instances ? 1 : 0
  name_prefix = "${var.project_prefix}-test-"
  vpc_id      = var.create_vpc ? aws_vpc.main[0].id : data.aws_vpc.default[0].id
  description = "Security group for test EC2 instances"

  # SSH access
  ingress {
    description = "SSH access"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = var.allowed_cidr_blocks
  }

  # Allow all outbound traffic
  egress {
    description = "All outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_prefix}-test-sg"
  }

  lifecycle {
    create_before_destroy = true
  }
}

# =============================================================================
# S3 Bucket for Lustre Data Repository
# =============================================================================

# S3 bucket for Lustre data repository
resource "aws_s3_bucket" "lustre_data" {
  count  = var.create_lustre_filesystem && var.create_s3_data_repository ? 1 : 0
  bucket = var.s3_bucket_name != null ? var.s3_bucket_name : "${var.project_prefix}-lustre-data-${random_string.suffix.result}"

  tags = {
    Name    = "FSx Lustre Data Repository"
    Purpose = "HPC workload data storage"
  }
}

# Enable versioning on S3 bucket
resource "aws_s3_bucket_versioning" "lustre_data" {
  count  = var.create_lustre_filesystem && var.create_s3_data_repository ? 1 : 0
  bucket = aws_s3_bucket.lustre_data[0].id
  versioning_configuration {
    status = "Enabled"
  }
}

# Configure server-side encryption for S3 bucket
resource "aws_s3_bucket_server_side_encryption_configuration" "lustre_data" {
  count  = var.create_lustre_filesystem && var.create_s3_data_repository ? 1 : 0
  bucket = aws_s3_bucket.lustre_data[0].id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = var.kms_key_id != null ? "aws:kms" : "AES256"
      kms_master_key_id = var.kms_key_id
    }
    bucket_key_enabled = true
  }
}

# Block public access to S3 bucket
resource "aws_s3_bucket_public_access_block" "lustre_data" {
  count  = var.create_lustre_filesystem && var.create_s3_data_repository ? 1 : 0
  bucket = aws_s3_bucket.lustre_data[0].id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Create sample directories in S3 bucket
resource "aws_s3_object" "input_directory" {
  count  = var.create_lustre_filesystem && var.create_s3_data_repository ? 1 : 0
  bucket = aws_s3_bucket.lustre_data[0].id
  key    = "input/"
  source = "/dev/null"

  tags = {
    Purpose = "Input data directory for HPC workloads"
  }
}

resource "aws_s3_object" "output_directory" {
  count  = var.create_lustre_filesystem && var.create_s3_data_repository ? 1 : 0
  bucket = aws_s3_bucket.lustre_data[0].id
  key    = "output/"
  source = "/dev/null"

  tags = {
    Purpose = "Output data directory for HPC results"
  }
}

# =============================================================================
# IAM Role for FSx Service Access
# =============================================================================

# IAM role for FSx to access S3
resource "aws_iam_role" "fsx_service" {
  count = var.create_lustre_filesystem && var.create_s3_data_repository ? 1 : 0
  name  = "${var.project_prefix}-fsx-service-role-${random_string.suffix.result}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "fsx.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Name    = "FSx Service Role"
    Purpose = "Allow FSx to access S3 data repository"
  }
}

# IAM policy for FSx to access S3 bucket
resource "aws_iam_role_policy" "fsx_s3_access" {
  count = var.create_lustre_filesystem && var.create_s3_data_repository ? 1 : 0
  name  = "${var.project_prefix}-fsx-s3-policy"
  role  = aws_iam_role.fsx_service[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:GetObjectVersion",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:ListBucket",
          "s3:ListBucketVersions"
        ]
        Resource = [
          aws_s3_bucket.lustre_data[0].arn,
          "${aws_s3_bucket.lustre_data[0].arn}/*"
        ]
      }
    ]
  })
}

# =============================================================================
# Amazon FSx for Lustre File System
# =============================================================================

# FSx for Lustre file system for high-performance computing workloads
resource "aws_fsx_lustre_file_system" "main" {
  count                        = var.create_lustre_filesystem ? 1 : 0
  storage_capacity             = var.lustre_storage_capacity
  subnet_ids                   = var.create_vpc ? [aws_subnet.public[0].id] : [length(var.subnet_ids) > 0 ? var.subnet_ids[0] : data.aws_subnets.default[0].ids[0]]
  deployment_type              = var.lustre_deployment_type
  per_unit_storage_throughput  = var.lustre_per_unit_storage_throughput
  security_group_ids           = [aws_security_group.fsx.id]

  # Auto import/export configuration
  auto_import_policy      = var.create_s3_data_repository ? var.lustre_auto_import_policy : null
  import_path             = var.create_s3_data_repository ? "s3://${aws_s3_bucket.lustre_data[0].bucket}/input/" : null
  export_path             = var.create_s3_data_repository ? "s3://${aws_s3_bucket.lustre_data[0].bucket}/output/" : null
  data_compression_type   = var.lustre_data_compression_type

  # Encryption configuration
  kms_key_id = var.enable_encryption_at_rest ? var.kms_key_id : null

  tags = {
    Name              = "${var.project_prefix}-lustre-fs"
    FileSystemType    = "Lustre"
    Purpose           = "High-performance computing workloads"
    DeploymentType    = var.lustre_deployment_type
    StorageCapacity   = "${var.lustre_storage_capacity}GiB"
    Throughput        = "${var.lustre_per_unit_storage_throughput}MB/s/TiB"
  }

  # Ensure proper resource dependencies
  depends_on = [
    aws_iam_role_policy.fsx_s3_access
  ]
}

# =============================================================================
# Amazon FSx for Windows File Server
# =============================================================================

# FSx for Windows File Server for SMB-based workloads
resource "aws_fsx_windows_file_system" "main" {
  count                      = var.create_windows_filesystem ? 1 : 0
  storage_capacity           = var.windows_storage_capacity
  subnet_ids                 = var.create_vpc ? [aws_subnet.public[0].id] : [length(var.subnet_ids) > 0 ? var.subnet_ids[0] : data.aws_subnets.default[0].ids[0]]
  throughput_capacity        = var.windows_throughput_capacity
  deployment_type            = var.windows_deployment_type
  security_group_ids         = [aws_security_group.fsx.id]

  # Multi-AZ configuration
  preferred_subnet_id = var.windows_deployment_type == "MULTI_AZ_1" ? (var.create_vpc ? aws_subnet.public[0].id : (length(var.subnet_ids) > 0 ? var.subnet_ids[0] : data.aws_subnets.default[0].ids[0])) : null

  # Backup configuration
  automatic_backup_retention_days = var.enable_automatic_backups ? var.backup_retention_days : 0
  daily_automatic_backup_start_time = var.enable_automatic_backups ? var.daily_backup_start_time : null
  copy_tags_to_backups           = var.enable_automatic_backups

  # Encryption configuration
  kms_key_id = var.enable_encryption_at_rest ? var.kms_key_id : null

  tags = {
    Name              = "${var.project_prefix}-windows-fs"
    FileSystemType    = "Windows"
    Purpose           = "SMB-based enterprise applications"
    DeploymentType    = var.windows_deployment_type
    StorageCapacity   = "${var.windows_storage_capacity}GiB"
    ThroughputCapacity = "${var.windows_throughput_capacity}MB/s"
  }
}

# =============================================================================
# Amazon FSx for NetApp ONTAP File System
# =============================================================================

# FSx for NetApp ONTAP for multi-protocol access
resource "aws_fsx_ontap_file_system" "main" {
  count                       = var.create_ontap_filesystem ? 1 : 0
  storage_capacity            = var.ontap_storage_capacity
  subnet_ids                  = var.create_vpc ? [aws_subnet.public[0].id, aws_subnet.public[1].id] : (length(var.subnet_ids) >= 2 ? slice(var.subnet_ids, 0, 2) : slice(data.aws_subnets.default[0].ids, 0, 2))
  deployment_type             = var.ontap_deployment_type
  throughput_capacity         = var.ontap_throughput_capacity
  security_group_ids          = [aws_security_group.fsx.id]

  # Multi-AZ configuration
  preferred_subnet_id = var.create_vpc ? aws_subnet.public[0].id : (length(var.subnet_ids) > 0 ? var.subnet_ids[0] : data.aws_subnets.default[0].ids[0])

  # Admin password
  fsx_admin_password = var.ontap_admin_password != null ? var.ontap_admin_password : random_password.ontap_admin[0].result

  # Backup configuration
  automatic_backup_retention_days = var.enable_automatic_backups ? var.backup_retention_days : 0
  daily_automatic_backup_start_time = var.enable_automatic_backups ? var.daily_backup_start_time : null

  # Encryption configuration
  kms_key_id = var.enable_encryption_at_rest ? var.kms_key_id : null

  tags = {
    Name              = "${var.project_prefix}-ontap-fs"
    FileSystemType    = "ONTAP"
    Purpose           = "Multi-protocol enterprise storage"
    DeploymentType    = var.ontap_deployment_type
    StorageCapacity   = "${var.ontap_storage_capacity}GiB"
    ThroughputCapacity = "${var.ontap_throughput_capacity}MB/s"
  }
}

# Storage Virtual Machine (SVM) for ONTAP
resource "aws_fsx_ontap_storage_virtual_machine" "main" {
  count                = var.create_ontap_filesystem && var.create_ontap_svm ? 1 : 0
  file_system_id       = aws_fsx_ontap_file_system.main[0].id
  name                 = var.ontap_svm_name
  svm_admin_password   = var.ontap_admin_password != null ? var.ontap_admin_password : random_password.ontap_admin[0].result

  tags = {
    Name    = "${var.project_prefix}-${var.ontap_svm_name}"
    Purpose = "Multi-protocol data access"
  }
}

# NFS volume for Unix/Linux workloads
resource "aws_fsx_ontap_volume" "nfs" {
  count                      = var.create_ontap_filesystem && var.create_ontap_svm && var.create_ontap_volumes ? 1 : 0
  name                       = "nfs-volume"
  junction_path              = "/nfs"
  size_in_megabytes          = var.ontap_nfs_volume_size
  storage_efficiency_enabled = true
  storage_virtual_machine_id = aws_fsx_ontap_storage_virtual_machine.main[0].id
  security_style             = "UNIX"

  tags = {
    Name        = "${var.project_prefix}-nfs-volume"
    Protocol    = "NFS"
    SecurityStyle = "UNIX"
    Purpose     = "Unix/Linux workload data"
  }
}

# SMB volume for Windows workloads
resource "aws_fsx_ontap_volume" "smb" {
  count                      = var.create_ontap_filesystem && var.create_ontap_svm && var.create_ontap_volumes ? 1 : 0
  name                       = "smb-volume"
  junction_path              = "/smb"
  size_in_megabytes          = var.ontap_smb_volume_size
  storage_efficiency_enabled = true
  storage_virtual_machine_id = aws_fsx_ontap_storage_virtual_machine.main[0].id
  security_style             = "NTFS"

  tags = {
    Name        = "${var.project_prefix}-smb-volume"
    Protocol    = "SMB"
    SecurityStyle = "NTFS"
    Purpose     = "Windows workload data"
  }
}

# =============================================================================
# CloudWatch Log Group for FSx Logging
# =============================================================================

# CloudWatch log group for FSx Lustre logging
resource "aws_cloudwatch_log_group" "fsx_lustre" {
  count             = var.create_lustre_filesystem ? 1 : 0
  name              = "/aws/fsx/lustre"
  retention_in_days = 30

  tags = {
    Name    = "FSx Lustre Logs"
    Purpose = "Lustre file system logging"
  }
}

# =============================================================================
# SNS Topic for CloudWatch Alarms (if email provided)
# =============================================================================

# SNS topic for alarm notifications
resource "aws_sns_topic" "alarms" {
  count = var.create_cloudwatch_alarms && var.sns_notification_email != null ? 1 : 0
  name  = "${var.project_prefix}-fsx-alarms"

  tags = {
    Name    = "FSx Alarm Notifications"
    Purpose = "CloudWatch alarm notifications"
  }
}

# SNS topic subscription for email notifications
resource "aws_sns_topic_subscription" "email" {
  count     = var.create_cloudwatch_alarms && var.sns_notification_email != null ? 1 : 0
  topic_arn = aws_sns_topic.alarms[0].arn
  protocol  = "email"
  endpoint  = var.sns_notification_email
}

# =============================================================================
# CloudWatch Alarms for Monitoring
# =============================================================================

# CloudWatch alarm for Lustre throughput utilization
resource "aws_cloudwatch_metric_alarm" "lustre_throughput" {
  count               = var.create_lustre_filesystem && var.create_cloudwatch_alarms ? 1 : 0
  alarm_name          = "${var.project_prefix}-lustre-throughput"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "ThroughputUtilization"
  namespace           = "AWS/FSx"
  period              = "300"
  statistic           = "Average"
  threshold           = var.alarm_threshold_lustre_throughput
  alarm_description   = "This metric monitors FSx Lustre throughput utilization"
  alarm_actions       = var.sns_notification_email != null ? [aws_sns_topic.alarms[0].arn] : []

  dimensions = {
    FileSystemId = aws_fsx_lustre_file_system.main[0].id
  }

  tags = {
    Name       = "Lustre Throughput Alarm"
    FileSystem = aws_fsx_lustre_file_system.main[0].id
  }
}

# CloudWatch alarm for Windows file system CPU utilization
resource "aws_cloudwatch_metric_alarm" "windows_cpu" {
  count               = var.create_windows_filesystem && var.create_cloudwatch_alarms ? 1 : 0
  alarm_name          = "${var.project_prefix}-windows-cpu"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "CPUUtilization"
  namespace           = "AWS/FSx"
  period              = "300"
  statistic           = "Average"
  threshold           = var.alarm_threshold_windows_cpu
  alarm_description   = "This metric monitors FSx Windows file system CPU utilization"
  alarm_actions       = var.sns_notification_email != null ? [aws_sns_topic.alarms[0].arn] : []

  dimensions = {
    FileSystemId = aws_fsx_windows_file_system.main[0].id
  }

  tags = {
    Name       = "Windows CPU Alarm"
    FileSystem = aws_fsx_windows_file_system.main[0].id
  }
}

# CloudWatch alarm for ONTAP storage utilization
resource "aws_cloudwatch_metric_alarm" "ontap_storage" {
  count               = var.create_ontap_filesystem && var.create_cloudwatch_alarms ? 1 : 0
  alarm_name          = "${var.project_prefix}-ontap-storage"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "1"
  metric_name         = "StorageUtilization"
  namespace           = "AWS/FSx"
  period              = "300"
  statistic           = "Average"
  threshold           = var.alarm_threshold_ontap_storage
  alarm_description   = "This metric monitors FSx ONTAP storage utilization"
  alarm_actions       = var.sns_notification_email != null ? [aws_sns_topic.alarms[0].arn] : []

  dimensions = {
    FileSystemId = aws_fsx_ontap_file_system.main[0].id
  }

  tags = {
    Name       = "ONTAP Storage Alarm"
    FileSystem = aws_fsx_ontap_file_system.main[0].id
  }
}

# =============================================================================
# Test EC2 Instances (Optional)
# =============================================================================

# IAM role for EC2 instances to access FSx
resource "aws_iam_role" "ec2_fsx_access" {
  count = var.create_test_instances ? 1 : 0
  name  = "${var.project_prefix}-ec2-fsx-role-${random_string.suffix.result}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Name    = "EC2 FSx Access Role"
    Purpose = "Allow EC2 instances to access FSx file systems"
  }
}

# IAM instance profile for EC2 instances
resource "aws_iam_instance_profile" "ec2_fsx_access" {
  count = var.create_test_instances ? 1 : 0
  name  = "${var.project_prefix}-ec2-fsx-profile-${random_string.suffix.result}"
  role  = aws_iam_role.ec2_fsx_access[0].name
}

# Test EC2 instance for Linux/Lustre testing
resource "aws_instance" "linux_test" {
  count                  = var.create_test_instances ? 1 : 0
  ami                    = data.aws_ami.amazon_linux[0].id
  instance_type          = var.test_instance_type
  key_name               = var.test_instance_key_name
  vpc_security_group_ids = [aws_security_group.test_instances[0].id, aws_security_group.fsx.id]
  subnet_id              = var.create_vpc ? aws_subnet.public[0].id : (length(var.subnet_ids) > 0 ? var.subnet_ids[0] : data.aws_subnets.default[0].ids[0])
  iam_instance_profile   = aws_iam_instance_profile.ec2_fsx_access[0].name

  user_data = base64encode(templatefile("${path.module}/user_data_linux.tftpl", {
    lustre_dns_name   = var.create_lustre_filesystem ? aws_fsx_lustre_file_system.main[0].dns_name : ""
    lustre_mount_name = var.create_lustre_filesystem ? aws_fsx_lustre_file_system.main[0].mount_name : ""
    windows_dns_name  = var.create_windows_filesystem ? aws_fsx_windows_file_system.main[0].dns_name : ""
    ontap_mgmt_dns    = var.create_ontap_filesystem ? aws_fsx_ontap_file_system.main[0].endpoints[0].management[0].dns_name : ""
  }))

  tags = {
    Name    = "${var.project_prefix}-linux-test"
    Purpose = "Test FSx file system access"
    OS      = "Amazon Linux 2"
  }
}

# Create user data template for Linux instance
resource "local_file" "linux_user_data_template" {
  count    = var.create_test_instances ? 1 : 0
  filename = "${path.module}/user_data_linux.tftpl"
  
  content = <<-EOF
#!/bin/bash
yum update -y
amazon-linux-extras install -y lustre2.10

# Create mount point for Lustre
mkdir -p /mnt/fsx

# Install useful tools for testing
yum install -y htop iotop tree

# Create test script for Lustre performance
cat > /home/ec2-user/test_lustre.sh << 'TESTEOF'
#!/bin/bash
%{ if lustre_dns_name != "" }
echo "Mounting Lustre file system..."
sudo mount -t lustre ${lustre_dns_name}@tcp:/${lustre_mount_name} /mnt/fsx
echo "Testing Lustre performance..."
sudo dd if=/dev/zero of=/mnt/fsx/testfile bs=1M count=100
sudo dd if=/mnt/fsx/testfile of=/dev/null bs=1M
sudo rm /mnt/fsx/testfile
%{ else }
echo "Lustre file system not available"
%{ endif }
TESTEOF

chmod +x /home/ec2-user/test_lustre.sh
chown ec2-user:ec2-user /home/ec2-user/test_lustre.sh

# Create info script with file system details
cat > /home/ec2-user/fsx_info.sh << 'INFOEOF'
#!/bin/bash
echo "=== FSx File System Information ==="
echo "Lustre DNS: ${lustre_dns_name}"
echo "Lustre Mount: ${lustre_mount_name}"
echo "Windows DNS: ${windows_dns_name}"
echo "ONTAP Management DNS: ${ontap_mgmt_dns}"
echo ""
echo "=== Mount Commands ==="
%{ if lustre_dns_name != "" }
echo "Lustre: sudo mount -t lustre ${lustre_dns_name}@tcp:/${lustre_mount_name} /mnt/fsx"
%{ endif }
INFOEOF

chmod +x /home/ec2-user/fsx_info.sh
chown ec2-user:ec2-user /home/ec2-user/fsx_info.sh
EOF
}