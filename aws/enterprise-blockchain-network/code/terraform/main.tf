# Main Terraform configuration for Hyperledger Fabric on Amazon Managed Blockchain
# This configuration creates a complete blockchain network with supporting infrastructure

# Generate random suffix for unique resource naming
resource "random_id" "suffix" {
  byte_length = 3
}

# Data source to get current AWS region
data "aws_region" "current" {}

# Data source to get AWS account ID
data "aws_caller_identity" "current" {}

# Data source to get availability zones
data "aws_availability_zones" "available" {
  state = "available"
}

# Data source for latest Amazon Linux 2 AMI
data "aws_ami" "amazon_linux" {
  count       = var.create_client_instance ? 1 : 0
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

# Local values for consistent naming and configuration
locals {
  name_prefix = "${var.network_name}-${random_id.suffix.hex}"
  member_name = "${var.member_name}-${random_id.suffix.hex}"
  
  # Determine availability zone for peer nodes
  peer_az = var.peer_node_availability_zone != "" ? var.peer_node_availability_zone : data.aws_availability_zones.available.names[0]
  
  # Common tags
  common_tags = merge(
    {
      Project     = "hyperledger-fabric-managed-blockchain"
      Environment = var.environment
      ManagedBy   = "terraform"
    },
    var.tags
  )
}

# CloudWatch Log Group for blockchain network logging
resource "aws_cloudwatch_log_group" "blockchain_logs" {
  count             = var.enable_logging ? 1 : 0
  name              = "/aws/managedblockchain/${local.name_prefix}"
  retention_in_days = var.log_retention_days

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-logs"
  })
}

# VPC for blockchain client access
resource "aws_vpc" "blockchain_vpc" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-vpc"
  })
}

# Internet Gateway for VPC
resource "aws_internet_gateway" "blockchain_igw" {
  vpc_id = aws_vpc.blockchain_vpc.id

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-igw"
  })
}

# Public subnet for client instances
resource "aws_subnet" "blockchain_subnet" {
  vpc_id                  = aws_vpc.blockchain_vpc.id
  cidr_block              = var.subnet_cidr
  availability_zone       = local.peer_az
  map_public_ip_on_launch = true

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-subnet"
    Type = "Public"
  })
}

# Route table for public subnet
resource "aws_route_table" "blockchain_rt" {
  vpc_id = aws_vpc.blockchain_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.blockchain_igw.id
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-rt"
  })
}

# Associate route table with subnet
resource "aws_route_table_association" "blockchain_rta" {
  subnet_id      = aws_subnet.blockchain_subnet.id
  route_table_id = aws_route_table.blockchain_rt.id
}

# Security group for blockchain client instances
resource "aws_security_group" "blockchain_client_sg" {
  count       = var.create_client_instance ? 1 : 0
  name        = "${local.name_prefix}-client-sg"
  description = "Security group for blockchain client instances"
  vpc_id      = aws_vpc.blockchain_vpc.id

  # SSH access
  ingress {
    description = "SSH access"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.allowed_ssh_cidr]
  }

  # HTTPS outbound for blockchain API calls
  egress {
    description = "HTTPS outbound"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # HTTP outbound for package downloads
  egress {
    description = "HTTP outbound"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-client-sg"
  })
}

# IAM role for Managed Blockchain network
resource "aws_iam_role" "blockchain_network_role" {
  name = "${local.name_prefix}-network-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "managedblockchain.amazonaws.com"
        }
      }
    ]
  })

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-network-role"
  })
}

# IAM policy for blockchain network logging
resource "aws_iam_role_policy" "blockchain_logging_policy" {
  count = var.enable_logging ? 1 : 0
  name  = "${local.name_prefix}-logging-policy"
  role  = aws_iam_role.blockchain_network_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "logs:DescribeLogGroups",
          "logs:DescribeLogStreams"
        ]
        Resource = var.enable_logging ? aws_cloudwatch_log_group.blockchain_logs[0].arn : null
      }
    ]
  })
}

# Amazon Managed Blockchain Network
resource "aws_managedblockchain_network" "fabric_network" {
  name        = local.name_prefix
  description = "Enterprise blockchain network for secure transactions"
  framework   = "HYPERLEDGER_FABRIC"

  framework_configuration {
    hyperledger_fabric_configuration {
      edition = var.network_edition
    }
  }

  voting_policy {
    approval_threshold_policy {
      threshold_percentage   = var.voting_threshold_percentage
      proposal_duration_in_hours = var.proposal_duration_hours
      threshold_comparator   = "GREATER_THAN"
    }
  }

  member_configuration {
    name        = local.member_name
    description = "Founding member organization"

    member_framework_configuration {
      member_fabric_configuration {
        admin_username = var.admin_username
        admin_password = var.admin_password
      }
    }

    dynamic "member_log_publishing_configuration" {
      for_each = var.enable_logging ? [1] : []
      content {
        fabric {
          ca_logs {
            cloudwatch {
              enabled = true
            }
          }
        }
      }
    }
  }

  tags = merge(local.common_tags, {
    Name = local.name_prefix
  })

  depends_on = [
    aws_iam_role_policy.blockchain_logging_policy
  ]
}

# Get the member ID from the network
data "aws_managedblockchain_member" "fabric_member" {
  network_id = aws_managedblockchain_network.fabric_network.id
  name       = local.member_name

  depends_on = [aws_managedblockchain_network.fabric_network]
}

# Managed Blockchain Node (Peer)
resource "aws_managedblockchain_node" "fabric_peer" {
  network_id    = aws_managedblockchain_network.fabric_network.id
  member_id     = data.aws_managedblockchain_member.fabric_member.id
  availability_zone = local.peer_az
  instance_type = var.peer_node_instance_type

  dynamic "node_log_publishing_configuration" {
    for_each = var.enable_logging ? [1] : []
    content {
      fabric {
        chaincode_logs {
          cloudwatch {
            enabled = true
          }
        }
        peer_logs {
          cloudwatch {
            enabled = true
          }
        }
      }
    }
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-peer"
  })
}

# VPC Endpoint for Managed Blockchain (if needed for private access)
resource "aws_vpc_endpoint" "managedblockchain" {
  vpc_id              = aws_vpc.blockchain_vpc.id
  service_name        = "com.amazonaws.${data.aws_region.current.name}.managedblockchain.${aws_managedblockchain_network.fabric_network.id}"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = [aws_subnet.blockchain_subnet.id]
  private_dns_enabled = true

  security_group_ids = var.create_client_instance ? [aws_security_group.blockchain_client_sg[0].id] : []

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-vpc-endpoint"
  })
}

# IAM role for EC2 client instance
resource "aws_iam_role" "client_instance_role" {
  count = var.create_client_instance ? 1 : 0
  name  = "${local.name_prefix}-client-role"

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
    Name = "${local.name_prefix}-client-role"
  })
}

# IAM policy for client instance blockchain access
resource "aws_iam_role_policy" "client_blockchain_policy" {
  count = var.create_client_instance ? 1 : 0
  name  = "${local.name_prefix}-client-policy"
  role  = aws_iam_role.client_instance_role[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "managedblockchain:GetNetwork",
          "managedblockchain:GetMember",
          "managedblockchain:GetNode",
          "managedblockchain:ListMembers",
          "managedblockchain:ListNodes",
          "managedblockchain:CreateAccessor",
          "managedblockchain:GetAccessor",
          "managedblockchain:ListAccessors"
        ]
        Resource = "*"
      }
    ]
  })
}

# Instance profile for EC2 client
resource "aws_iam_instance_profile" "client_instance_profile" {
  count = var.create_client_instance ? 1 : 0
  name  = "${local.name_prefix}-client-profile"
  role  = aws_iam_role.client_instance_role[0].name

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-client-profile"
  })
}

# User data script for client instance setup
locals {
  user_data = var.create_client_instance ? base64encode(templatefile("${path.module}/user_data.sh", {
    network_id = aws_managedblockchain_network.fabric_network.id
    member_id  = data.aws_managedblockchain_member.fabric_member.id
    region     = data.aws_region.current.name
  })) : ""
}

# Client EC2 instance for blockchain interaction
resource "aws_instance" "blockchain_client" {
  count                  = var.create_client_instance ? 1 : 0
  ami                    = data.aws_ami.amazon_linux[0].id
  instance_type          = var.client_instance_type
  key_name              = var.key_pair_name != "" ? var.key_pair_name : null
  vpc_security_group_ids = [aws_security_group.blockchain_client_sg[0].id]
  subnet_id             = aws_subnet.blockchain_subnet.id
  iam_instance_profile  = aws_iam_instance_profile.client_instance_profile[0].name

  user_data = local.user_data

  root_block_device {
    volume_type = "gp3"
    volume_size = 20
    encrypted   = true
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-client"
  })

  depends_on = [
    aws_managedblockchain_node.fabric_peer
  ]
}

# Create user data script file
resource "local_file" "user_data_script" {
  count = var.create_client_instance ? 1 : 0
  
  filename = "${path.module}/user_data.sh"
  content = templatefile("${path.module}/user_data.tpl", {
    network_id = aws_managedblockchain_network.fabric_network.id
    member_id  = data.aws_managedblockchain_member.fabric_member.id
    region     = data.aws_region.current.name
  })

  file_permission = "0755"
}

# Template file for user data script
resource "local_file" "user_data_template" {
  filename = "${path.module}/user_data.tpl"
  content = <<-EOF
#!/bin/bash
# User data script for blockchain client instance setup

# Update system packages
yum update -y

# Install required packages
yum install -y git curl wget unzip

# Install Node.js via NodeSource repository
curl -fsSL https://rpm.nodesource.com/setup_18.x | bash -
yum install -y nodejs

# Verify Node.js installation
node --version
npm --version

# Install yarn globally
npm install -g yarn

# Create application directory
mkdir -p /home/ec2-user/fabric-client-app
chown ec2-user:ec2-user /home/ec2-user/fabric-client-app

# Create package.json for Fabric SDK
cat > /home/ec2-user/fabric-client-app/package.json << 'PACKAGE_EOF'
{
  "name": "fabric-blockchain-client",
  "version": "1.0.0",
  "description": "Sample Hyperledger Fabric client for Amazon Managed Blockchain",
  "main": "app.js",
  "dependencies": {
    "fabric-network": "^2.2.20",
    "fabric-client": "^1.4.22",
    "fabric-ca-client": "^2.2.20"
  }
}
PACKAGE_EOF

# Set ownership
chown ec2-user:ec2-user /home/ec2-user/fabric-client-app/package.json

# Create environment configuration
cat > /home/ec2-user/fabric-client-app/.env << 'ENV_EOF'
NETWORK_ID=${network_id}
MEMBER_ID=${member_id}
AWS_REGION=${region}
ENV_EOF

chown ec2-user:ec2-user /home/ec2-user/fabric-client-app/.env

# Create sample chaincode
mkdir -p /home/ec2-user/fabric-client-app/chaincode
cat > /home/ec2-user/fabric-client-app/chaincode/asset-contract.js << 'CHAINCODE_EOF'
'use strict';

const { Contract } = require('fabric-contract-api');

class AssetContract extends Contract {

    async initLedger(ctx) {
        const assets = [
            {
                ID: 'asset1',
                Owner: 'Alice',
                Value: 100,
                Timestamp: new Date().toISOString()
            }
        ];

        for (const asset of assets) {
            await ctx.stub.putState(asset.ID, Buffer.from(JSON.stringify(asset)));
        }
    }

    async createAsset(ctx, id, owner, value) {
        const asset = {
            ID: id,
            Owner: owner,
            Value: parseInt(value),
            Timestamp: new Date().toISOString()
        };
        
        await ctx.stub.putState(id, Buffer.from(JSON.stringify(asset)));
        return JSON.stringify(asset);
    }

    async readAsset(ctx, id) {
        const assetJSON = await ctx.stub.getState(id);
        if (!assetJSON || assetJSON.length === 0) {
            throw new Error(`Asset $${id} does not exist`);
        }
        return assetJSON.toString();
    }

    async getAllAssets(ctx) {
        const allResults = [];
        const iterator = await ctx.stub.getStateByRange('', '');
        let result = await iterator.next();
        
        while (!result.done) {
            const strValue = Buffer.from(result.value.value).toString('utf8');
            let record;
            try {
                record = JSON.parse(strValue);
            } catch (err) {
                record = strValue;
            }
            allResults.push({ Key: result.value.key, Record: record });
            result = await iterator.next();
        }
        
        return JSON.stringify(allResults);
    }
}

module.exports = AssetContract;
CHAINCODE_EOF

chown -R ec2-user:ec2-user /home/ec2-user/fabric-client-app/chaincode

# Install npm dependencies as ec2-user
sudo -u ec2-user bash -c 'cd /home/ec2-user/fabric-client-app && npm install'

# Create setup completion marker
touch /home/ec2-user/setup-complete
chown ec2-user:ec2-user /home/ec2-user/setup-complete

# Log completion
echo "Blockchain client setup completed at $(date)" >> /var/log/user-data.log
EOF

  file_permission = "0644"
}