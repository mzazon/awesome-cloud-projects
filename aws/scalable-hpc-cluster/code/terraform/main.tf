# Local variables for resource naming and configuration
locals {
  cluster_name = var.cluster_name != "" ? var.cluster_name : "hpc-cluster-${random_string.suffix.result}"
  
  common_tags = merge(
    {
      Environment = var.environment
      Project     = "HPC-ParallelCluster"
      ManagedBy   = "Terraform"
      ClusterName = local.cluster_name
    },
    var.additional_tags
  )
  
  # Generate ParallelCluster configuration
  parallelcluster_config = templatefile("${path.module}/templates/cluster-config.yaml.tpl", {
    region                    = var.aws_region
    cluster_name             = local.cluster_name
    head_node_instance_type  = var.head_node_instance_type
    compute_instance_type    = var.compute_instance_type
    min_compute_nodes        = var.min_compute_nodes
    max_compute_nodes        = var.max_compute_nodes
    public_subnet_id         = aws_subnet.public_subnet.id
    private_subnet_id        = aws_subnet.private_subnet.id
    keypair_name             = aws_key_pair.hpc_keypair.key_name
    s3_bucket_name           = aws_s3_bucket.hpc_data_bucket.bucket
    shared_storage_size      = var.shared_storage_size
    fsx_storage_capacity     = var.fsx_storage_capacity
    fsx_deployment_type      = var.fsx_deployment_type
    root_volume_size         = var.root_volume_size
    root_volume_type         = var.root_volume_type
    enable_efa               = var.enable_efa
    disable_hyperthreading   = var.disable_hyperthreading
    enable_cloudwatch        = var.enable_cloudwatch_monitoring
    scaledown_idletime       = var.scaledown_idletime
    scheduler_type           = var.scheduler_type
    enable_ebs_encryption    = var.enable_ebs_encryption
    kms_key_id               = var.kms_key_id
    custom_ami_id            = var.custom_ami_id
  })
  
  cluster_creation_command = "pcluster create-cluster --cluster-name ${local.cluster_name} --cluster-configuration s3://${aws_s3_bucket.hpc_data_bucket.bucket}/${aws_s3_object.parallelcluster_config.key}"
}

# Generate random suffix for unique resource naming
resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
}

# Data sources for current AWS account and region
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# Generate SSH key pair for cluster access
resource "tls_private_key" "hpc_key" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "aws_key_pair" "hpc_keypair" {
  key_name   = "hpc-keypair-${random_string.suffix.result}"
  public_key = tls_private_key.hpc_key.public_key_openssh

  tags = local.common_tags
}

# VPC and Networking Infrastructure
resource "aws_vpc" "hpc_vpc" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = merge(local.common_tags, {
    Name = "hpc-vpc-${random_string.suffix.result}"
  })
}

resource "aws_internet_gateway" "hpc_igw" {
  vpc_id = aws_vpc.hpc_vpc.id

  tags = merge(local.common_tags, {
    Name = "hpc-igw-${random_string.suffix.result}"
  })
}

# Public subnet for head node
resource "aws_subnet" "public_subnet" {
  vpc_id                  = aws_vpc.hpc_vpc.id
  cidr_block              = var.public_subnet_cidr
  availability_zone       = var.availability_zone
  map_public_ip_on_launch = true

  tags = merge(local.common_tags, {
    Name = "hpc-public-subnet-${random_string.suffix.result}"
    Type = "Public"
  })
}

# Private subnet for compute nodes
resource "aws_subnet" "private_subnet" {
  vpc_id            = aws_vpc.hpc_vpc.id
  cidr_block        = var.private_subnet_cidr
  availability_zone = var.availability_zone

  tags = merge(local.common_tags, {
    Name = "hpc-private-subnet-${random_string.suffix.result}"
    Type = "Private"
  })
}

# Elastic IP for NAT Gateway
resource "aws_eip" "nat_eip" {
  domain = "vpc"
  
  depends_on = [aws_internet_gateway.hpc_igw]

  tags = merge(local.common_tags, {
    Name = "hpc-nat-eip-${random_string.suffix.result}"
  })
}

# NAT Gateway for private subnet internet access
resource "aws_nat_gateway" "hpc_nat" {
  allocation_id = aws_eip.nat_eip.id
  subnet_id     = aws_subnet.public_subnet.id

  tags = merge(local.common_tags, {
    Name = "hpc-nat-gateway-${random_string.suffix.result}"
  })
}

# Route table for public subnet
resource "aws_route_table" "public_rt" {
  vpc_id = aws_vpc.hpc_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.hpc_igw.id
  }

  tags = merge(local.common_tags, {
    Name = "hpc-public-rt-${random_string.suffix.result}"
  })
}

# Route table for private subnet
resource "aws_route_table" "private_rt" {
  vpc_id = aws_vpc.hpc_vpc.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.hpc_nat.id
  }

  tags = merge(local.common_tags, {
    Name = "hpc-private-rt-${random_string.suffix.result}"
  })
}

# Associate route tables with subnets
resource "aws_route_table_association" "public_rta" {
  subnet_id      = aws_subnet.public_subnet.id
  route_table_id = aws_route_table.public_rt.id
}

resource "aws_route_table_association" "private_rta" {
  subnet_id      = aws_subnet.private_subnet.id
  route_table_id = aws_route_table.private_rt.id
}

# Security Groups
resource "aws_security_group" "head_node_sg" {
  name        = "hpc-head-node-sg-${random_string.suffix.result}"
  description = "Security group for HPC head node"
  vpc_id      = aws_vpc.hpc_vpc.id

  # SSH access from allowed CIDRs
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = var.allowed_ssh_cidr
    description = "SSH access for cluster management"
  }

  # Allow all traffic from compute nodes
  ingress {
    from_port       = 0
    to_port         = 65535
    protocol        = "tcp"
    security_groups = [aws_security_group.compute_node_sg.id]
    description     = "All traffic from compute nodes"
  }

  # Allow all outbound traffic
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "All outbound traffic"
  }

  tags = merge(local.common_tags, {
    Name = "hpc-head-node-sg-${random_string.suffix.result}"
  })
}

resource "aws_security_group" "compute_node_sg" {
  name        = "hpc-compute-node-sg-${random_string.suffix.result}"
  description = "Security group for HPC compute nodes"
  vpc_id      = aws_vpc.hpc_vpc.id

  # Allow all traffic from head node
  ingress {
    from_port       = 0
    to_port         = 65535
    protocol        = "tcp"
    security_groups = [aws_security_group.head_node_sg.id]
    description     = "All traffic from head node"
  }

  # Allow all traffic between compute nodes
  ingress {
    from_port = 0
    to_port   = 65535
    protocol  = "tcp"
    self      = true
    description = "Inter-node communication"
  }

  # Allow all outbound traffic
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "All outbound traffic"
  }

  tags = merge(local.common_tags, {
    Name = "hpc-compute-node-sg-${random_string.suffix.result}"
  })
}

# S3 Bucket for HPC data storage
resource "aws_s3_bucket" "hpc_data_bucket" {
  bucket = "hpc-data-${random_string.suffix.result}-${data.aws_caller_identity.current.account_id}"

  tags = local.common_tags
}

resource "aws_s3_bucket_versioning" "hpc_data_bucket_versioning" {
  bucket = aws_s3_bucket.hpc_data_bucket.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "hpc_data_bucket_encryption" {
  bucket = aws_s3_bucket.hpc_data_bucket.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "hpc_data_bucket_pab" {
  bucket = aws_s3_bucket.hpc_data_bucket.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Create folder structure in S3
resource "aws_s3_object" "input_folder" {
  bucket = aws_s3_bucket.hpc_data_bucket.id
  key    = "input/"
  content = ""
  
  tags = local.common_tags
}

resource "aws_s3_object" "output_folder" {
  bucket = aws_s3_bucket.hpc_data_bucket.id
  key    = "output/"
  content = ""
  
  tags = local.common_tags
}

resource "aws_s3_object" "jobs_folder" {
  bucket = aws_s3_bucket.hpc_data_bucket.id
  key    = "jobs/"
  content = ""
  
  tags = local.common_tags
}

resource "aws_s3_object" "keys_folder" {
  bucket = aws_s3_bucket.hpc_data_bucket.id
  key    = "keys/"
  content = ""
  
  tags = local.common_tags
}

# Upload sample job script
resource "aws_s3_object" "sample_job_script" {
  bucket = aws_s3_bucket.hpc_data_bucket.id
  key    = "jobs/sample_job.sh"
  content = templatefile("${path.module}/templates/sample_job.sh.tpl", {
    cluster_name = local.cluster_name
  })
  
  tags = local.common_tags
}

# Store private key in S3 for access
resource "aws_s3_object" "private_key" {
  bucket  = aws_s3_bucket.hpc_data_bucket.id
  key     = "keys/${aws_key_pair.hpc_keypair.key_name}.pem"
  content = tls_private_key.hpc_key.private_key_pem
  
  tags = local.common_tags
}

# Store ParallelCluster configuration in S3
resource "aws_s3_object" "parallelcluster_config" {
  bucket  = aws_s3_bucket.hpc_data_bucket.id
  key     = "config/cluster-config.yaml"
  content = local.parallelcluster_config
  
  tags = local.common_tags
}

# IAM Role for ParallelCluster instances
resource "aws_iam_role" "parallelcluster_instance_role" {
  name = "ParallelClusterInstanceRole-${random_string.suffix.result}"

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

  tags = local.common_tags
}

# IAM policies for ParallelCluster
resource "aws_iam_role_policy_attachment" "parallelcluster_instance_policy" {
  role       = aws_iam_role.parallelcluster_instance_role.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
}

resource "aws_iam_role_policy_attachment" "parallelcluster_ssm_policy" {
  role       = aws_iam_role.parallelcluster_instance_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# Custom IAM policy for S3 access
resource "aws_iam_role_policy" "parallelcluster_s3_policy" {
  name = "ParallelClusterS3Policy-${random_string.suffix.result}"
  role = aws_iam_role.parallelcluster_instance_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:ListBucket"
        ]
        Resource = [
          aws_s3_bucket.hpc_data_bucket.arn,
          "${aws_s3_bucket.hpc_data_bucket.arn}/*"
        ]
      }
    ]
  })
}

# Instance profile for ParallelCluster
resource "aws_iam_instance_profile" "parallelcluster_instance_profile" {
  name = "ParallelClusterInstanceProfile-${random_string.suffix.result}"
  role = aws_iam_role.parallelcluster_instance_role.name

  tags = local.common_tags
}

# CloudWatch Log Group for ParallelCluster logs
resource "aws_cloudwatch_log_group" "parallelcluster_logs" {
  count             = var.enable_cloudwatch_logs ? 1 : 0
  name              = "/aws/parallelcluster/${local.cluster_name}"
  retention_in_days = 30

  tags = local.common_tags
}

# CloudWatch Dashboard for cluster monitoring
resource "aws_cloudwatch_dashboard" "parallelcluster_dashboard" {
  count          = var.enable_cloudwatch_monitoring ? 1 : 0
  dashboard_name = "${local.cluster_name}-performance"

  dashboard_body = jsonencode({
    widgets = [
      {
        type   = "metric"
        x      = 0
        y      = 0
        width  = 12
        height = 6
        
        properties = {
          metrics = [
            ["AWS/EC2", "CPUUtilization", "ClusterName", local.cluster_name],
            ["AWS/EC2", "NetworkIn", "ClusterName", local.cluster_name],
            ["AWS/EC2", "NetworkOut", "ClusterName", local.cluster_name]
          ]
          period = 300
          stat   = "Average"
          region = var.aws_region
          title  = "HPC Cluster Metrics"
          view   = "timeSeries"
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 6
        width  = 12
        height = 6
        
        properties = {
          metrics = [
            ["AWS/EC2", "MemoryUtilization", "ClusterName", local.cluster_name],
            ["AWS/EC2", "DiskReadOps", "ClusterName", local.cluster_name],
            ["AWS/EC2", "DiskWriteOps", "ClusterName", local.cluster_name]
          ]
          period = 300
          stat   = "Average"
          region = var.aws_region
          title  = "Memory and Disk Metrics"
          view   = "timeSeries"
        }
      }
    ]
  })
}

# CloudWatch Alarms for cluster health monitoring
resource "aws_cloudwatch_metric_alarm" "high_cpu_alarm" {
  count               = var.enable_cloudwatch_monitoring ? 1 : 0
  alarm_name          = "${local.cluster_name}-high-cpu"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = "300"
  statistic           = "Average"
  threshold           = "80"
  alarm_description   = "This metric monitors ec2 cpu utilization"
  alarm_actions       = []

  dimensions = {
    ClusterName = local.cluster_name
  }

  tags = local.common_tags
}

resource "aws_cloudwatch_metric_alarm" "high_memory_alarm" {
  count               = var.enable_cloudwatch_monitoring ? 1 : 0
  alarm_name          = "${local.cluster_name}-high-memory"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "MemoryUtilization"
  namespace           = "AWS/EC2"
  period              = "300"
  statistic           = "Average"
  threshold           = "85"
  alarm_description   = "This metric monitors ec2 memory utilization"
  alarm_actions       = []

  dimensions = {
    ClusterName = local.cluster_name
  }

  tags = local.common_tags
}

# Create template files directory structure
resource "local_file" "cluster_config_template" {
  content = templatefile("${path.module}/templates/cluster-config.yaml.tpl", {
    region                    = var.aws_region
    cluster_name             = local.cluster_name
    head_node_instance_type  = var.head_node_instance_type
    compute_instance_type    = var.compute_instance_type
    min_compute_nodes        = var.min_compute_nodes
    max_compute_nodes        = var.max_compute_nodes
    public_subnet_id         = aws_subnet.public_subnet.id
    private_subnet_id        = aws_subnet.private_subnet.id
    keypair_name             = aws_key_pair.hpc_keypair.key_name
    s3_bucket_name           = aws_s3_bucket.hpc_data_bucket.bucket
    shared_storage_size      = var.shared_storage_size
    fsx_storage_capacity     = var.fsx_storage_capacity
    fsx_deployment_type      = var.fsx_deployment_type
    root_volume_size         = var.root_volume_size
    root_volume_type         = var.root_volume_type
    enable_efa               = var.enable_efa
    disable_hyperthreading   = var.disable_hyperthreading
    enable_cloudwatch        = var.enable_cloudwatch_monitoring
    scaledown_idletime       = var.scaledown_idletime
    scheduler_type           = var.scheduler_type
    enable_ebs_encryption    = var.enable_ebs_encryption
    kms_key_id               = var.kms_key_id
    custom_ami_id            = var.custom_ami_id
  })
  filename = "${path.module}/cluster-config.yaml"
}

# Create templates directory and files
resource "local_file" "cluster_config_tpl" {
  content = <<-EOF
Region: ${region}
Image:
  Os: alinux2
  %{ if custom_ami_id != "" }CustomAmi: ${custom_ami_id}%{ endif }
HeadNode:
  InstanceType: ${head_node_instance_type}
  Networking:
    SubnetId: ${public_subnet_id}
  Ssh:
    KeyName: ${keypair_name}
  LocalStorage:
    RootVolume:
      Size: ${root_volume_size}
      VolumeType: ${root_volume_type}
      %{ if enable_ebs_encryption }Encrypted: true%{ endif }
      %{ if kms_key_id != "" }KmsKeyId: ${kms_key_id}%{ endif }
Scheduling:
  Scheduler: ${scheduler_type}
  %{ if scheduler_type == "slurm" }
  SlurmSettings:
    ScaledownIdletime: ${scaledown_idletime}
    QueueUpdateStrategy: TERMINATE
  %{ endif }
  %{ if scheduler_type == "slurm" }
  SlurmQueues:
    - Name: compute
      ComputeResources:
        - Name: compute-nodes
          InstanceType: ${compute_instance_type}
          MinCount: ${min_compute_nodes}
          MaxCount: ${max_compute_nodes}
          %{ if disable_hyperthreading }DisableSimultaneousMultithreading: true%{ endif }
          %{ if enable_efa }
          Efa:
            Enabled: true
          %{ endif }
      Networking:
        SubnetIds:
          - ${private_subnet_id}
      ComputeSettings:
        LocalStorage:
          RootVolume:
            Size: ${root_volume_size}
            VolumeType: ${root_volume_type}
            %{ if enable_ebs_encryption }Encrypted: true%{ endif }
            %{ if kms_key_id != "" }KmsKeyId: ${kms_key_id}%{ endif }
  %{ endif }
SharedStorage:
  - MountDir: /shared
    Name: shared-storage
    StorageType: Ebs
    EbsSettings:
      Size: ${shared_storage_size}
      VolumeType: gp3
      %{ if enable_ebs_encryption }Encrypted: true%{ endif }
      %{ if kms_key_id != "" }KmsKeyId: ${kms_key_id}%{ endif }
  - MountDir: /fsx
    Name: fsx-storage
    StorageType: FsxLustre
    FsxLustreSettings:
      StorageCapacity: ${fsx_storage_capacity}
      DeploymentType: ${fsx_deployment_type}
      ImportPath: s3://${s3_bucket_name}/
      ExportPath: s3://${s3_bucket_name}/output/
%{ if enable_cloudwatch }
Monitoring:
  CloudWatch:
    Enabled: true
    DashboardName: ${cluster_name}-dashboard
%{ endif }
EOF
  filename = "${path.module}/templates/cluster-config.yaml.tpl"
}

resource "local_file" "sample_job_tpl" {
  content = <<-EOF
#!/bin/bash
#SBATCH --job-name=hpc-test-${cluster_name}
#SBATCH --nodes=2
#SBATCH --ntasks-per-node=8
#SBATCH --time=00:10:00
#SBATCH --output=output_%j.log
#SBATCH --error=error_%j.log

# Load required modules
module load openmpi

# Print job information
echo "Job started at: $(date)"
echo "Running on cluster: ${cluster_name}"
echo "Job ID: $SLURM_JOB_ID"
echo "Nodes: $SLURM_JOB_NODELIST"
echo "Tasks per node: $SLURM_NTASKS_PER_NODE"
echo "Total tasks: $SLURM_NTASKS"

# Run MPI test
echo "Running MPI hostname test..."
mpirun -np $SLURM_NTASKS hostname

# Simple computational test
echo "Running simple computational test..."
mpirun -np $SLURM_NTASKS python3 -c "
import socket
import time
import sys
from mpi4py import MPI

comm = MPI.COMM_WORLD
rank = comm.Get_rank()
size = comm.Get_size()

hostname = socket.gethostname()
print(f'Rank {rank}/{size} on {hostname}')

# Simple computation
start_time = time.time()
result = sum(i**2 for i in range(1000000))
end_time = time.time()

print(f'Rank {rank} computed {result} in {end_time - start_time:.2f} seconds')
"

echo "Job completed at: $(date)"
EOF
  filename = "${path.module}/templates/sample_job.sh.tpl"
}