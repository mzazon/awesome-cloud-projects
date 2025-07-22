# Multi-VPC Transit Gateway Architecture with Route Table Management
# This file contains the main infrastructure resources for a scalable multi-VPC architecture

# Random suffix for resource uniqueness
resource "random_id" "suffix" {
  count       = var.enable_resource_suffix ? 1 : 0
  byte_length = 3
}

locals {
  # Generate resource suffix if enabled
  suffix = var.enable_resource_suffix ? "-${random_id.suffix[0].hex}" : ""
  
  # Resource naming
  name_prefix = var.resource_prefix != "" ? "${var.resource_prefix}-" : ""
  
  # Common tags
  common_tags = merge(var.default_tags, {
    Project     = var.project_name
    Environment = var.environment
  })

  # Availability zones for primary region
  primary_azs = [for az in var.availability_zones : "${var.aws_region}${az}"]
  
  # Availability zones for DR region
  dr_azs = [for az in var.availability_zones : "${var.dr_region}${az}"]
}

# Data source for account ID
data "aws_caller_identity" "current" {}

# Data source for primary region availability zones
data "aws_availability_zones" "primary" {
  state = "available"
}

# Data source for DR region availability zones
data "aws_availability_zones" "dr" {
  provider = aws.dr
  state    = "available"
}

#==============================================================================
# VPC RESOURCES
#==============================================================================

# Production VPC
resource "aws_vpc" "production" {
  cidr_block           = var.vpc_cidrs.production
  enable_dns_hostnames = var.enable_dns_hostnames
  enable_dns_support   = var.enable_dns_resolution

  tags = merge(local.common_tags, {
    Name        = "${local.name_prefix}prod-vpc${local.suffix}"
    Environment = "production"
    Tier        = "production"
  })
}

# Development VPC
resource "aws_vpc" "development" {
  cidr_block           = var.vpc_cidrs.development
  enable_dns_hostnames = var.enable_dns_hostnames
  enable_dns_support   = var.enable_dns_resolution

  tags = merge(local.common_tags, {
    Name        = "${local.name_prefix}dev-vpc${local.suffix}"
    Environment = "development"
    Tier        = "non-production"
  })
}

# Test VPC
resource "aws_vpc" "test" {
  cidr_block           = var.vpc_cidrs.test
  enable_dns_hostnames = var.enable_dns_hostnames
  enable_dns_support   = var.enable_dns_resolution

  tags = merge(local.common_tags, {
    Name        = "${local.name_prefix}test-vpc${local.suffix}"
    Environment = "test"
    Tier        = "non-production"
  })
}

# Shared Services VPC
resource "aws_vpc" "shared" {
  cidr_block           = var.vpc_cidrs.shared
  enable_dns_hostnames = var.enable_dns_hostnames
  enable_dns_support   = var.enable_dns_resolution

  tags = merge(local.common_tags, {
    Name        = "${local.name_prefix}shared-vpc${local.suffix}"
    Environment = "shared"
    Tier        = "shared-services"
  })
}

# Disaster Recovery VPC (in DR region)
resource "aws_vpc" "dr" {
  provider = aws.dr
  
  cidr_block           = var.vpc_cidrs.dr
  enable_dns_hostnames = var.enable_dns_hostnames
  enable_dns_support   = var.enable_dns_resolution

  tags = merge(local.common_tags, {
    Name        = "${local.name_prefix}dr-vpc${local.suffix}"
    Environment = "disaster-recovery"
    Tier        = "production"
  })
}

#==============================================================================
# SUBNET RESOURCES
#==============================================================================

# Production VPC Subnets
resource "aws_subnet" "production_private_a" {
  vpc_id            = aws_vpc.production.id
  cidr_block        = var.subnet_cidrs.production.private_a
  availability_zone = local.primary_azs[0]

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}prod-subnet-a${local.suffix}"
    Type = "private"
  })
}

resource "aws_subnet" "production_private_b" {
  vpc_id            = aws_vpc.production.id
  cidr_block        = var.subnet_cidrs.production.private_b
  availability_zone = local.primary_azs[1]

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}prod-subnet-b${local.suffix}"
    Type = "private"
  })
}

# Development VPC Subnets
resource "aws_subnet" "development_private_a" {
  vpc_id            = aws_vpc.development.id
  cidr_block        = var.subnet_cidrs.development.private_a
  availability_zone = local.primary_azs[0]

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}dev-subnet-a${local.suffix}"
    Type = "private"
  })
}

resource "aws_subnet" "development_private_b" {
  vpc_id            = aws_vpc.development.id
  cidr_block        = var.subnet_cidrs.development.private_b
  availability_zone = local.primary_azs[1]

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}dev-subnet-b${local.suffix}"
    Type = "private"
  })
}

# Test VPC Subnets
resource "aws_subnet" "test_private_a" {
  vpc_id            = aws_vpc.test.id
  cidr_block        = var.subnet_cidrs.test.private_a
  availability_zone = local.primary_azs[0]

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}test-subnet-a${local.suffix}"
    Type = "private"
  })
}

resource "aws_subnet" "test_private_b" {
  vpc_id            = aws_vpc.test.id
  cidr_block        = var.subnet_cidrs.test.private_b
  availability_zone = local.primary_azs[1]

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}test-subnet-b${local.suffix}"
    Type = "private"
  })
}

# Shared Services VPC Subnets
resource "aws_subnet" "shared_private_a" {
  vpc_id            = aws_vpc.shared.id
  cidr_block        = var.subnet_cidrs.shared.private_a
  availability_zone = local.primary_azs[0]

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}shared-subnet-a${local.suffix}"
    Type = "private"
  })
}

resource "aws_subnet" "shared_private_b" {
  vpc_id            = aws_vpc.shared.id
  cidr_block        = var.subnet_cidrs.shared.private_b
  availability_zone = local.primary_azs[1]

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}shared-subnet-b${local.suffix}"
    Type = "private"
  })
}

# DR VPC Subnets
resource "aws_subnet" "dr_private_a" {
  provider = aws.dr
  
  vpc_id            = aws_vpc.dr.id
  cidr_block        = var.subnet_cidrs.dr.private_a
  availability_zone = local.dr_azs[0]

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}dr-subnet-a${local.suffix}"
    Type = "private"
  })
}

resource "aws_subnet" "dr_private_b" {
  provider = aws.dr
  
  vpc_id            = aws_vpc.dr.id
  cidr_block        = var.subnet_cidrs.dr.private_b
  availability_zone = local.dr_azs[1]

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}dr-subnet-b${local.suffix}"
    Type = "private"
  })
}

#==============================================================================
# TRANSIT GATEWAY RESOURCES
#==============================================================================

# Primary Transit Gateway
resource "aws_ec2_transit_gateway" "main" {
  description                     = "Enterprise Multi-VPC Transit Gateway"
  amazon_side_asn                = var.transit_gateway_asn
  auto_accept_shared_attachments = "disable"
  default_route_table_association = "disable"
  default_route_table_propagation = "disable"
  dns_support                    = "enable"
  vpn_ecmp_support              = "enable"

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}enterprise-tgw${local.suffix}"
  })
}

# DR Transit Gateway
resource "aws_ec2_transit_gateway" "dr" {
  provider = aws.dr
  
  description                     = "Disaster Recovery Transit Gateway"
  amazon_side_asn                = var.dr_transit_gateway_asn
  auto_accept_shared_attachments = "disable"
  default_route_table_association = "enable"
  default_route_table_propagation = "enable"
  dns_support                    = "enable"
  vpn_ecmp_support              = "enable"

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}dr-tgw${local.suffix}"
  })
}

#==============================================================================
# TRANSIT GATEWAY ROUTE TABLES
#==============================================================================

# Production Route Table
resource "aws_ec2_transit_gateway_route_table" "production" {
  transit_gateway_id = aws_ec2_transit_gateway.main.id

  tags = merge(local.common_tags, {
    Name        = "${local.name_prefix}prod-route-table${local.suffix}"
    Environment = "production"
  })
}

# Development Route Table (shared by dev and test)
resource "aws_ec2_transit_gateway_route_table" "development" {
  transit_gateway_id = aws_ec2_transit_gateway.main.id

  tags = merge(local.common_tags, {
    Name        = "${local.name_prefix}dev-route-table${local.suffix}"
    Environment = "development"
  })
}

# Shared Services Route Table
resource "aws_ec2_transit_gateway_route_table" "shared" {
  transit_gateway_id = aws_ec2_transit_gateway.main.id

  tags = merge(local.common_tags, {
    Name        = "${local.name_prefix}shared-route-table${local.suffix}"
    Environment = "shared"
  })
}

#==============================================================================
# TRANSIT GATEWAY VPC ATTACHMENTS
#==============================================================================

# Production VPC Attachment
resource "aws_ec2_transit_gateway_vpc_attachment" "production" {
  subnet_ids         = [aws_subnet.production_private_a.id]
  transit_gateway_id = aws_ec2_transit_gateway.main.id
  vpc_id             = aws_vpc.production.id
  
  # Disable default association and propagation for custom route management
  transit_gateway_default_route_table_association = false
  transit_gateway_default_route_table_propagation = false

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}prod-attachment${local.suffix}"
  })
}

# Development VPC Attachment
resource "aws_ec2_transit_gateway_vpc_attachment" "development" {
  subnet_ids         = [aws_subnet.development_private_a.id]
  transit_gateway_id = aws_ec2_transit_gateway.main.id
  vpc_id             = aws_vpc.development.id
  
  transit_gateway_default_route_table_association = false
  transit_gateway_default_route_table_propagation = false

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}dev-attachment${local.suffix}"
  })
}

# Test VPC Attachment
resource "aws_ec2_transit_gateway_vpc_attachment" "test" {
  subnet_ids         = [aws_subnet.test_private_a.id]
  transit_gateway_id = aws_ec2_transit_gateway.main.id
  vpc_id             = aws_vpc.test.id
  
  transit_gateway_default_route_table_association = false
  transit_gateway_default_route_table_propagation = false

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}test-attachment${local.suffix}"
  })
}

# Shared Services VPC Attachment
resource "aws_ec2_transit_gateway_vpc_attachment" "shared" {
  subnet_ids         = [aws_subnet.shared_private_a.id]
  transit_gateway_id = aws_ec2_transit_gateway.main.id
  vpc_id             = aws_vpc.shared.id
  
  transit_gateway_default_route_table_association = false
  transit_gateway_default_route_table_propagation = false

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}shared-attachment${local.suffix}"
  })
}

# DR VPC Attachment
resource "aws_ec2_transit_gateway_vpc_attachment" "dr" {
  provider = aws.dr
  
  subnet_ids         = [aws_subnet.dr_private_a.id]
  transit_gateway_id = aws_ec2_transit_gateway.dr.id
  vpc_id             = aws_vpc.dr.id

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}dr-attachment${local.suffix}"
  })
}

#==============================================================================
# ROUTE TABLE ASSOCIATIONS
#==============================================================================

# Associate Production VPC with Production Route Table
resource "aws_ec2_transit_gateway_route_table_association" "production" {
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_vpc_attachment.production.id
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.production.id
}

# Associate Development VPC with Development Route Table
resource "aws_ec2_transit_gateway_route_table_association" "development" {
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_vpc_attachment.development.id
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.development.id
}

# Associate Test VPC with Development Route Table (shared environment)
resource "aws_ec2_transit_gateway_route_table_association" "test" {
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_vpc_attachment.test.id
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.development.id
}

# Associate Shared Services VPC with Shared Route Table
resource "aws_ec2_transit_gateway_route_table_association" "shared" {
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_vpc_attachment.shared.id
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.shared.id
}

#==============================================================================
# ROUTE PROPAGATIONS
#==============================================================================

# Enable Production to access Shared Services
resource "aws_ec2_transit_gateway_route_table_propagation" "prod_to_shared" {
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_vpc_attachment.shared.id
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.production.id
}

# Enable Development/Test to access Shared Services
resource "aws_ec2_transit_gateway_route_table_propagation" "dev_to_shared" {
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_vpc_attachment.shared.id
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.development.id
}

# Enable Shared Services to access Production
resource "aws_ec2_transit_gateway_route_table_propagation" "shared_to_prod" {
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_vpc_attachment.production.id
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.shared.id
}

# Enable Shared Services to access Development
resource "aws_ec2_transit_gateway_route_table_propagation" "shared_to_dev" {
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_vpc_attachment.development.id
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.shared.id
}

# Enable Shared Services to access Test
resource "aws_ec2_transit_gateway_route_table_propagation" "shared_to_test" {
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_vpc_attachment.test.id
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.shared.id
}

#==============================================================================
# STATIC ROUTES FOR SECURITY POLICIES
#==============================================================================

# Blackhole route to block direct Dev-to-Prod communication
resource "aws_ec2_transit_gateway_route" "block_dev_to_prod" {
  destination_cidr_block         = var.vpc_cidrs.production
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.development.id
  blackhole                      = true
}

# Explicit route for shared services access from production
resource "aws_ec2_transit_gateway_route" "prod_to_shared_explicit" {
  destination_cidr_block         = var.vpc_cidrs.shared
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_vpc_attachment.shared.id
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.production.id
}

# Explicit route for shared services access from development
resource "aws_ec2_transit_gateway_route" "dev_to_shared_explicit" {
  destination_cidr_block         = var.vpc_cidrs.shared
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_vpc_attachment.shared.id
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.development.id
}

#==============================================================================
# CROSS-REGION PEERING (CONDITIONAL)
#==============================================================================

# Cross-region peering attachment
resource "aws_ec2_transit_gateway_peering_attachment" "cross_region" {
  count = var.enable_cross_region_peering ? 1 : 0
  
  peer_account_id         = data.aws_caller_identity.current.account_id
  peer_region             = var.dr_region
  peer_transit_gateway_id = aws_ec2_transit_gateway.dr.id
  transit_gateway_id      = aws_ec2_transit_gateway.main.id

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}cross-region-peering${local.suffix}"
  })
}

# Accept peering attachment in DR region
resource "aws_ec2_transit_gateway_peering_attachment_accepter" "cross_region" {
  count    = var.enable_cross_region_peering ? 1 : 0
  provider = aws.dr
  
  transit_gateway_attachment_id = aws_ec2_transit_gateway_peering_attachment.cross_region[0].id

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}cross-region-peering-accepter${local.suffix}"
  })
}

#==============================================================================
# VPC ROUTE TABLE UPDATES
#==============================================================================

# Update Production VPC route table
resource "aws_route" "prod_to_shared" {
  route_table_id         = aws_vpc.production.default_route_table_id
  destination_cidr_block = var.vpc_cidrs.shared
  transit_gateway_id     = aws_ec2_transit_gateway.main.id
  
  depends_on = [aws_ec2_transit_gateway_vpc_attachment.production]
}

# Update Development VPC route table
resource "aws_route" "dev_to_shared" {
  route_table_id         = aws_vpc.development.default_route_table_id
  destination_cidr_block = var.vpc_cidrs.shared
  transit_gateway_id     = aws_ec2_transit_gateway.main.id
  
  depends_on = [aws_ec2_transit_gateway_vpc_attachment.development]
}

# Update Test VPC route table
resource "aws_route" "test_to_shared" {
  route_table_id         = aws_vpc.test.default_route_table_id
  destination_cidr_block = var.vpc_cidrs.shared
  transit_gateway_id     = aws_ec2_transit_gateway.main.id
  
  depends_on = [aws_ec2_transit_gateway_vpc_attachment.test]
}

# Update Shared Services VPC route table (broader access)
resource "aws_route" "shared_to_all" {
  route_table_id         = aws_vpc.shared.default_route_table_id
  destination_cidr_block = "10.0.0.0/8"
  transit_gateway_id     = aws_ec2_transit_gateway.main.id
  
  depends_on = [aws_ec2_transit_gateway_vpc_attachment.shared]
}

#==============================================================================
# SECURITY GROUPS
#==============================================================================

# Production Security Group
resource "aws_security_group" "production_tgw" {
  name        = "${local.name_prefix}prod-tgw-sg${local.suffix}"
  description = "Security group for production Transit Gateway traffic"
  vpc_id      = aws_vpc.production.id

  # HTTPS within production environment
  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidrs.production]
    description = "HTTPS within production environment"
  }

  # DNS from shared services
  ingress {
    from_port   = 53
    to_port     = 53
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidrs.shared]
    description = "DNS TCP from shared services"
  }

  ingress {
    from_port   = 53
    to_port     = 53
    protocol    = "udp"
    cidr_blocks = [var.vpc_cidrs.shared]
    description = "DNS UDP from shared services"
  }

  # Outbound rules
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "All outbound traffic"
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}prod-tgw-sg${local.suffix}"
  })
}

# Development Security Group
resource "aws_security_group" "development_tgw" {
  name        = "${local.name_prefix}dev-tgw-sg${local.suffix}"
  description = "Security group for development Transit Gateway traffic"
  vpc_id      = aws_vpc.development.id

  # HTTP within development environment
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidrs.development]
    description = "HTTP within development environment"
  }

  # HTTPS within development environment
  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidrs.development]
    description = "HTTPS within development environment"
  }

  # SSH from test environment
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidrs.test]
    description = "SSH from test environment"
  }

  # DNS from shared services
  ingress {
    from_port   = 53
    to_port     = 53
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidrs.shared]
    description = "DNS TCP from shared services"
  }

  ingress {
    from_port   = 53
    to_port     = 53
    protocol    = "udp"
    cidr_blocks = [var.vpc_cidrs.shared]
    description = "DNS UDP from shared services"
  }

  # Outbound rules
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "All outbound traffic"
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}dev-tgw-sg${local.suffix}"
  })
}

# Shared Services Security Group
resource "aws_security_group" "shared_tgw" {
  name        = "${local.name_prefix}shared-tgw-sg${local.suffix}"
  description = "Security group for shared services Transit Gateway traffic"
  vpc_id      = aws_vpc.shared.id

  # DNS server access from all environments
  ingress {
    from_port   = 53
    to_port     = 53
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/8"]
    description = "DNS TCP from all environments"
  }

  ingress {
    from_port   = 53
    to_port     = 53
    protocol    = "udp"
    cidr_blocks = ["10.0.0.0/8"]
    description = "DNS UDP from all environments"
  }

  # HTTPS for management interfaces
  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/8"]
    description = "HTTPS for management interfaces"
  }

  # Monitoring and logging ports
  ingress {
    from_port   = 514
    to_port     = 514
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/8"]
    description = "Syslog TCP"
  }

  ingress {
    from_port   = 514
    to_port     = 514
    protocol    = "udp"
    cidr_blocks = ["10.0.0.0/8"]
    description = "Syslog UDP"
  }

  # Outbound rules
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "All outbound traffic"
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}shared-tgw-sg${local.suffix}"
  })
}