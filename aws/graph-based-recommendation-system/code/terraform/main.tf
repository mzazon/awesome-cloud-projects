# Main Terraform Configuration for Neptune Graph Database Recommendation Engine
# This file contains all the infrastructure resources needed for the recipe

# Data sources for availability zones and AMI
data "aws_availability_zones" "available" {
  state = "available"
}

data "aws_ami" "amazon_linux" {
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

data "aws_caller_identity" "current" {}

# Generate random suffix for unique resource naming
resource "random_id" "suffix" {
  byte_length = 3
}

locals {
  # Use provided cluster identifier or generate one
  cluster_identifier = var.neptune_cluster_identifier != "" ? var.neptune_cluster_identifier : "${var.project_name}-${random_id.suffix.hex}"
  
  # Use provided S3 bucket name or generate one
  s3_bucket_name = var.s3_bucket_name != "" ? var.s3_bucket_name : "${var.project_name}-sample-data-${random_id.suffix.hex}"
  
  # Use provided key pair name or generate one
  key_pair_name = var.ec2_key_pair_name != "" ? var.ec2_key_pair_name : "${var.project_name}-keypair-${random_id.suffix.hex}"
  
  # Determine availability zones to use
  availability_zones = length(var.availability_zones) > 0 ? var.availability_zones : slice(data.aws_availability_zones.available.names, 0, 3)
  
  # Common tags for all resources
  common_tags = merge(
    {
      Name        = var.project_name
      Environment = var.environment
      Recipe      = "graph-databases-recommendation-engines-amazon-neptune"
    },
    var.additional_tags
  )
}

# ============================================================================
# VPC and Networking Resources
# ============================================================================

# Create VPC for Neptune cluster
resource "aws_vpc" "neptune_vpc" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-vpc"
  })
}

# Internet Gateway for public subnet access
resource "aws_internet_gateway" "neptune_igw" {
  vpc_id = aws_vpc.neptune_vpc.id

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-igw"
  })
}

# Private subnets for Neptune cluster (Multi-AZ)
resource "aws_subnet" "neptune_private_subnets" {
  count = length(var.private_subnet_cidrs)

  vpc_id            = aws_vpc.neptune_vpc.id
  cidr_block        = var.private_subnet_cidrs[count.index]
  availability_zone = local.availability_zones[count.index]

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-private-subnet-${count.index + 1}"
    Type = "Private"
  })
}

# Public subnets for EC2 client instance
resource "aws_subnet" "neptune_public_subnets" {
  count = length(var.public_subnet_cidrs)

  vpc_id                  = aws_vpc.neptune_vpc.id
  cidr_block              = var.public_subnet_cidrs[count.index]
  availability_zone       = local.availability_zones[count.index]
  map_public_ip_on_launch = true

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-public-subnet-${count.index + 1}"
    Type = "Public"
  })
}

# Route table for public subnets
resource "aws_route_table" "neptune_public_rt" {
  vpc_id = aws_vpc.neptune_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.neptune_igw.id
  }

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-public-rt"
  })
}

# Route table associations for public subnets
resource "aws_route_table_association" "neptune_public_rta" {
  count = length(aws_subnet.neptune_public_subnets)

  subnet_id      = aws_subnet.neptune_public_subnets[count.index].id
  route_table_id = aws_route_table.neptune_public_rt.id
}

# ============================================================================
# Security Groups
# ============================================================================

# Security group for Neptune cluster
resource "aws_security_group" "neptune_sg" {
  name_prefix = "${var.project_name}-neptune-"
  vpc_id      = aws_vpc.neptune_vpc.id
  description = "Security group for Neptune cluster"

  # Allow Neptune port access from within VPC
  ingress {
    description = "Neptune Gremlin/SPARQL access from VPC"
    from_port   = 8182
    to_port     = 8182
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  # Allow all outbound traffic
  egress {
    description = "All outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-neptune-sg"
  })
}

# Security group for EC2 client instance
resource "aws_security_group" "ec2_client_sg" {
  name_prefix = "${var.project_name}-ec2-client-"
  vpc_id      = aws_vpc.neptune_vpc.id
  description = "Security group for EC2 client instance"

  # SSH access
  ingress {
    description = "SSH access"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = var.allowed_cidr_blocks
  }

  # HTTP access (for development purposes)
  ingress {
    description = "HTTP access"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = var.allowed_cidr_blocks
  }

  # HTTPS access (for development purposes)
  ingress {
    description = "HTTPS access"
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

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-ec2-client-sg"
  })
}

# ============================================================================
# Neptune Cluster Configuration
# ============================================================================

# Neptune subnet group for Multi-AZ deployment
resource "aws_neptune_subnet_group" "neptune_subnet_group" {
  name       = "${local.cluster_identifier}-subnet-group"
  subnet_ids = aws_subnet.neptune_private_subnets[*].id

  tags = merge(local.common_tags, {
    Name = "${local.cluster_identifier}-subnet-group"
  })
}

# Neptune parameter group for custom configurations
resource "aws_neptune_parameter_group" "neptune_params" {
  family      = "neptune1.3"
  name        = "${local.cluster_identifier}-params"
  description = "Neptune parameter group for ${var.project_name}"

  parameter {
    name  = "neptune_enable_audit_log"
    value = var.enable_cloudwatch_logs ? "1" : "0"
  }

  tags = merge(local.common_tags, {
    Name = "${local.cluster_identifier}-params"
  })
}

# Neptune cluster parameter group
resource "aws_neptune_cluster_parameter_group" "neptune_cluster_params" {
  family      = "neptune1.3"
  name        = "${local.cluster_identifier}-cluster-params"
  description = "Neptune cluster parameter group for ${var.project_name}"

  parameter {
    name  = "neptune_enable_audit_log"
    value = var.enable_cloudwatch_logs ? "1" : "0"
  }

  tags = merge(local.common_tags, {
    Name = "${local.cluster_identifier}-cluster-params"
  })
}

# CloudWatch Log Groups for Neptune (if enabled)
resource "aws_cloudwatch_log_group" "neptune_audit_log" {
  count = var.enable_cloudwatch_logs ? 1 : 0

  name              = "/aws/neptune/${local.cluster_identifier}/audit"
  retention_in_days = var.cloudwatch_log_retention_days

  tags = merge(local.common_tags, {
    Name = "${local.cluster_identifier}-audit-log"
  })
}

# Neptune cluster
resource "aws_neptune_cluster" "neptune_cluster" {
  cluster_identifier                  = local.cluster_identifier
  engine                             = "neptune"
  engine_version                     = var.neptune_engine_version
  backup_retention_period            = var.neptune_backup_retention_period
  preferred_backup_window            = var.neptune_backup_window
  preferred_maintenance_window       = var.neptune_maintenance_window
  db_subnet_group_name               = aws_neptune_subnet_group.neptune_subnet_group.name
  vpc_security_group_ids             = [aws_security_group.neptune_sg.id]
  storage_encrypted                  = var.neptune_storage_encrypted
  kms_key_arn                        = var.neptune_kms_key_id != "" ? var.neptune_kms_key_id : null
  deletion_protection                = var.enable_deletion_protection
  apply_immediately                  = var.apply_immediately
  neptune_cluster_parameter_group_name = aws_neptune_cluster_parameter_group.neptune_cluster_params.name
  
  # Enable audit logging if CloudWatch logs are enabled
  dynamic "enable_cloudwatch_logs_exports" {
    for_each = var.enable_cloudwatch_logs ? ["audit"] : []
    content {
      enable_cloudwatch_logs_exports = ["audit"]
    }
  }

  # Skip final snapshot for development environments
  skip_final_snapshot = var.environment != "prod"
  final_snapshot_identifier = var.environment == "prod" ? "${local.cluster_identifier}-final-snapshot-${formatdate("YYYY-MM-DD-hhmm", timestamp())}" : null

  tags = merge(local.common_tags, {
    Name = local.cluster_identifier
  })

  depends_on = [
    aws_cloudwatch_log_group.neptune_audit_log
  ]
}

# Neptune primary instance
resource "aws_neptune_cluster_instance" "neptune_primary" {
  identifier                   = "${local.cluster_identifier}-primary"
  cluster_identifier          = aws_neptune_cluster.neptune_cluster.id
  instance_class               = var.neptune_instance_class
  engine                       = aws_neptune_cluster.neptune_cluster.engine
  engine_version               = aws_neptune_cluster.neptune_cluster.engine_version
  publicly_accessible         = false
  neptune_parameter_group_name = aws_neptune_parameter_group.neptune_params.name
  auto_minor_version_upgrade   = var.enable_auto_minor_version_upgrade
  apply_immediately            = var.apply_immediately

  tags = merge(local.common_tags, {
    Name = "${local.cluster_identifier}-primary"
    Role = "Primary"
  })
}

# Neptune read replicas
resource "aws_neptune_cluster_instance" "neptune_replicas" {
  count = var.neptune_replica_count

  identifier                   = "${local.cluster_identifier}-replica-${count.index + 1}"
  cluster_identifier          = aws_neptune_cluster.neptune_cluster.id
  instance_class               = var.neptune_instance_class
  engine                       = aws_neptune_cluster.neptune_cluster.engine
  engine_version               = aws_neptune_cluster.neptune_cluster.engine_version
  publicly_accessible         = false
  neptune_parameter_group_name = aws_neptune_parameter_group.neptune_params.name
  auto_minor_version_upgrade   = var.enable_auto_minor_version_upgrade
  apply_immediately            = var.apply_immediately

  tags = merge(local.common_tags, {
    Name = "${local.cluster_identifier}-replica-${count.index + 1}"
    Role = "Replica"
  })
}

# ============================================================================
# S3 Bucket for Sample Data
# ============================================================================

# S3 bucket for storing sample graph data
resource "aws_s3_bucket" "sample_data_bucket" {
  bucket        = local.s3_bucket_name
  force_destroy = var.s3_force_destroy

  tags = merge(local.common_tags, {
    Name    = local.s3_bucket_name
    Purpose = "Sample data storage for Neptune recommendation engine"
  })
}

# S3 bucket versioning
resource "aws_s3_bucket_versioning" "sample_data_versioning" {
  bucket = aws_s3_bucket.sample_data_bucket.id
  versioning_configuration {
    status = "Enabled"
  }
}

# S3 bucket server-side encryption
resource "aws_s3_bucket_server_side_encryption_configuration" "sample_data_encryption" {
  bucket = aws_s3_bucket.sample_data_bucket.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
    bucket_key_enabled = true
  }
}

# S3 bucket public access block
resource "aws_s3_bucket_public_access_block" "sample_data_pab" {
  bucket = aws_s3_bucket.sample_data_bucket.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Upload sample data files to S3
resource "aws_s3_object" "sample_users" {
  bucket = aws_s3_bucket.sample_data_bucket.id
  key    = "sample-users.csv"
  content = <<EOF
id,name,age,city,interests
user1,Alice,28,Seattle,books;technology;travel
user2,Bob,35,Portland,sports;music;cooking
user3,Carol,42,Vancouver,art;books;photography
user4,David,31,San Francisco,technology;gaming;fitness
user5,Eve,26,Los Angeles,fashion;travel;music
EOF

  tags = merge(local.common_tags, {
    Name = "sample-users.csv"
    Type = "SampleData"
  })
}

resource "aws_s3_object" "sample_products" {
  bucket = aws_s3_bucket.sample_data_bucket.id
  key    = "sample-products.csv"
  content = <<EOF
id,name,category,price,brand,tags
prod1,Laptop,Electronics,999.99,TechCorp,technology;work;portable
prod2,Running Shoes,Sports,129.99,SportsBrand,fitness;running;comfort
prod3,Camera,Electronics,599.99,PhotoPro,photography;hobby;travel
prod4,Cookbook,Books,29.99,FoodPress,cooking;recipes;kitchen
prod5,Headphones,Electronics,199.99,AudioMax,music;technology;wireless
EOF

  tags = merge(local.common_tags, {
    Name = "sample-products.csv"
    Type = "SampleData"
  })
}

resource "aws_s3_object" "sample_purchases" {
  bucket = aws_s3_bucket.sample_data_bucket.id
  key    = "sample-purchases.csv"
  content = <<EOF
user_id,product_id,quantity,purchase_date,rating
user1,prod1,1,2024-01-15,5
user1,prod3,1,2024-01-20,4
user2,prod2,1,2024-01-18,5
user2,prod4,2,2024-01-25,4
user3,prod3,1,2024-01-22,5
user3,prod4,1,2024-01-28,3
user4,prod1,1,2024-01-30,4
user4,prod5,1,2024-02-02,5
user5,prod5,1,2024-02-05,4
EOF

  tags = merge(local.common_tags, {
    Name = "sample-purchases.csv"
    Type = "SampleData"
  })
}

# ============================================================================
# EC2 Key Pair and Instance
# ============================================================================

# Generate TLS private key for EC2 key pair
resource "tls_private_key" "ec2_key" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

# Create EC2 key pair
resource "aws_key_pair" "ec2_key_pair" {
  key_name   = local.key_pair_name
  public_key = tls_private_key.ec2_key.public_key_openssh

  tags = merge(local.common_tags, {
    Name = local.key_pair_name
  })
}

# IAM role for EC2 instance (for S3 access and CloudWatch logs)
resource "aws_iam_role" "ec2_neptune_client_role" {
  name = "${var.project_name}-ec2-neptune-client-role"

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

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-ec2-neptune-client-role"
  })
}

# IAM policy for Neptune access
resource "aws_iam_role_policy" "ec2_neptune_access" {
  name = "${var.project_name}-ec2-neptune-access"
  role = aws_iam_role.ec2_neptune_client_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "neptune-db:*",
          "neptune:*"
        ]
        Resource = [
          aws_neptune_cluster.neptune_cluster.arn,
          "${aws_neptune_cluster.neptune_cluster.arn}/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:ListBucket"
        ]
        Resource = [
          aws_s3_bucket.sample_data_bucket.arn,
          "${aws_s3_bucket.sample_data_bucket.arn}/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "logs:DescribeLogStreams"
        ]
        Resource = "arn:aws:logs:*:*:*"
      }
    ]
  })
}

# Attach AWS managed policy for SSM access (optional for debugging)
resource "aws_iam_role_policy_attachment" "ec2_ssm_policy" {
  role       = aws_iam_role.ec2_neptune_client_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# IAM instance profile for EC2
resource "aws_iam_instance_profile" "ec2_neptune_client_profile" {
  name = "${var.project_name}-ec2-neptune-client-profile"
  role = aws_iam_role.ec2_neptune_client_role.name

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-ec2-neptune-client-profile"
  })
}

# User data script for EC2 instance initialization
locals {
  default_user_data = <<-EOF
#!/bin/bash
yum update -y
yum install -y python3 python3-pip git

# Install Python packages for Neptune
pip3 install gremlinpython boto3 requests

# Install AWS CLI v2
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
./aws/install

# Create neptune configuration directory
mkdir -p /home/ec2-user/neptune-config
chown ec2-user:ec2-user /home/ec2-user/neptune-config

# Create environment variables file
cat > /home/ec2-user/neptune-config/neptune-env.sh << 'EOL'
export NEPTUNE_ENDPOINT="${aws_neptune_cluster.neptune_cluster.endpoint}"
export NEPTUNE_READ_ENDPOINT="${aws_neptune_cluster.neptune_cluster.reader_endpoint}"
export NEPTUNE_PORT="8182"
export S3_BUCKET="${aws_s3_bucket.sample_data_bucket.id}"
export AWS_REGION="${var.aws_region}"
EOL

chown ec2-user:ec2-user /home/ec2-user/neptune-config/neptune-env.sh

# Create sample Gremlin scripts
cat > /home/ec2-user/neptune-config/load-data.groovy << 'EOL'
// Clear existing data
g.V().drop().iterate()

// Create user vertices
g.addV('user').property('id', 'user1').property('name', 'Alice').property('age', 28).property('city', 'Seattle').next()
g.addV('user').property('id', 'user2').property('name', 'Bob').property('age', 35).property('city', 'Portland').next()
g.addV('user').property('id', 'user3').property('name', 'Carol').property('age', 42).property('city', 'Vancouver').next()
g.addV('user').property('id', 'user4').property('name', 'David').property('age', 31).property('city', 'San Francisco').next()
g.addV('user').property('id', 'user5').property('name', 'Eve').property('age', 26).property('city', 'Los Angeles').next()

// Create product vertices
g.addV('product').property('id', 'prod1').property('name', 'Laptop').property('category', 'Electronics').property('price', 999.99).next()
g.addV('product').property('id', 'prod2').property('name', 'Running Shoes').property('category', 'Sports').property('price', 129.99).next()
g.addV('product').property('id', 'prod3').property('name', 'Camera').property('category', 'Electronics').property('price', 599.99).next()
g.addV('product').property('id', 'prod4').property('name', 'Cookbook').property('category', 'Books').property('price', 29.99).next()
g.addV('product').property('id', 'prod5').property('name', 'Headphones').property('category', 'Electronics').property('price', 199.99).next()

// Create purchase relationships
g.V().has('user', 'id', 'user1').as('u').V().has('product', 'id', 'prod1').addE('purchased').from('u').property('rating', 5).property('date', '2024-01-15').next()
g.V().has('user', 'id', 'user1').as('u').V().has('product', 'id', 'prod3').addE('purchased').from('u').property('rating', 4).property('date', '2024-01-20').next()
g.V().has('user', 'id', 'user2').as('u').V().has('product', 'id', 'prod2').addE('purchased').from('u').property('rating', 5).property('date', '2024-01-18').next()
g.V().has('user', 'id', 'user2').as('u').V().has('product', 'id', 'prod4').addE('purchased').from('u').property('rating', 4).property('date', '2024-01-25').next()
g.V().has('user', 'id', 'user3').as('u').V().has('product', 'id', 'prod3').addE('purchased').from('u').property('rating', 5).property('date', '2024-01-22').next()
g.V().has('user', 'id', 'user3').as('u').V().has('product', 'id', 'prod4').addE('purchased').from('u').property('rating', 3).property('date', '2024-01-28').next()
g.V().has('user', 'id', 'user4').as('u').V().has('product', 'id', 'prod1').addE('purchased').from('u').property('rating', 4).property('date', '2024-01-30').next()
g.V().has('user', 'id', 'user4').as('u').V().has('product', 'id', 'prod5').addE('purchased').from('u').property('rating', 5).property('date', '2024-02-02').next()
g.V().has('user', 'id', 'user5').as('u').V().has('product', 'id', 'prod5').addE('purchased').from('u').property('rating', 4).property('date', '2024-02-05').next()

// Create category relationships
g.V().has('product', 'category', 'Electronics').as('p1').V().has('product', 'category', 'Electronics').as('p2').where(neq('p1')).addE('same_category').from('p1').to('p2').next()

// Commit the transaction
g.tx().commit()

println "Data loaded successfully"
EOL

chown ec2-user:ec2-user /home/ec2-user/neptune-config/load-data.groovy

# Create Python connection test script
cat > /home/ec2-user/neptune-config/test-connection.py << 'EOL'
#!/usr/bin/env python3
import sys
import os
from gremlin_python.driver.driver_remote_connection import DriverRemoteConnection
from gremlin_python.structure.graph import Graph

def test_neptune_connection():
    try:
        endpoint = os.environ.get('NEPTUNE_ENDPOINT')
        if not endpoint:
            print("Error: NEPTUNE_ENDPOINT environment variable not set")
            return False
            
        # Create connection
        connection_string = f'wss://{endpoint}:8182/gremlin'
        print(f"Connecting to: {connection_string}")
        
        connection = DriverRemoteConnection(connection_string, 'g')
        g = Graph().traversal().withRemote(connection)
        
        # Test basic connectivity
        vertex_count = g.V().count().next()
        edge_count = g.E().count().next()
        
        print(f"✅ Connected to Neptune successfully!")
        print(f"Graph contains {vertex_count} vertices and {edge_count} edges")
        
        # Test sample queries if data exists
        if vertex_count > 0:
            users = g.V().hasLabel('user').valueMap().limit(3).toList()
            products = g.V().hasLabel('product').valueMap().limit(3).toList()
            
            print("\nSample Users:")
            for user in users:
                print(f"  {user}")
            
            print("\nSample Products:")
            for product in products:
                print(f"  {product}")
        
        connection.close()
        return True
        
    except Exception as e:
        print(f"❌ Connection failed: {e}")
        return False

if __name__ == "__main__":
    # Source environment variables
    os.system("source /home/ec2-user/neptune-config/neptune-env.sh")
    test_neptune_connection()
EOL

chmod +x /home/ec2-user/neptune-config/test-connection.py
chown ec2-user:ec2-user /home/ec2-user/neptune-config/test-connection.py

# Add neptune environment to .bashrc
echo "source /home/ec2-user/neptune-config/neptune-env.sh" >> /home/ec2-user/.bashrc

# Install additional development tools
yum install -y htop tree vim

# Log completion
echo "EC2 instance initialization completed at $(date)" >> /var/log/user-data.log
EOF

  user_data_script = var.ec2_user_data_script != "" ? var.ec2_user_data_script : local.default_user_data
}

# EC2 instance for Neptune client
resource "aws_instance" "neptune_client" {
  ami                         = data.aws_ami.amazon_linux.id
  instance_type               = var.ec2_instance_type
  key_name                    = aws_key_pair.ec2_key_pair.key_name
  vpc_security_group_ids      = [aws_security_group.ec2_client_sg.id]
  subnet_id                   = aws_subnet.neptune_public_subnets[0].id
  associate_public_ip_address = var.ec2_associate_public_ip
  iam_instance_profile        = aws_iam_instance_profile.ec2_neptune_client_profile.name

  user_data = base64encode(local.user_data_script)

  root_block_device {
    volume_type           = "gp3"
    volume_size           = 20
    encrypted             = true
    delete_on_termination = true

    tags = merge(local.common_tags, {
      Name = "${var.project_name}-ec2-client-root"
    })
  }

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-neptune-client"
    Type = "NeptuneClient"
  })

  # Wait for Neptune cluster to be available
  depends_on = [
    aws_neptune_cluster.neptune_cluster,
    aws_neptune_cluster_instance.neptune_primary
  ]
}

# ============================================================================
# Local File for Private Key (Optional - for development)
# ============================================================================

# Save private key to local file (only for development environments)
resource "local_file" "private_key" {
  count = var.environment != "prod" ? 1 : 0

  content         = tls_private_key.ec2_key.private_key_pem
  filename        = "${local.key_pair_name}.pem"
  file_permission = "0400"
}