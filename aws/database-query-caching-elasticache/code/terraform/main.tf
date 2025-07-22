# Main Terraform Configuration for Database Query Caching with ElastiCache
# This configuration creates a complete caching infrastructure with Redis and MySQL

# Random suffix for unique resource naming
resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
}

# Local values for consistent naming and configuration
locals {
  name_prefix = "${var.project_name}-${var.environment}"
  common_tags = merge(
    {
      Name        = local.name_prefix
      Environment = var.environment
      Project     = var.project_name
    },
    var.additional_tags
  )
}

# Data source to get default VPC if not provided
data "aws_vpc" "selected" {
  id      = var.vpc_id
  default = var.vpc_id == null ? true : null
}

# Data source to get subnets if not provided
data "aws_subnets" "selected" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.selected.id]
  }

  # Only use provided subnet IDs if they're specified
  tags = length(var.subnet_ids) > 0 ? null : {}
}

data "aws_subnet" "selected" {
  count = length(var.subnet_ids) > 0 ? length(var.subnet_ids) : length(data.aws_subnets.selected.ids)
  id    = length(var.subnet_ids) > 0 ? var.subnet_ids[count.index] : data.aws_subnets.selected.ids[count.index]
}

# Get the latest Amazon Linux 2 AMI for EC2 instance
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

# Random password for RDS if not provided
resource "random_password" "rds_password" {
  count   = var.create_rds_instance && var.rds_master_password == null ? 1 : 0
  length  = 16
  special = true
}

# Security Group for ElastiCache Redis
resource "aws_security_group" "redis" {
  name_prefix = "${local.name_prefix}-redis-"
  description = "Security group for ElastiCache Redis cluster"
  vpc_id      = data.aws_vpc.selected.id

  # Allow Redis access from VPC CIDR
  ingress {
    description = "Redis access from VPC"
    from_port   = var.redis_port
    to_port     = var.redis_port
    protocol    = "tcp"
    cidr_blocks = [data.aws_vpc.selected.cidr_block]
  }

  # Allow Redis access from additional CIDR blocks if specified
  dynamic "ingress" {
    for_each = length(var.allowed_cidr_blocks) > 0 ? [1] : []
    content {
      description = "Redis access from allowed CIDR blocks"
      from_port   = var.redis_port
      to_port     = var.redis_port
      protocol    = "tcp"
      cidr_blocks = var.allowed_cidr_blocks
    }
  }

  egress {
    description = "All outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-redis-sg"
    Type = "Redis Security Group"
  })

  lifecycle {
    create_before_destroy = true
  }
}

# Security Group for RDS MySQL
resource "aws_security_group" "rds" {
  count = var.create_rds_instance ? 1 : 0

  name_prefix = "${local.name_prefix}-rds-"
  description = "Security group for RDS MySQL database"
  vpc_id      = data.aws_vpc.selected.id

  # Allow MySQL access from VPC CIDR
  ingress {
    description = "MySQL access from VPC"
    from_port   = 3306
    to_port     = 3306
    protocol    = "tcp"
    cidr_blocks = [data.aws_vpc.selected.cidr_block]
  }

  # Allow MySQL access from additional CIDR blocks if specified
  dynamic "ingress" {
    for_each = length(var.allowed_cidr_blocks) > 0 ? [1] : []
    content {
      description = "MySQL access from allowed CIDR blocks"
      from_port   = 3306
      to_port     = 3306
      protocol    = "tcp"
      cidr_blocks = var.allowed_cidr_blocks
    }
  }

  egress {
    description = "All outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-rds-sg"
    Type = "RDS Security Group"
  })

  lifecycle {
    create_before_destroy = true
  }
}

# Security Group for EC2 instance
resource "aws_security_group" "ec2" {
  count = var.create_ec2_instance ? 1 : 0

  name_prefix = "${local.name_prefix}-ec2-"
  description = "Security group for EC2 test instance"
  vpc_id      = data.aws_vpc.selected.id

  # Allow SSH access from anywhere (adjust as needed for security)
  ingress {
    description = "SSH access"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = length(var.allowed_cidr_blocks) > 0 ? var.allowed_cidr_blocks : ["0.0.0.0/0"]
  }

  # Allow HTTP access for testing
  ingress {
    description = "HTTP access"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "All outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-ec2-sg"
    Type = "EC2 Security Group"
  })

  lifecycle {
    create_before_destroy = true
  }
}

# ElastiCache Subnet Group
resource "aws_elasticache_subnet_group" "redis" {
  name       = "${local.name_prefix}-subnet-group-${random_string.suffix.result}"
  subnet_ids = length(var.subnet_ids) > 0 ? var.subnet_ids : data.aws_subnets.selected.ids

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-redis-subnet-group"
    Type = "ElastiCache Subnet Group"
  })
}

# ElastiCache Parameter Group for Redis optimization
resource "aws_elasticache_parameter_group" "redis" {
  family = "redis${var.redis_engine_version}"
  name   = "${local.name_prefix}-params-${random_string.suffix.result}"

  # Configure maxmemory policy for LRU eviction (optimal for caching)
  parameter {
    name  = "maxmemory-policy"
    value = "allkeys-lru"
  }

  # Enable Redis notifications for cache events
  parameter {
    name  = "notify-keyspace-events"
    value = "Ex"
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-redis-params"
    Type = "ElastiCache Parameter Group"
  })

  lifecycle {
    create_before_destroy = true
  }
}

# ElastiCache Redis Replication Group
resource "aws_elasticache_replication_group" "redis" {
  replication_group_id       = "${local.name_prefix}-${random_string.suffix.result}"
  description                = "Redis cluster for database query caching"
  
  # Network Configuration
  subnet_group_name   = aws_elasticache_subnet_group.redis.name
  security_group_ids  = [aws_security_group.redis.id]
  port                = var.redis_port

  # Engine Configuration
  engine               = "redis"
  engine_version       = var.redis_engine_version
  node_type            = var.redis_node_type
  parameter_group_name = aws_elasticache_parameter_group.redis.name

  # High Availability Configuration
  num_cache_clusters         = var.redis_num_cache_clusters
  automatic_failover_enabled = var.redis_automatic_failover_enabled
  multi_az_enabled          = var.redis_multi_az_enabled

  # Security Configuration
  at_rest_encryption_enabled = var.redis_at_rest_encryption_enabled
  transit_encryption_enabled = var.redis_transit_encryption_enabled

  # Logging Configuration
  log_delivery_configuration {
    destination      = aws_cloudwatch_log_group.redis_slow[0].name
    destination_type = "cloudwatch-logs"
    log_format       = "json"
    log_type         = "slow-log"
  }

  # Maintenance and Backup Configuration
  maintenance_window         = "sun:05:00-sun:06:00"
  snapshot_retention_limit   = 3
  snapshot_window           = "03:00-04:00"
  final_snapshot_identifier = "${local.name_prefix}-final-snapshot-${random_string.suffix.result}"

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-redis-cluster"
    Type = "ElastiCache Redis Replication Group"
  })

  depends_on = [
    aws_cloudwatch_log_group.redis_slow
  ]
}

# CloudWatch Log Group for Redis slow log
resource "aws_cloudwatch_log_group" "redis_slow" {
  count = var.enable_cloudwatch_logs ? 1 : 0

  name              = "/aws/elasticache/redis/${local.name_prefix}-slow-log"
  retention_in_days = 7

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-redis-slow-log"
    Type = "CloudWatch Log Group"
  })
}

# RDS DB Subnet Group
resource "aws_db_subnet_group" "rds" {
  count = var.create_rds_instance ? 1 : 0

  name       = "${local.name_prefix}-db-subnet-group-${random_string.suffix.result}"
  subnet_ids = length(var.subnet_ids) > 0 ? var.subnet_ids : data.aws_subnets.selected.ids

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-rds-subnet-group"
    Type = "RDS Subnet Group"
  })
}

# RDS MySQL Database Instance
resource "aws_db_instance" "mysql" {
  count = var.create_rds_instance ? 1 : 0

  # Basic Configuration
  identifier     = "${local.name_prefix}-mysql-${random_string.suffix.result}"
  engine         = var.rds_engine
  engine_version = var.rds_engine_version
  instance_class = var.rds_instance_class

  # Database Configuration
  allocated_storage     = var.rds_allocated_storage
  storage_type         = "gp2"
  storage_encrypted    = true

  # Credentials
  db_name  = "testdb"
  username = var.rds_master_username
  password = var.rds_master_password != null ? var.rds_master_password : random_password.rds_password[0].result

  # Network Configuration
  db_subnet_group_name   = aws_db_subnet_group.rds[0].name
  vpc_security_group_ids = [aws_security_group.rds[0].id]
  publicly_accessible    = var.rds_publicly_accessible

  # High Availability and Backup Configuration
  multi_az               = var.rds_multi_az
  backup_retention_period = var.rds_backup_retention_period
  backup_window          = "07:00-08:00"
  maintenance_window     = "sun:08:00-sun:09:00"

  # Performance and Monitoring
  performance_insights_enabled = true
  monitoring_interval         = 60
  monitoring_role_arn        = aws_iam_role.rds_monitoring[0].arn

  # Additional Configuration
  skip_final_snapshot = true
  deletion_protection = false

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-mysql-db"
    Type = "RDS MySQL Database"
  })

  depends_on = [
    aws_iam_role.rds_monitoring
  ]
}

# IAM Role for RDS Enhanced Monitoring
resource "aws_iam_role" "rds_monitoring" {
  count = var.create_rds_instance ? 1 : 0

  name_prefix = "${local.name_prefix}-rds-monitoring-"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "monitoring.rds.amazonaws.com"
        }
      }
    ]
  })

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-rds-monitoring-role"
    Type = "IAM Role"
  })
}

# IAM Role Policy Attachment for RDS Enhanced Monitoring
resource "aws_iam_role_policy_attachment" "rds_monitoring" {
  count = var.create_rds_instance ? 1 : 0

  role       = aws_iam_role.rds_monitoring[0].name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonRDSEnhancedMonitoringRole"
}

# IAM Role for EC2 instance
resource "aws_iam_role" "ec2" {
  count = var.create_ec2_instance ? 1 : 0

  name_prefix = "${local.name_prefix}-ec2-role-"

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
    Name = "${local.name_prefix}-ec2-role"
    Type = "IAM Role"
  })
}

# IAM Instance Profile for EC2
resource "aws_iam_instance_profile" "ec2" {
  count = var.create_ec2_instance ? 1 : 0

  name_prefix = "${local.name_prefix}-ec2-profile-"
  role        = aws_iam_role.ec2[0].name

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-ec2-instance-profile"
    Type = "IAM Instance Profile"
  })
}

# IAM Policy for EC2 to access CloudWatch and other AWS services
resource "aws_iam_role_policy" "ec2_policy" {
  count = var.create_ec2_instance ? 1 : 0

  name_prefix = "${local.name_prefix}-ec2-policy-"
  role        = aws_iam_role.ec2[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "cloudwatch:PutMetricData",
          "cloudwatch:GetMetricStatistics",
          "cloudwatch:ListMetrics",
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "logs:DescribeLogStreams"
        ]
        Resource = "*"
      }
    ]
  })
}

# User data script for EC2 instance setup
locals {
  user_data = base64encode(templatefile("${path.module}/user_data.sh", {
    redis_endpoint = aws_elasticache_replication_group.redis.primary_endpoint_address
    mysql_endpoint = var.create_rds_instance ? aws_db_instance.mysql[0].address : "localhost"
    mysql_username = var.rds_master_username
    mysql_password = var.create_rds_instance ? (var.rds_master_password != null ? var.rds_master_password : random_password.rds_password[0].result) : "password"
  }))
}

# Create user data script file
resource "local_file" "user_data_script" {
  count = var.create_ec2_instance ? 1 : 0

  filename = "${path.module}/user_data.sh"
  content = templatefile("${path.module}/user_data_template.sh", {
    redis_endpoint = aws_elasticache_replication_group.redis.primary_endpoint_address
    mysql_endpoint = var.create_rds_instance ? aws_db_instance.mysql[0].address : "localhost"
    mysql_username = var.rds_master_username
    mysql_password = var.create_rds_instance ? (var.rds_master_password != null ? var.rds_master_password : random_password.rds_password[0].result) : "password"
  })

  provisioner "local-exec" {
    command = "chmod +x ${path.module}/user_data.sh"
  }
}

# Create user data template
resource "local_file" "user_data_template" {
  filename = "${path.module}/user_data_template.sh"
  content  = <<-EOF
#!/bin/bash
# User Data Script for Database Query Caching Demo
# This script installs and configures the necessary tools for testing

# Update system packages
yum update -y

# Install Redis CLI and MySQL client
yum install -y redis mysql

# Install Python 3 and pip
amazon-linux-extras install -y python3.8
pip3 install redis pymysql boto3

# Set environment variables for applications
echo "export REDIS_HOST=${redis_endpoint}" >> /etc/environment
echo "export MYSQL_HOST=${mysql_endpoint}" >> /etc/environment
echo "export MYSQL_USER=${mysql_username}" >> /etc/environment
echo "export MYSQL_PASSWORD=${mysql_password}" >> /etc/environment
echo "export MYSQL_DB=testdb" >> /etc/environment

# Create cache demo script
cat > /home/ec2-user/cache_demo.py << 'SCRIPT_EOF'
import redis
import pymysql
import json
import time
import sys
import os

# Configuration from environment variables
REDIS_HOST = os.environ.get('REDIS_HOST', 'localhost')
MYSQL_HOST = os.environ.get('MYSQL_HOST', 'localhost')
MYSQL_USER = os.environ.get('MYSQL_USER', 'admin')
MYSQL_PASSWORD = os.environ.get('MYSQL_PASSWORD', 'password')
MYSQL_DB = os.environ.get('MYSQL_DB', 'testdb')

def test_redis_connection():
    """Test Redis connectivity"""
    try:
        redis_client = redis.Redis(host=REDIS_HOST, port=6379, decode_responses=True)
        response = redis_client.ping()
        print(f"✅ Redis connection successful: {response}")
        return redis_client
    except Exception as e:
        print(f"❌ Redis connection failed: {e}")
        return None

def test_mysql_connection():
    """Test MySQL connectivity"""
    try:
        connection = pymysql.connect(
            host=MYSQL_HOST,
            user=MYSQL_USER,
            password=MYSQL_PASSWORD,
            autocommit=True
        )
        print("✅ MySQL connection successful")
        return connection
    except Exception as e:
        print(f"❌ MySQL connection failed: {e}")
        return None

def cache_aside_demo(redis_client):
    """Demonstrate cache-aside pattern"""
    print("\n=== Cache-Aside Pattern Demo ===")
    
    # Set a test value in cache
    key = "product:123"
    value = {"id": 123, "name": "Test Product", "price": 29.99}
    
    # Store in cache with 300 second TTL
    redis_client.setex(key, 300, json.dumps(value))
    print(f"✅ Stored in cache: {key}")
    
    # Retrieve from cache
    cached_value = redis_client.get(key)
    if cached_value:
        print(f"✅ Retrieved from cache: {json.loads(cached_value)}")
    
    # Test cache expiration
    ttl = redis_client.ttl(key)
    print(f"📅 TTL remaining: {ttl} seconds")

def performance_demo(redis_client):
    """Demonstrate performance difference"""
    print("\n=== Performance Comparison Demo ===")
    
    # Test cache write performance
    start_time = time.time()
    for i in range(100):
        redis_client.set(f"perf_test:{i}", f"value_{i}", ex=60)
    cache_write_time = time.time() - start_time
    print(f"🚀 Cache write (100 operations): {cache_write_time:.4f} seconds")
    
    # Test cache read performance
    start_time = time.time()
    for i in range(100):
        value = redis_client.get(f"perf_test:{i}")
    cache_read_time = time.time() - start_time
    print(f"🚀 Cache read (100 operations): {cache_read_time:.4f} seconds")
    
    print(f"📊 Average cache read latency: {(cache_read_time/100)*1000:.2f} ms per operation")

def main():
    """Main demo function"""
    print("=== Database Query Caching Demo ===")
    print(f"Redis Host: {REDIS_HOST}")
    print(f"MySQL Host: {MYSQL_HOST}")
    
    # Test connections
    redis_client = test_redis_connection()
    mysql_connection = test_mysql_connection()
    
    if redis_client:
        cache_aside_demo(redis_client)
        performance_demo(redis_client)
    
    if mysql_connection:
        mysql_connection.close()
        print("✅ MySQL connection closed")

if __name__ == "__main__":
    main()
SCRIPT_EOF

# Make the script executable and change ownership
chmod +x /home/ec2-user/cache_demo.py
chown ec2-user:ec2-user /home/ec2-user/cache_demo.py

# Create a simple test script for Redis operations
cat > /home/ec2-user/test_cache.sh << 'TEST_EOF'
#!/bin/bash
# Simple Redis connectivity test script

echo "=== Redis Connectivity Test ==="
echo "Redis Endpoint: $REDIS_HOST"

# Test basic Redis commands
echo "Testing Redis PING..."
redis-cli -h $REDIS_HOST ping

echo "Setting test key..."
redis-cli -h $REDIS_HOST set "test:connection" "success" EX 60

echo "Getting test key..."
redis-cli -h $REDIS_HOST get "test:connection"

echo "Getting Redis info..."
redis-cli -h $REDIS_HOST info server | head -10

echo "✅ Redis test complete"
TEST_EOF

chmod +x /home/ec2-user/test_cache.sh
chown ec2-user:ec2-user /home/ec2-user/test_cache.sh

# Log completion
echo "✅ User data script completed successfully" >> /var/log/user-data.log
date >> /var/log/user-data.log
EOF
}

# EC2 Instance for testing cache integration
resource "aws_instance" "test" {
  count = var.create_ec2_instance ? 1 : 0

  ami                    = data.aws_ami.amazon_linux.id
  instance_type          = var.ec2_instance_type
  key_name              = var.ec2_key_pair_name
  vpc_security_group_ids = [aws_security_group.ec2[0].id]
  subnet_id             = data.aws_subnet.selected[0].id
  iam_instance_profile  = aws_iam_instance_profile.ec2[0].name

  user_data = local.user_data

  # Ensure dependencies are ready before launching
  depends_on = [
    aws_elasticache_replication_group.redis,
    aws_db_instance.mysql,
    local_file.user_data_template
  ]

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-test-instance"
    Type = "EC2 Test Instance"
  })

  lifecycle {
    create_before_destroy = true
  }
}

# CloudWatch Dashboard for monitoring cache performance
resource "aws_cloudwatch_dashboard" "cache_monitoring" {
  dashboard_name = "${local.name_prefix}-cache-monitoring"

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
            ["AWS/ElastiCache", "CacheHits", "CacheClusterId", aws_elasticache_replication_group.redis.replication_group_id],
            [".", "CacheMisses", ".", "."],
            [".", "CurrConnections", ".", "."],
          ]
          view    = "timeSeries"
          stacked = false
          region  = var.aws_region
          title   = "ElastiCache Performance Metrics"
          period  = 300
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
            ["AWS/ElastiCache", "BytesUsedForCache", "CacheClusterId", aws_elasticache_replication_group.redis.replication_group_id],
            [".", "DatabaseMemoryUsagePercentage", ".", "."],
          ]
          view    = "timeSeries"
          stacked = false
          region  = var.aws_region
          title   = "ElastiCache Memory Usage"
          period  = 300
        }
      }
    ]
  })

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-dashboard"
    Type = "CloudWatch Dashboard"
  })
}