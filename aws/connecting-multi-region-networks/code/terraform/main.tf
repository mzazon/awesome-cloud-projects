# Multi-Region VPC Connectivity with Transit Gateway
# This configuration creates a scalable hub-and-spoke network architecture
# across two AWS regions using Transit Gateway with cross-region peering

# Generate unique suffix for resource naming
resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
}

# Local values for resource naming and configuration
locals {
  name_prefix = "${var.project_name}-${random_string.suffix.result}"
  
  # Subnet CIDR calculations
  primary_subnet_a_cidr   = cidrsubnet(var.primary_vpc_a_cidr, 8, 1)
  primary_subnet_b_cidr   = cidrsubnet(var.primary_vpc_b_cidr, 8, 1)
  secondary_subnet_a_cidr = cidrsubnet(var.secondary_vpc_a_cidr, 8, 1)
  secondary_subnet_b_cidr = cidrsubnet(var.secondary_vpc_b_cidr, 8, 1)
  
  # Common tags
  common_tags = merge(var.common_tags, {
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "terraform"
    Recipe      = "multi-region-vpc-connectivity-transit-gateway"
  })
}

# Data source for AWS account ID
data "aws_caller_identity" "current" {}

# Data sources for availability zones
data "aws_availability_zones" "primary" {
  provider = aws.primary
  state    = "available"
}

data "aws_availability_zones" "secondary" {
  provider = aws.secondary
  state    = "available"
}

#===============================================================================
# PRIMARY REGION INFRASTRUCTURE
#===============================================================================

# Primary VPC A
resource "aws_vpc" "primary_vpc_a" {
  provider = aws.primary

  cidr_block           = var.primary_vpc_a_cidr
  enable_dns_support   = var.enable_dns_support
  enable_dns_hostnames = var.enable_dns_hostnames

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-primary-vpc-a"
    Type = "Primary"
    CIDR = var.primary_vpc_a_cidr
  })
}

# Primary VPC B
resource "aws_vpc" "primary_vpc_b" {
  provider = aws.primary

  cidr_block           = var.primary_vpc_b_cidr
  enable_dns_support   = var.enable_dns_support
  enable_dns_hostnames = var.enable_dns_hostnames

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-primary-vpc-b"
    Type = "Primary"
    CIDR = var.primary_vpc_b_cidr
  })
}

# Primary region subnets for Transit Gateway attachments
resource "aws_subnet" "primary_subnet_a" {
  provider = aws.primary

  vpc_id            = aws_vpc.primary_vpc_a.id
  cidr_block        = local.primary_subnet_a_cidr
  availability_zone = data.aws_availability_zones.primary.names[0]

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-primary-subnet-a"
    Type = "Transit Gateway Attachment"
  })
}

resource "aws_subnet" "primary_subnet_b" {
  provider = aws.primary

  vpc_id            = aws_vpc.primary_vpc_b.id
  cidr_block        = local.primary_subnet_b_cidr
  availability_zone = data.aws_availability_zones.primary.names[0]

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-primary-subnet-b"
    Type = "Transit Gateway Attachment"
  })
}

# Primary Transit Gateway
resource "aws_ec2_transit_gateway" "primary" {
  provider = aws.primary

  description                     = "Primary region Transit Gateway for ${var.project_name}"
  amazon_side_asn                 = var.primary_tgw_asn
  default_route_table_association = var.enable_default_route_table_association ? "enable" : "disable"
  default_route_table_propagation = var.enable_default_route_table_propagation ? "enable" : "disable"
  auto_accept_shared_attachments  = var.enable_auto_accept_shared_attachments
  multicast_support              = var.enable_multicast_support ? "enable" : "disable"

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-primary-tgw"
    Type = "Primary Transit Gateway"
    ASN  = tostring(var.primary_tgw_asn)
  })
}

# Primary VPC attachments to Transit Gateway
resource "aws_ec2_transit_gateway_vpc_attachment" "primary_attachment_a" {
  provider = aws.primary

  transit_gateway_id = aws_ec2_transit_gateway.primary.id
  vpc_id            = aws_vpc.primary_vpc_a.id
  subnet_ids        = [aws_subnet.primary_subnet_a.id]

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-primary-attachment-a"
    VPC  = aws_vpc.primary_vpc_a.id
  })
}

resource "aws_ec2_transit_gateway_vpc_attachment" "primary_attachment_b" {
  provider = aws.primary

  transit_gateway_id = aws_ec2_transit_gateway.primary.id
  vpc_id            = aws_vpc.primary_vpc_b.id
  subnet_ids        = [aws_subnet.primary_subnet_b.id]

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-primary-attachment-b"
    VPC  = aws_vpc.primary_vpc_b.id
  })
}

# Custom route table for primary Transit Gateway
resource "aws_ec2_transit_gateway_route_table" "primary" {
  provider = aws.primary

  transit_gateway_id = aws_ec2_transit_gateway.primary.id

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-primary-rt"
    Type = "Custom Route Table"
  })
}

#===============================================================================
# SECONDARY REGION INFRASTRUCTURE
#===============================================================================

# Secondary VPC A
resource "aws_vpc" "secondary_vpc_a" {
  provider = aws.secondary

  cidr_block           = var.secondary_vpc_a_cidr
  enable_dns_support   = var.enable_dns_support
  enable_dns_hostnames = var.enable_dns_hostnames

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-secondary-vpc-a"
    Type = "Secondary"
    CIDR = var.secondary_vpc_a_cidr
  })
}

# Secondary VPC B
resource "aws_vpc" "secondary_vpc_b" {
  provider = aws.secondary

  cidr_block           = var.secondary_vpc_b_cidr
  enable_dns_support   = var.enable_dns_support
  enable_dns_hostnames = var.enable_dns_hostnames

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-secondary-vpc-b"
    Type = "Secondary"
    CIDR = var.secondary_vpc_b_cidr
  })
}

# Secondary region subnets for Transit Gateway attachments
resource "aws_subnet" "secondary_subnet_a" {
  provider = aws.secondary

  vpc_id            = aws_vpc.secondary_vpc_a.id
  cidr_block        = local.secondary_subnet_a_cidr
  availability_zone = data.aws_availability_zones.secondary.names[0]

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-secondary-subnet-a"
    Type = "Transit Gateway Attachment"
  })
}

resource "aws_subnet" "secondary_subnet_b" {
  provider = aws.secondary

  vpc_id            = aws_vpc.secondary_vpc_b.id
  cidr_block        = local.secondary_subnet_b_cidr
  availability_zone = data.aws_availability_zones.secondary.names[0]

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-secondary-subnet-b"
    Type = "Transit Gateway Attachment"
  })
}

# Secondary Transit Gateway
resource "aws_ec2_transit_gateway" "secondary" {
  provider = aws.secondary

  description                     = "Secondary region Transit Gateway for ${var.project_name}"
  amazon_side_asn                 = var.secondary_tgw_asn
  default_route_table_association = var.enable_default_route_table_association ? "enable" : "disable"
  default_route_table_propagation = var.enable_default_route_table_propagation ? "enable" : "disable"
  auto_accept_shared_attachments  = var.enable_auto_accept_shared_attachments
  multicast_support              = var.enable_multicast_support ? "enable" : "disable"

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-secondary-tgw"
    Type = "Secondary Transit Gateway"
    ASN  = tostring(var.secondary_tgw_asn)
  })
}

# Secondary VPC attachments to Transit Gateway
resource "aws_ec2_transit_gateway_vpc_attachment" "secondary_attachment_a" {
  provider = aws.secondary

  transit_gateway_id = aws_ec2_transit_gateway.secondary.id
  vpc_id            = aws_vpc.secondary_vpc_a.id
  subnet_ids        = [aws_subnet.secondary_subnet_a.id]

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-secondary-attachment-a"
    VPC  = aws_vpc.secondary_vpc_a.id
  })
}

resource "aws_ec2_transit_gateway_vpc_attachment" "secondary_attachment_b" {
  provider = aws.secondary

  transit_gateway_id = aws_ec2_transit_gateway.secondary.id
  vpc_id            = aws_vpc.secondary_vpc_b.id
  subnet_ids        = [aws_subnet.secondary_subnet_b.id]

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-secondary-attachment-b"
    VPC  = aws_vpc.secondary_vpc_b.id
  })
}

# Custom route table for secondary Transit Gateway
resource "aws_ec2_transit_gateway_route_table" "secondary" {
  provider = aws.secondary

  transit_gateway_id = aws_ec2_transit_gateway.secondary.id

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-secondary-rt"
    Type = "Custom Route Table"
  })
}

#===============================================================================
# CROSS-REGION CONNECTIVITY
#===============================================================================

# Cross-region Transit Gateway peering attachment
resource "aws_ec2_transit_gateway_peering_attachment" "cross_region" {
  provider = aws.primary

  peer_account_id         = data.aws_caller_identity.current.account_id
  peer_region            = var.secondary_region
  peer_transit_gateway_id = aws_ec2_transit_gateway.secondary.id
  transit_gateway_id     = aws_ec2_transit_gateway.primary.id

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-cross-region-peering"
    Type = "Cross-Region Peering"
  })
}

# Accept the peering attachment in secondary region
resource "aws_ec2_transit_gateway_peering_attachment_accepter" "cross_region" {
  provider = aws.secondary

  transit_gateway_attachment_id = aws_ec2_transit_gateway_peering_attachment.cross_region.id

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-cross-region-peering-accepter"
    Type = "Peering Accepter"
  })
}

#===============================================================================
# ROUTE TABLE ASSOCIATIONS
#===============================================================================

# Associate primary VPC attachments with custom route table
resource "aws_ec2_transit_gateway_route_table_association" "primary_a" {
  provider = aws.primary

  transit_gateway_attachment_id  = aws_ec2_transit_gateway_vpc_attachment.primary_attachment_a.id
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.primary.id
}

resource "aws_ec2_transit_gateway_route_table_association" "primary_b" {
  provider = aws.primary

  transit_gateway_attachment_id  = aws_ec2_transit_gateway_vpc_attachment.primary_attachment_b.id
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.primary.id
}

# Associate peering attachment with primary route table
resource "aws_ec2_transit_gateway_route_table_association" "primary_peering" {
  provider = aws.primary

  transit_gateway_attachment_id  = aws_ec2_transit_gateway_peering_attachment.cross_region.id
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.primary.id
}

# Associate secondary VPC attachments with custom route table
resource "aws_ec2_transit_gateway_route_table_association" "secondary_a" {
  provider = aws.secondary

  transit_gateway_attachment_id  = aws_ec2_transit_gateway_vpc_attachment.secondary_attachment_a.id
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.secondary.id
}

resource "aws_ec2_transit_gateway_route_table_association" "secondary_b" {
  provider = aws.secondary

  transit_gateway_attachment_id  = aws_ec2_transit_gateway_vpc_attachment.secondary_attachment_b.id
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.secondary.id
}

# Associate peering attachment with secondary route table
resource "aws_ec2_transit_gateway_route_table_association" "secondary_peering" {
  provider = aws.secondary

  transit_gateway_attachment_id  = aws_ec2_transit_gateway_peering_attachment.cross_region.id
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.secondary.id
}

#===============================================================================
# CROSS-REGION ROUTES
#===============================================================================

# Routes from primary to secondary region
resource "aws_ec2_transit_gateway_route" "primary_to_secondary_a" {
  provider = aws.primary

  destination_cidr_block         = var.secondary_vpc_a_cidr
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_peering_attachment.cross_region.id
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.primary.id

  depends_on = [aws_ec2_transit_gateway_peering_attachment_accepter.cross_region]
}

resource "aws_ec2_transit_gateway_route" "primary_to_secondary_b" {
  provider = aws.primary

  destination_cidr_block         = var.secondary_vpc_b_cidr
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_peering_attachment.cross_region.id
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.primary.id

  depends_on = [aws_ec2_transit_gateway_peering_attachment_accepter.cross_region]
}

# Routes from secondary to primary region
resource "aws_ec2_transit_gateway_route" "secondary_to_primary_a" {
  provider = aws.secondary

  destination_cidr_block         = var.primary_vpc_a_cidr
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_peering_attachment.cross_region.id
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.secondary.id

  depends_on = [aws_ec2_transit_gateway_peering_attachment_accepter.cross_region]
}

resource "aws_ec2_transit_gateway_route" "secondary_to_primary_b" {
  provider = aws.secondary

  destination_cidr_block         = var.primary_vpc_b_cidr
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_peering_attachment.cross_region.id
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.secondary.id

  depends_on = [aws_ec2_transit_gateway_peering_attachment_accepter.cross_region]
}

#===============================================================================
# SECURITY GROUPS FOR TESTING
#===============================================================================

# Security group for primary VPC A to enable cross-region testing
resource "aws_security_group" "primary_cross_region" {
  count    = var.enable_cross_region_icmp ? 1 : 0
  provider = aws.primary

  name_prefix = "${local.name_prefix}-primary-cross-region-"
  description = "Security group for cross-region connectivity testing"
  vpc_id      = aws_vpc.primary_vpc_a.id

  # Allow ICMP from secondary region VPCs
  ingress {
    description = "ICMP from secondary region VPC A"
    from_port   = -1
    to_port     = -1
    protocol    = "icmp"
    cidr_blocks = [var.secondary_vpc_a_cidr]
  }

  ingress {
    description = "ICMP from secondary region VPC B"
    from_port   = -1
    to_port     = -1
    protocol    = "icmp"
    cidr_blocks = [var.secondary_vpc_b_cidr]
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
    Name = "${local.name_prefix}-primary-cross-region-sg"
    Type = "Cross-Region Security Group"
  })

  lifecycle {
    create_before_destroy = true
  }
}

# Security group for secondary VPC A to enable cross-region testing
resource "aws_security_group" "secondary_cross_region" {
  count    = var.enable_cross_region_icmp ? 1 : 0
  provider = aws.secondary

  name_prefix = "${local.name_prefix}-secondary-cross-region-"
  description = "Security group for cross-region connectivity testing"
  vpc_id      = aws_vpc.secondary_vpc_a.id

  # Allow ICMP from primary region VPCs
  ingress {
    description = "ICMP from primary region VPC A"
    from_port   = -1
    to_port     = -1
    protocol    = "icmp"
    cidr_blocks = [var.primary_vpc_a_cidr]
  }

  ingress {
    description = "ICMP from primary region VPC B"
    from_port   = -1
    to_port     = -1
    protocol    = "icmp"
    cidr_blocks = [var.primary_vpc_b_cidr]
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
    Name = "${local.name_prefix}-secondary-cross-region-sg"
    Type = "Cross-Region Security Group"
  })

  lifecycle {
    create_before_destroy = true
  }
}

#===============================================================================
# CLOUDWATCH MONITORING
#===============================================================================

# CloudWatch dashboard for Transit Gateway monitoring
resource "aws_cloudwatch_dashboard" "tgw_monitoring" {
  count          = var.create_cloudwatch_dashboard ? 1 : 0
  provider       = aws.primary
  dashboard_name = "${local.name_prefix}-tgw-dashboard"

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
            ["AWS/TransitGateway", "BytesIn", "TransitGateway", aws_ec2_transit_gateway.primary.id],
            [".", "BytesOut", ".", "."],
            [".", "PacketDropCount", ".", "."]
          ]
          period = 300
          stat   = "Sum"
          region = var.primary_region
          title  = "Primary Transit Gateway Metrics"
          yAxis = {
            left = {
              min = 0
            }
          }
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
            ["AWS/TransitGateway", "BytesIn", "TransitGateway", aws_ec2_transit_gateway.secondary.id],
            [".", "BytesOut", ".", "."],
            [".", "PacketDropCount", ".", "."]
          ]
          period = 300
          stat   = "Sum"
          region = var.secondary_region
          title  = "Secondary Transit Gateway Metrics"
          yAxis = {
            left = {
              min = 0
            }
          }
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 6
        width  = 24
        height = 6

        properties = {
          metrics = [
            ["AWS/TransitGateway", "PacketsReceived", "TransitGateway", aws_ec2_transit_gateway.primary.id],
            [".", "PacketsDropped", ".", "."],
            ["AWS/TransitGateway", "PacketsReceived", "TransitGateway", aws_ec2_transit_gateway.secondary.id],
            [".", "PacketsDropped", ".", "."]
          ]
          period = 300
          stat   = "Sum"
          region = var.primary_region
          title  = "Cross-Region Packet Flow"
          yAxis = {
            left = {
              min = 0
            }
          }
        }
      }
    ]
  })

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-tgw-dashboard"
    Type = "Monitoring Dashboard"
  })
}