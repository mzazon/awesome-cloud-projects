# -----------------------------------------------------------------------------
# Data Sources
# -----------------------------------------------------------------------------

# Get current AWS account ID and region
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# Get availability zones for the region
data "aws_availability_zones" "available" {
  state = "available"
}

# Get default VPC if using existing VPC
data "aws_vpc" "default" {
  count   = var.use_default_vpc ? 1 : 0
  default = true
}

# Get default subnets if using existing VPC
data "aws_subnets" "default" {
  count = var.use_default_vpc ? 1 : 0

  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default[0].id]
  }

  filter {
    name   = "default-for-az"
    values = ["true"]
  }
}

# Get the latest Amazon Linux 2 AMI
data "aws_ami" "amazon_linux" {
  count       = var.create_ec2_client ? 1 : 0
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

# -----------------------------------------------------------------------------
# Local Values
# -----------------------------------------------------------------------------

locals {
  # Generate unique suffix for resource names
  random_suffix = random_string.suffix.result

  # Construct resource names
  network_name = "${var.network_name_prefix}-${local.random_suffix}"
  member_name  = "${var.member_name_prefix}-${local.random_suffix}"

  # VPC and subnet configuration
  vpc_id = var.use_default_vpc ? data.aws_vpc.default[0].id : aws_vpc.blockchain[0].id
  subnet_ids = var.use_default_vpc ? data.aws_subnets.default[0].ids : [
    aws_subnet.blockchain_private[0].id,
    aws_subnet.blockchain_public[0].id
  ]
  
  # Primary subnet for resources
  primary_subnet_id = var.use_default_vpc ? data.aws_subnets.default[0].ids[0] : aws_subnet.blockchain_public[0].id

  # Availability zone for peer node
  peer_az = var.peer_node_availability_zone != null ? var.peer_node_availability_zone : "${data.aws_region.current.name}a"

  # Common tags
  common_tags = merge(
    {
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "Terraform"
      Recipe      = "private-blockchain-networks-amazon-managed-blockchain"
    },
    var.additional_tags
  )
}

# -----------------------------------------------------------------------------
# Random String Generation
# -----------------------------------------------------------------------------

resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
}

# Generate a random password for admin if not provided
resource "random_password" "admin_password" {
  count   = var.admin_password == "TempPassword123!" ? 1 : 0
  length  = 16
  special = true
}

# -----------------------------------------------------------------------------
# VPC Resources (only if creating new VPC)
# -----------------------------------------------------------------------------

resource "aws_vpc" "blockchain" {
  count                = var.use_default_vpc ? 0 : 1
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = merge(local.common_tags, {
    Name = "blockchain-vpc-${local.random_suffix}"
  })
}

resource "aws_internet_gateway" "blockchain" {
  count  = var.use_default_vpc ? 0 : 1
  vpc_id = aws_vpc.blockchain[0].id

  tags = merge(local.common_tags, {
    Name = "blockchain-igw-${local.random_suffix}"
  })
}

resource "aws_subnet" "blockchain_public" {
  count                   = var.use_default_vpc ? 0 : 1
  vpc_id                  = aws_vpc.blockchain[0].id
  cidr_block              = var.subnet_cidrs[0]
  availability_zone       = data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = true

  tags = merge(local.common_tags, {
    Name = "blockchain-public-subnet-${local.random_suffix}"
    Type = "Public"
  })
}

resource "aws_subnet" "blockchain_private" {
  count             = var.use_default_vpc ? 0 : 1
  vpc_id            = aws_vpc.blockchain[0].id
  cidr_block        = var.subnet_cidrs[1]
  availability_zone = data.aws_availability_zones.available.names[1]

  tags = merge(local.common_tags, {
    Name = "blockchain-private-subnet-${local.random_suffix}"
    Type = "Private"
  })
}

resource "aws_route_table" "blockchain_public" {
  count  = var.use_default_vpc ? 0 : 1
  vpc_id = aws_vpc.blockchain[0].id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.blockchain[0].id
  }

  tags = merge(local.common_tags, {
    Name = "blockchain-public-rt-${local.random_suffix}"
  })
}

resource "aws_route_table_association" "blockchain_public" {
  count          = var.use_default_vpc ? 0 : 1
  subnet_id      = aws_subnet.blockchain_public[0].id
  route_table_id = aws_route_table.blockchain_public[0].id
}

# -----------------------------------------------------------------------------
# Security Groups
# -----------------------------------------------------------------------------

resource "aws_security_group" "blockchain_endpoint" {
  name_prefix = "blockchain-endpoint-"
  description = "Security group for Managed Blockchain VPC endpoint"
  vpc_id      = local.vpc_id

  # Inbound rules for Hyperledger Fabric communication
  dynamic "ingress" {
    for_each = var.blockchain_ports
    content {
      description = "Blockchain port ${ingress.value}"
      from_port   = ingress.value
      to_port     = ingress.value
      protocol    = "tcp"
      cidr_blocks = [var.use_default_vpc ? data.aws_vpc.default[0].cidr_block : var.vpc_cidr]
    }
  }

  # Allow peer-to-peer communication within security group
  ingress {
    description = "Peer-to-peer communication"
    from_port   = 7051
    to_port     = 7053
    protocol    = "tcp"
    self        = true
  }

  # Outbound rules
  egress {
    description = "All outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, {
    Name = "blockchain-endpoint-sg-${local.random_suffix}"
  })

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_security_group" "blockchain_client" {
  count       = var.create_ec2_client ? 1 : 0
  name_prefix = "blockchain-client-"
  description = "Security group for blockchain client EC2 instance"
  vpc_id      = local.vpc_id

  # SSH access
  ingress {
    description = "SSH access"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = var.allowed_ssh_cidrs
  }

  # Allow access to blockchain ports
  dynamic "egress" {
    for_each = var.blockchain_ports
    content {
      description = "Blockchain port ${egress.value}"
      from_port   = egress.value
      to_port     = egress.value
      protocol    = "tcp"
      cidr_blocks = ["0.0.0.0/0"]
    }
  }

  # General outbound access for software installation
  egress {
    description = "All outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, {
    Name = "blockchain-client-sg-${local.random_suffix}"
  })

  lifecycle {
    create_before_destroy = true
  }
}

# -----------------------------------------------------------------------------
# IAM Roles and Policies
# -----------------------------------------------------------------------------

# IAM role for Managed Blockchain
resource "aws_iam_role" "managed_blockchain" {
  count = var.create_iam_roles ? 1 : 0
  name  = "ManagedBlockchainRole-${local.random_suffix}"

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
    Name = "managed-blockchain-role"
  })
}

resource "aws_iam_role_policy_attachment" "managed_blockchain" {
  count      = var.create_iam_roles ? 1 : 0
  role       = aws_iam_role.managed_blockchain[0].name
  policy_arn = "arn:aws:iam::aws:policy/AmazonManagedBlockchainFullAccess"
}

# IAM role for chaincode execution
resource "aws_iam_role" "chaincode_execution" {
  count = var.create_iam_roles ? 1 : 0
  name  = "BlockchainChaincodeRole-${local.random_suffix}"

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
    Name = "chaincode-execution-role"
  })
}

resource "aws_iam_policy" "chaincode_execution" {
  count       = var.create_iam_roles ? 1 : 0
  name        = "BlockchainChaincodePolicy-${local.random_suffix}"
  description = "Policy for blockchain chaincode execution"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "managedblockchain:*",
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "logs:DescribeLogGroups",
          "logs:DescribeLogStreams"
        ]
        Resource = "*"
      }
    ]
  })

  tags = local.common_tags
}

resource "aws_iam_role_policy_attachment" "chaincode_execution" {
  count      = var.create_iam_roles ? 1 : 0
  role       = aws_iam_role.chaincode_execution[0].name
  policy_arn = aws_iam_policy.chaincode_execution[0].arn
}

resource "aws_iam_instance_profile" "chaincode_execution" {
  count = var.create_iam_roles ? 1 : 0
  name  = "blockchain-chaincode-profile-${local.random_suffix}"
  role  = aws_iam_role.chaincode_execution[0].name

  tags = local.common_tags
}

# -----------------------------------------------------------------------------
# VPC Endpoint for Managed Blockchain
# -----------------------------------------------------------------------------

resource "aws_vpc_endpoint" "managedblockchain" {
  count               = var.create_vpc_endpoint ? 1 : 0
  vpc_id              = local.vpc_id
  service_name        = "com.amazonaws.${data.aws_region.current.name}.managedblockchain"
  subnet_ids          = [local.primary_subnet_id]
  security_group_ids  = [aws_security_group.blockchain_endpoint.id]
  vpc_endpoint_type   = "Interface"
  private_dns_enabled = true

  tags = merge(local.common_tags, {
    Name = "managedblockchain-endpoint-${local.random_suffix}"
  })
}

# -----------------------------------------------------------------------------
# Managed Blockchain Network
# -----------------------------------------------------------------------------

resource "aws_managedblockchain_network" "blockchain_network" {
  name        = local.network_name
  description = var.network_description
  framework   = "HYPERLEDGER_FABRIC"

  framework_configuration {
    hyperledger_fabric_configuration {
      edition = var.fabric_edition
    }
  }

  voting_policy {
    approval_threshold_policy {
      threshold_percentage    = var.voting_threshold_percentage
      proposal_duration_hours = var.proposal_duration_hours
      threshold_comparator    = var.threshold_comparator
    }
  }

  member_configuration {
    name        = local.member_name
    description = var.member_description

    member_framework_configuration {
      hyperledger_fabric_configuration {
        admin_username = var.admin_username
        admin_password = var.admin_password != "TempPassword123!" ? var.admin_password : random_password.admin_password[0].result
      }
    }
  }

  tags = merge(local.common_tags, {
    Name = local.network_name
  })

  # Prevent accidental deletion in production
  lifecycle {
    prevent_destroy = false  # Set to true for production environments
  }
}

# -----------------------------------------------------------------------------
# Blockchain Member (retrieved from network creation)
# -----------------------------------------------------------------------------

data "aws_managedblockchain_member" "founding_member" {
  network_id = aws_managedblockchain_network.blockchain_network.id
  name       = local.member_name

  depends_on = [aws_managedblockchain_network.blockchain_network]
}

# -----------------------------------------------------------------------------
# Peer Node
# -----------------------------------------------------------------------------

resource "aws_managedblockchain_node" "peer_node" {
  network_id    = aws_managedblockchain_network.blockchain_network.id
  member_id     = data.aws_managedblockchain_member.founding_member.id
  instance_type = var.peer_node_instance_type

  node_configuration {
    availability_zone = local.peer_az
  }

  tags = merge(local.common_tags, {
    Name     = "peer-node-${local.random_suffix}"
    NodeType = "Peer"
  })

  # Ensure network is fully created before creating nodes
  depends_on = [
    aws_managedblockchain_network.blockchain_network,
    data.aws_managedblockchain_member.founding_member
  ]
}

# -----------------------------------------------------------------------------
# EC2 Key Pair
# -----------------------------------------------------------------------------

resource "aws_key_pair" "blockchain_client" {
  count      = var.create_ec2_client ? 1 : 0
  key_name   = "${var.ec2_key_pair_name}-${local.random_suffix}"
  public_key = tls_private_key.blockchain_client[0].public_key_openssh

  tags = merge(local.common_tags, {
    Name = "${var.ec2_key_pair_name}-${local.random_suffix}"
  })
}

resource "tls_private_key" "blockchain_client" {
  count     = var.create_ec2_client ? 1 : 0
  algorithm = "RSA"
  rsa_bits  = 4096
}

# Store private key in local file
resource "local_file" "private_key" {
  count           = var.create_ec2_client ? 1 : 0
  filename        = "${path.module}/${var.ec2_key_pair_name}-${local.random_suffix}.pem"
  content         = tls_private_key.blockchain_client[0].private_key_pem
  file_permission = "0400"
}

# -----------------------------------------------------------------------------
# EC2 Instance for Blockchain Client
# -----------------------------------------------------------------------------

resource "aws_instance" "blockchain_client" {
  count                       = var.create_ec2_client ? 1 : 0
  ami                         = data.aws_ami.amazon_linux[0].id
  instance_type               = var.ec2_instance_type
  key_name                    = aws_key_pair.blockchain_client[0].key_name
  subnet_id                   = local.primary_subnet_id
  vpc_security_group_ids      = [aws_security_group.blockchain_client[0].id]
  iam_instance_profile        = var.create_iam_roles ? aws_iam_instance_profile.chaincode_execution[0].name : null
  associate_public_ip_address = true

  user_data = base64encode(templatefile("${path.module}/user_data.sh", {
    region              = data.aws_region.current.name
    network_id          = aws_managedblockchain_network.blockchain_network.id
    member_id           = data.aws_managedblockchain_member.founding_member.id
    node_id             = aws_managedblockchain_node.peer_node.id
    hyperledger_version = var.hyperledger_fabric_version
  }))

  tags = merge(local.common_tags, {
    Name = "blockchain-client-${local.random_suffix}"
    Type = "BlockchainClient"
  })

  # Ensure blockchain resources are created first
  depends_on = [
    aws_managedblockchain_network.blockchain_network,
    aws_managedblockchain_node.peer_node
  ]
}

# -----------------------------------------------------------------------------
# CloudWatch Log Groups
# -----------------------------------------------------------------------------

resource "aws_cloudwatch_log_group" "blockchain_logs" {
  count             = var.enable_cloudwatch_logs ? 1 : 0
  name              = "/aws/managedblockchain/${local.network_name}"
  retention_in_days = var.log_retention_days

  tags = merge(local.common_tags, {
    Name = "blockchain-logs-${local.random_suffix}"
  })
}

resource "aws_cloudwatch_log_group" "vpc_flow_logs" {
  count             = var.enable_vpc_flow_logs ? 1 : 0
  name              = "/aws/vpc/flowlogs-${local.random_suffix}"
  retention_in_days = var.log_retention_days

  tags = merge(local.common_tags, {
    Name = "vpc-flow-logs-${local.random_suffix}"
  })
}

# -----------------------------------------------------------------------------
# VPC Flow Logs
# -----------------------------------------------------------------------------

resource "aws_iam_role" "flow_logs" {
  count = var.enable_vpc_flow_logs ? 1 : 0
  name  = "VPCFlowLogsRole-${local.random_suffix}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "vpc-flow-logs.amazonaws.com"
        }
      }
    ]
  })

  tags = merge(local.common_tags, {
    Name = "vpc-flow-logs-role"
  })
}

resource "aws_iam_role_policy" "flow_logs" {
  count = var.enable_vpc_flow_logs ? 1 : 0
  name  = "VPCFlowLogsPolicy-${local.random_suffix}"
  role  = aws_iam_role.flow_logs[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "logs:DescribeLogGroups",
          "logs:DescribeLogStreams"
        ]
        Effect   = "Allow"
        Resource = "*"
      }
    ]
  })
}

resource "aws_flow_log" "vpc_flow_logs" {
  count                = var.enable_vpc_flow_logs ? 1 : 0
  iam_role_arn         = aws_iam_role.flow_logs[0].arn
  log_destination      = aws_cloudwatch_log_group.vpc_flow_logs[0].arn
  log_destination_type = "cloud-watch-logs"
  traffic_type         = "ALL"
  vpc_id               = local.vpc_id

  tags = merge(local.common_tags, {
    Name = "vpc-flow-logs-${local.random_suffix}"
  })

  depends_on = [aws_iam_role_policy.flow_logs]
}