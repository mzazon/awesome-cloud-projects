# Main Terraform configuration for gRPC microservices with VPC Lattice and CloudWatch

# Data sources for current AWS account and region
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# Generate random suffix for unique resource naming
resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
}

# Get the latest Amazon Linux 2 AMI
data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }

  filter {
    name   = "state"
    values = ["available"]
  }
}

# VPC for gRPC microservices
resource "aws_vpc" "grpc_vpc" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "grpc-vpc-${random_string.suffix.result}"
  }
}

# Internet Gateway for public subnet access
resource "aws_internet_gateway" "grpc_igw" {
  vpc_id = aws_vpc.grpc_vpc.id

  tags = {
    Name = "grpc-igw-${random_string.suffix.result}"
  }
}

# Public subnet for EC2 instances
resource "aws_subnet" "grpc_subnet" {
  vpc_id                  = aws_vpc.grpc_vpc.id
  cidr_block              = var.subnet_cidr
  availability_zone       = data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = true

  tags = {
    Name = "grpc-subnet-${random_string.suffix.result}"
  }
}

# Get available AZs
data "aws_availability_zones" "available" {
  state = "available"
}

# Route table for public subnet
resource "aws_route_table" "grpc_rt" {
  vpc_id = aws_vpc.grpc_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.grpc_igw.id
  }

  tags = {
    Name = "grpc-rt-${random_string.suffix.result}"
  }
}

# Associate route table with subnet
resource "aws_route_table_association" "grpc_rta" {
  subnet_id      = aws_subnet.grpc_subnet.id
  route_table_id = aws_route_table.grpc_rt.id
}

# Security group for gRPC microservices
resource "aws_security_group" "grpc_services_sg" {
  name_prefix = "grpc-services-${random_string.suffix.result}"
  description = "Security group for gRPC microservices"
  vpc_id      = aws_vpc.grpc_vpc.id

  # Allow gRPC traffic (ports 50051-50053)
  ingress {
    description = "gRPC service ports"
    from_port   = 50051
    to_port     = 50053
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  # Allow health check traffic (port 8080)
  ingress {
    description = "Health check port"
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  # Allow SSH access for debugging (optional)
  ingress {
    description = "SSH access"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]  # Restrict this in production
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
    Name = "grpc-services-sg-${random_string.suffix.result}"
  }
}

# User data script for EC2 instances with health check server
locals {
  user_data = base64encode(templatefile("${path.module}/user-data.sh", {
    region = data.aws_region.current.name
  }))
}

# Create user data script file
resource "local_file" "user_data_script" {
  content = <<-EOF
#!/bin/bash
yum update -y
yum install -y python3 python3-pip
pip3 install grpcio grpcio-tools flask

# Create a simple gRPC health server
cat > /home/ec2-user/health_server.py << 'PYEOF'
from flask import Flask, jsonify
import socket
import os

app = Flask(__name__)

@app.route('/health')
def health():
    hostname = socket.gethostname()
    instance_id = os.environ.get('EC2_INSTANCE_ID', 'unknown')
    return jsonify({
        'status': 'healthy',
        'service': 'grpc-service',
        'hostname': hostname,
        'instance_id': instance_id,
        'timestamp': '$(date -u +%Y-%m-%dT%H:%M:%SZ)'
    }), 200

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=8080)
PYEOF

# Get instance metadata
export EC2_INSTANCE_ID=$(curl -s http://169.254.169.254/latest/meta-data/instance-id)

# Start health check server
nohup python3 /home/ec2-user/health_server.py > /var/log/health-server.log 2>&1 &

# Create systemd service for health server
cat > /etc/systemd/system/grpc-health.service << 'EOF'
[Unit]
Description=gRPC Health Check Server
After=network.target

[Service]
Type=simple
User=ec2-user
WorkingDirectory=/home/ec2-user
ExecStart=/usr/bin/python3 /home/ec2-user/health_server.py
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

# Enable and start the service
systemctl enable grpc-health.service
systemctl start grpc-health.service
EOF

  filename = "${path.module}/user-data.sh"
}

# IAM role for EC2 instances
resource "aws_iam_role" "grpc_instance_role" {
  name_prefix = "grpc-instance-role-${random_string.suffix.result}"

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
    Name = "grpc-instance-role-${random_string.suffix.result}"
  }
}

# IAM instance profile
resource "aws_iam_instance_profile" "grpc_instance_profile" {
  name_prefix = "grpc-instance-profile-${random_string.suffix.result}"
  role        = aws_iam_role.grpc_instance_role.name
}

# Attach CloudWatch agent policy to instance role
resource "aws_iam_role_policy_attachment" "cloudwatch_agent_policy" {
  role       = aws_iam_role.grpc_instance_role.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
}

# EC2 instances for each microservice
resource "aws_instance" "grpc_instances" {
  for_each = var.microservices

  ami                    = data.aws_ami.amazon_linux.id
  instance_type          = var.instance_type
  vpc_security_group_ids = [aws_security_group.grpc_services_sg.id]
  subnet_id              = aws_subnet.grpc_subnet.id
  iam_instance_profile   = aws_iam_instance_profile.grpc_instance_profile.name
  user_data              = local.user_data

  tags = {
    Name    = "${each.value.name}-${random_string.suffix.result}"
    Service = each.value.name
    Port    = each.value.port
  }

  lifecycle {
    create_before_destroy = true
  }
}

# VPC Lattice Service Network
resource "aws_vpclattice_service_network" "grpc_service_network" {
  name      = "grpc-microservices-${random_string.suffix.result}"
  auth_type = "AWS_IAM"

  tags = {
    Environment = var.environment
    Purpose     = "gRPC-Services"
  }
}

# Associate VPC with Service Network
resource "aws_vpclattice_service_network_vpc_association" "grpc_vpc_association" {
  vpc_identifier             = aws_vpc.grpc_vpc.id
  service_network_identifier = aws_vpclattice_service_network.grpc_service_network.id

  tags = {
    Service = "gRPC-Network"
  }
}

# Target Groups for each microservice
resource "aws_vpclattice_target_group" "grpc_target_groups" {
  for_each = var.microservices

  name = "${each.value.name}-${random_string.suffix.result}"
  type = "INSTANCE"

  config {
    port             = each.value.port
    protocol         = "HTTP"
    protocol_version = "HTTP2"
    vpc_identifier   = aws_vpc.grpc_vpc.id

    health_check {
      enabled                       = true
      protocol                      = "HTTP"
      protocol_version              = "HTTP1"
      port                          = each.value.health_port
      path                          = "/health"
      health_check_interval_seconds = 30
      health_check_timeout_seconds  = 5
      healthy_threshold_count       = 2
      unhealthy_threshold_count     = 3

      matcher {
        value = "200"
      }
    }
  }

  tags = {
    Service = each.value.name
  }

  depends_on = [aws_vpclattice_service_network.grpc_service_network]
}

# Register instances with target groups
resource "aws_vpclattice_target_group_attachment" "grpc_target_attachments" {
  for_each = var.microservices

  target_group_identifier = aws_vpclattice_target_group.grpc_target_groups[each.key].id

  target {
    id   = aws_instance.grpc_instances[each.key].id
    port = each.value.port
  }

  depends_on = [aws_instance.grpc_instances]
}

# VPC Lattice Services
resource "aws_vpclattice_service" "grpc_services" {
  for_each = var.microservices

  name      = "${each.value.name}-${random_string.suffix.result}"
  auth_type = "AWS_IAM"

  tags = {
    Service  = each.value.name
    Protocol = "gRPC"
  }
}

# Associate services with service network
resource "aws_vpclattice_service_network_service_association" "grpc_service_associations" {
  for_each = var.microservices

  service_network_identifier = aws_vpclattice_service_network.grpc_service_network.id
  service_identifier         = aws_vpclattice_service.grpc_services[each.key].id

  tags = {
    Service = each.value.name
  }
}

# Listeners for gRPC services
resource "aws_vpclattice_listener" "grpc_listeners" {
  for_each = var.microservices

  service_identifier = aws_vpclattice_service.grpc_services[each.key].id
  name               = "grpc-listener"
  protocol           = "HTTPS"
  port               = 443

  default_action {
    forward {
      target_groups {
        target_group_identifier = aws_vpclattice_target_group.grpc_target_groups[each.key].id
        weight                  = 100
      }
    }
  }

  tags = {
    Protocol = "gRPC"
  }

  depends_on = [aws_vpclattice_target_group.grpc_target_groups]
}

# CloudWatch Log Group for VPC Lattice access logs
resource "aws_cloudwatch_log_group" "vpc_lattice_logs" {
  count = var.enable_access_logs ? 1 : 0

  name              = "/aws/vpc-lattice/grpc-services-${random_string.suffix.result}"
  retention_in_days = var.cloudwatch_log_retention_days

  tags = {
    Service = "VPC-Lattice-Logs"
  }
}

# Enable access logging for service network
resource "aws_vpclattice_access_log_subscription" "grpc_access_logs" {
  count = var.enable_access_logs ? 1 : 0

  resource_identifier = aws_vpclattice_service_network.grpc_service_network.id
  destination_arn     = aws_cloudwatch_log_group.vpc_lattice_logs[0].arn

  depends_on = [aws_cloudwatch_log_group.vpc_lattice_logs]
}

# CloudWatch Alarms for monitoring (if enabled)
resource "aws_cloudwatch_metric_alarm" "high_error_rate" {
  for_each = var.enable_monitoring ? var.microservices : {}

  alarm_name          = "gRPC-${title(each.key)}Service-HighErrorRate-${random_string.suffix.result}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = var.alarm_evaluation_periods
  metric_name         = "HTTPCode_5XX_Count"
  namespace           = "AWS/VpcLattice"
  period              = 300
  statistic           = "Sum"
  threshold           = var.high_error_rate_threshold
  alarm_description   = "High error rate in ${each.value.name}"

  dimensions = {
    Service = "${each.value.name}-${random_string.suffix.result}"
  }

  tags = {
    Service = each.value.name
    Type    = "ErrorRate"
  }
}

resource "aws_cloudwatch_metric_alarm" "high_latency" {
  for_each = var.enable_monitoring ? var.microservices : {}

  alarm_name          = "gRPC-${title(each.key)}Service-HighLatency-${random_string.suffix.result}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = var.alarm_evaluation_periods
  metric_name         = "RequestTime"
  namespace           = "AWS/VpcLattice"
  period              = 300
  statistic           = "Average"
  threshold           = var.high_latency_threshold_ms
  alarm_description   = "High latency in ${each.value.name}"

  dimensions = {
    Service = "${each.value.name}-${random_string.suffix.result}"
  }

  tags = {
    Service = each.value.name
    Type    = "Latency"
  }
}

resource "aws_cloudwatch_metric_alarm" "connection_failures" {
  for_each = var.enable_monitoring ? var.microservices : {}

  alarm_name          = "gRPC-${title(each.key)}Service-ConnectionFailures-${random_string.suffix.result}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = var.alarm_evaluation_periods
  metric_name         = "ConnectionErrorCount"
  namespace           = "AWS/VpcLattice"
  period              = 300
  statistic           = "Sum"
  threshold           = var.connection_failure_threshold
  alarm_description   = "High connection failure rate for ${each.value.name}"

  dimensions = {
    TargetGroup = "${each.value.name}-${random_string.suffix.result}"
  }

  tags = {
    Service = each.value.name
    Type    = "ConnectionFailures"
  }
}

# CloudWatch Dashboard
resource "aws_cloudwatch_dashboard" "grpc_dashboard" {
  count = var.create_dashboard ? 1 : 0

  dashboard_name = "gRPC-Microservices-${random_string.suffix.result}"

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
            for service_key, service in var.microservices : [
              "AWS/VpcLattice",
              "TotalRequestCount",
              "Service",
              "${service.name}-${random_string.suffix.result}"
            ]
          ]
          period = 300
          stat   = "Sum"
          region = data.aws_region.current.name
          title  = "gRPC Request Count"
          view   = "timeSeries"
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 0
        width  = 12
        height = 6
        properties = {
          metrics = [
            for service_key, service in var.microservices : [
              "AWS/VpcLattice",
              "RequestTime",
              "Service",
              "${service.name}-${random_string.suffix.result}"
            ]
          ]
          period = 300
          stat   = "Average"
          region = data.aws_region.current.name
          title  = "gRPC Request Latency (ms)"
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
            for service_key, service in var.microservices : [
              "AWS/VpcLattice",
              "HTTPCode_2XX_Count",
              "Service",
              "${service.name}-${random_string.suffix.result}"
            ]
          ]
          period = 300
          stat   = "Sum"
          region = data.aws_region.current.name
          title  = "Successful Requests (2XX)"
          view   = "timeSeries"
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 6
        width  = 12
        height = 6
        properties = {
          metrics = [
            for service_key, service in var.microservices : [
              "AWS/VpcLattice",
              "HTTPCode_5XX_Count",
              "Service",
              "${service.name}-${random_string.suffix.result}"
            ]
          ]
          period = 300
          stat   = "Sum"
          region = data.aws_region.current.name
          title  = "Server Errors (5XX)"
          view   = "timeSeries"
        }
      }
    ]
  })
}