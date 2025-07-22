# Multi-Region VPC Peering with Complex Routing Scenarios
# This Terraform configuration creates a sophisticated global network architecture
# with hub-and-spoke topology across multiple AWS regions

# Generate random suffix for unique resource naming
resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
}

locals {
  # Common naming convention
  name_prefix = "${var.project_name}-${random_string.suffix.result}"
  
  # Common tags for all resources
  common_tags = merge(
    {
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "terraform"
      Recipe      = "multi-region-vpc-peering-complex-routing"
    },
    var.additional_tags,
    var.enable_cost_optimization_tags ? {
      CostCenter    = "networking"
      BusinessUnit  = "infrastructure"
      Application   = "global-connectivity"
    } : {}
  )
}

#===============================================================================
# PRIMARY REGION (US-East-1) INFRASTRUCTURE
#===============================================================================

# Hub VPC in Primary Region - Central connectivity point for US-East-1
resource "aws_vpc" "hub_vpc" {
  provider = aws.primary
  
  cidr_block           = var.vpc_cidrs.hub_vpc
  enable_dns_hostnames = var.enable_dns_hostnames
  enable_dns_support   = var.enable_dns_support
  
  tags = merge(local.common_tags, {
    Name   = "${local.name_prefix}-hub-vpc"
    Region = var.primary_region
    Role   = "hub"
    Tier   = "core"
  })
}

# Production VPC in Primary Region - Isolated production workloads
resource "aws_vpc" "prod_vpc" {
  provider = aws.primary
  
  cidr_block           = var.vpc_cidrs.prod_vpc
  enable_dns_hostnames = var.enable_dns_hostnames
  enable_dns_support   = var.enable_dns_support
  
  tags = merge(local.common_tags, {
    Name   = "${local.name_prefix}-prod-vpc"
    Region = var.primary_region
    Role   = "spoke"
    Tier   = "production"
  })
}

# Development VPC in Primary Region - Development and testing workloads
resource "aws_vpc" "dev_vpc" {
  provider = aws.primary
  
  cidr_block           = var.vpc_cidrs.dev_vpc
  enable_dns_hostnames = var.enable_dns_hostnames
  enable_dns_support   = var.enable_dns_support
  
  tags = merge(local.common_tags, {
    Name   = "${local.name_prefix}-dev-vpc"
    Region = var.primary_region
    Role   = "spoke"
    Tier   = "development"
  })
}

# Subnets in Primary Region
resource "aws_subnet" "hub_subnet" {
  provider = aws.primary
  
  vpc_id            = aws_vpc.hub_vpc.id
  cidr_block        = var.subnet_cidrs.hub_subnet
  availability_zone = "${var.primary_region}${var.availability_zones.primary}"
  
  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-hub-subnet-${var.availability_zones.primary}"
    Type = "hub"
  })
}

resource "aws_subnet" "prod_subnet" {
  provider = aws.primary
  
  vpc_id            = aws_vpc.prod_vpc.id
  cidr_block        = var.subnet_cidrs.prod_subnet
  availability_zone = "${var.primary_region}${var.availability_zones.primary}"
  
  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-prod-subnet-${var.availability_zones.primary}"
    Type = "production"
  })
}

resource "aws_subnet" "dev_subnet" {
  provider = aws.primary
  
  vpc_id            = aws_vpc.dev_vpc.id
  cidr_block        = var.subnet_cidrs.dev_subnet
  availability_zone = "${var.primary_region}${var.availability_zones.primary}"
  
  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-dev-subnet-${var.availability_zones.primary}"
    Type = "development"
  })
}

#===============================================================================
# SECONDARY REGION (US-West-2) INFRASTRUCTURE - DISASTER RECOVERY
#===============================================================================

# DR Hub VPC in Secondary Region - Disaster recovery hub
resource "aws_vpc" "dr_hub_vpc" {
  provider = aws.secondary
  
  cidr_block           = var.vpc_cidrs.dr_hub_vpc
  enable_dns_hostnames = var.enable_dns_hostnames
  enable_dns_support   = var.enable_dns_support
  
  tags = merge(local.common_tags, {
    Name   = "${local.name_prefix}-dr-hub-vpc"
    Region = var.secondary_region
    Role   = "hub"
    Tier   = "disaster-recovery"
  })
}

# DR Production VPC in Secondary Region
resource "aws_vpc" "dr_prod_vpc" {
  provider = aws.secondary
  
  cidr_block           = var.vpc_cidrs.dr_prod_vpc
  enable_dns_hostnames = var.enable_dns_hostnames
  enable_dns_support   = var.enable_dns_support
  
  tags = merge(local.common_tags, {
    Name   = "${local.name_prefix}-dr-prod-vpc"
    Region = var.secondary_region
    Role   = "spoke"
    Tier   = "disaster-recovery"
  })
}

# Subnets in Secondary Region
resource "aws_subnet" "dr_hub_subnet" {
  provider = aws.secondary
  
  vpc_id            = aws_vpc.dr_hub_vpc.id
  cidr_block        = var.subnet_cidrs.dr_hub_subnet
  availability_zone = "${var.secondary_region}${var.availability_zones.secondary}"
  
  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-dr-hub-subnet-${var.availability_zones.secondary}"
    Type = "disaster-recovery-hub"
  })
}

resource "aws_subnet" "dr_prod_subnet" {
  provider = aws.secondary
  
  vpc_id            = aws_vpc.dr_prod_vpc.id
  cidr_block        = var.subnet_cidrs.dr_prod_subnet
  availability_zone = "${var.secondary_region}${var.availability_zones.secondary}"
  
  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-dr-prod-subnet-${var.availability_zones.secondary}"
    Type = "disaster-recovery-production"
  })
}

#===============================================================================
# EU REGION (EU-West-1) INFRASTRUCTURE
#===============================================================================

# EU Hub VPC - Regional hub for European operations
resource "aws_vpc" "eu_hub_vpc" {
  provider = aws.eu
  
  cidr_block           = var.vpc_cidrs.eu_hub_vpc
  enable_dns_hostnames = var.enable_dns_hostnames
  enable_dns_support   = var.enable_dns_support
  
  tags = merge(local.common_tags, {
    Name   = "${local.name_prefix}-eu-hub-vpc"
    Region = var.eu_region
    Role   = "hub"
    Tier   = "regional"
  })
}

# EU Production VPC
resource "aws_vpc" "eu_prod_vpc" {
  provider = aws.eu
  
  cidr_block           = var.vpc_cidrs.eu_prod_vpc
  enable_dns_hostnames = var.enable_dns_hostnames
  enable_dns_support   = var.enable_dns_support
  
  tags = merge(local.common_tags, {
    Name   = "${local.name_prefix}-eu-prod-vpc"
    Region = var.eu_region
    Role   = "spoke"
    Tier   = "production"
  })
}

# Subnets in EU Region
resource "aws_subnet" "eu_hub_subnet" {
  provider = aws.eu
  
  vpc_id            = aws_vpc.eu_hub_vpc.id
  cidr_block        = var.subnet_cidrs.eu_hub_subnet
  availability_zone = "${var.eu_region}${var.availability_zones.eu}"
  
  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-eu-hub-subnet-${var.availability_zones.eu}"
    Type = "regional-hub"
  })
}

resource "aws_subnet" "eu_prod_subnet" {
  provider = aws.eu
  
  vpc_id            = aws_vpc.eu_prod_vpc.id
  cidr_block        = var.subnet_cidrs.eu_prod_subnet
  availability_zone = "${var.eu_region}${var.availability_zones.eu}"
  
  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-eu-prod-subnet-${var.availability_zones.eu}"
    Type = "european-production"
  })
}

#===============================================================================
# APAC REGION (AP-Southeast-1) INFRASTRUCTURE
#===============================================================================

# APAC VPC - Asia-Pacific spoke connected to EU Hub
resource "aws_vpc" "apac_vpc" {
  provider = aws.apac
  
  cidr_block           = var.vpc_cidrs.apac_vpc
  enable_dns_hostnames = var.enable_dns_hostnames
  enable_dns_support   = var.enable_dns_support
  
  tags = merge(local.common_tags, {
    Name   = "${local.name_prefix}-apac-vpc"
    Region = var.apac_region
    Role   = "spoke"
    Tier   = "regional"
  })
}

# Subnet in APAC Region
resource "aws_subnet" "apac_subnet" {
  provider = aws.apac
  
  vpc_id            = aws_vpc.apac_vpc.id
  cidr_block        = var.subnet_cidrs.apac_subnet
  availability_zone = "${var.apac_region}${var.availability_zones.apac}"
  
  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-apac-subnet-${var.availability_zones.apac}"
    Type = "asia-pacific"
  })
}

#===============================================================================
# VPC PEERING CONNECTIONS - INTER-REGION HUB-TO-HUB
#===============================================================================

# Primary Hub to DR Hub Peering (US-East-1 to US-West-2)
resource "aws_vpc_peering_connection" "hub_to_dr_hub" {
  provider = aws.primary
  
  vpc_id        = aws_vpc.hub_vpc.id
  peer_vpc_id   = aws_vpc.dr_hub_vpc.id
  peer_region   = var.secondary_region
  auto_accept   = false
  
  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-hub-to-dr-hub-peering"
    Type = "inter-region-hub"
  })
}

# Accept the peering connection in the secondary region
resource "aws_vpc_peering_connection_accepter" "hub_to_dr_hub_accepter" {
  provider = aws.secondary
  
  vpc_peering_connection_id = aws_vpc_peering_connection.hub_to_dr_hub.id
  auto_accept               = true
  
  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-hub-to-dr-hub-accepter"
  })
}

# Primary Hub to EU Hub Peering (US-East-1 to EU-West-1)
resource "aws_vpc_peering_connection" "hub_to_eu_hub" {
  provider = aws.primary
  
  vpc_id        = aws_vpc.hub_vpc.id
  peer_vpc_id   = aws_vpc.eu_hub_vpc.id
  peer_region   = var.eu_region
  auto_accept   = false
  
  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-hub-to-eu-hub-peering"
    Type = "inter-region-hub"
  })
}

# Accept the peering connection in the EU region
resource "aws_vpc_peering_connection_accepter" "hub_to_eu_hub_accepter" {
  provider = aws.eu
  
  vpc_peering_connection_id = aws_vpc_peering_connection.hub_to_eu_hub.id
  auto_accept               = true
  
  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-hub-to-eu-hub-accepter"
  })
}

# DR Hub to EU Hub Peering (US-West-2 to EU-West-1)
resource "aws_vpc_peering_connection" "dr_hub_to_eu_hub" {
  provider = aws.secondary
  
  vpc_id        = aws_vpc.dr_hub_vpc.id
  peer_vpc_id   = aws_vpc.eu_hub_vpc.id
  peer_region   = var.eu_region
  auto_accept   = false
  
  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-dr-hub-to-eu-hub-peering"
    Type = "inter-region-hub"
  })
}

# Accept the peering connection in the EU region
resource "aws_vpc_peering_connection_accepter" "dr_hub_to_eu_hub_accepter" {
  provider = aws.eu
  
  vpc_peering_connection_id = aws_vpc_peering_connection.dr_hub_to_eu_hub.id
  auto_accept               = true
  
  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-dr-hub-to-eu-hub-accepter"
  })
}

#===============================================================================
# VPC PEERING CONNECTIONS - INTRA-REGION HUB-TO-SPOKE
#===============================================================================

# Primary Hub to Production VPC Peering (US-East-1)
resource "aws_vpc_peering_connection" "hub_to_prod" {
  provider = aws.primary
  
  vpc_id      = aws_vpc.hub_vpc.id
  peer_vpc_id = aws_vpc.prod_vpc.id
  auto_accept = true
  
  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-hub-to-prod-peering"
    Type = "intra-region-hub-spoke"
  })
}

# Primary Hub to Development VPC Peering (US-East-1)
resource "aws_vpc_peering_connection" "hub_to_dev" {
  provider = aws.primary
  
  vpc_id      = aws_vpc.hub_vpc.id
  peer_vpc_id = aws_vpc.dev_vpc.id
  auto_accept = true
  
  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-hub-to-dev-peering"
    Type = "intra-region-hub-spoke"
  })
}

# DR Hub to DR Production VPC Peering (US-West-2)
resource "aws_vpc_peering_connection" "dr_hub_to_dr_prod" {
  provider = aws.secondary
  
  vpc_id      = aws_vpc.dr_hub_vpc.id
  peer_vpc_id = aws_vpc.dr_prod_vpc.id
  auto_accept = true
  
  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-dr-hub-to-dr-prod-peering"
    Type = "intra-region-hub-spoke"
  })
}

# EU Hub to EU Production VPC Peering (EU-West-1)
resource "aws_vpc_peering_connection" "eu_hub_to_eu_prod" {
  provider = aws.eu
  
  vpc_id      = aws_vpc.eu_hub_vpc.id
  peer_vpc_id = aws_vpc.eu_prod_vpc.id
  auto_accept = true
  
  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-eu-hub-to-eu-prod-peering"
    Type = "intra-region-hub-spoke"
  })
}

#===============================================================================
# VPC PEERING CONNECTIONS - CROSS-REGION SPOKE-TO-HUB
#===============================================================================

# APAC to EU Hub Peering (AP-Southeast-1 to EU-West-1)
resource "aws_vpc_peering_connection" "apac_to_eu_hub" {
  provider = aws.apac
  
  vpc_id        = aws_vpc.apac_vpc.id
  peer_vpc_id   = aws_vpc.eu_hub_vpc.id
  peer_region   = var.eu_region
  auto_accept   = false
  
  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-apac-to-eu-hub-peering"
    Type = "cross-region-spoke-hub"
  })
}

# Accept the APAC to EU Hub peering connection
resource "aws_vpc_peering_connection_accepter" "apac_to_eu_hub_accepter" {
  provider = aws.eu
  
  vpc_peering_connection_id = aws_vpc_peering_connection.apac_to_eu_hub.id
  auto_accept               = true
  
  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-apac-to-eu-hub-accepter"
  })
}

#===============================================================================
# ROUTE TABLES AND COMPLEX ROUTING CONFIGURATION
#===============================================================================

# Get default route tables for all VPCs
data "aws_route_table" "hub_vpc_main" {
  provider = aws.primary
  vpc_id   = aws_vpc.hub_vpc.id
  
  filter {
    name   = "association.main"
    values = ["true"]
  }
}

data "aws_route_table" "prod_vpc_main" {
  provider = aws.primary
  vpc_id   = aws_vpc.prod_vpc.id
  
  filter {
    name   = "association.main"
    values = ["true"]
  }
}

data "aws_route_table" "dev_vpc_main" {
  provider = aws.primary
  vpc_id   = aws_vpc.dev_vpc.id
  
  filter {
    name   = "association.main"
    values = ["true"]
  }
}

data "aws_route_table" "dr_hub_vpc_main" {
  provider = aws.secondary
  vpc_id   = aws_vpc.dr_hub_vpc.id
  
  filter {
    name   = "association.main"
    values = ["true"]
  }
}

data "aws_route_table" "dr_prod_vpc_main" {
  provider = aws.secondary
  vpc_id   = aws_vpc.dr_prod_vpc.id
  
  filter {
    name   = "association.main"
    values = ["true"]
  }
}

data "aws_route_table" "eu_hub_vpc_main" {
  provider = aws.eu
  vpc_id   = aws_vpc.eu_hub_vpc.id
  
  filter {
    name   = "association.main"
    values = ["true"]
  }
}

data "aws_route_table" "eu_prod_vpc_main" {
  provider = aws.eu
  vpc_id   = aws_vpc.eu_prod_vpc.id
  
  filter {
    name   = "association.main"
    values = ["true"]
  }
}

data "aws_route_table" "apac_vpc_main" {
  provider = aws.apac
  vpc_id   = aws_vpc.apac_vpc.id
  
  filter {
    name   = "association.main"
    values = ["true"]
  }
}

#===============================================================================
# HUB ROUTE TABLE CONFIGURATIONS - TRANSIT ROUTING
#===============================================================================

# Primary Hub (US-East-1) Routes - Central transit hub
resource "aws_route" "hub_to_dr_hub" {
  provider = aws.primary
  
  route_table_id            = data.aws_route_table.hub_vpc_main.id
  destination_cidr_block    = var.vpc_cidrs.dr_hub_vpc
  vpc_peering_connection_id = aws_vpc_peering_connection.hub_to_dr_hub.id
  
  depends_on = [aws_vpc_peering_connection_accepter.hub_to_dr_hub_accepter]
}

resource "aws_route" "hub_to_dr_prod_via_dr_hub" {
  provider = aws.primary
  
  route_table_id            = data.aws_route_table.hub_vpc_main.id
  destination_cidr_block    = var.vpc_cidrs.dr_prod_vpc
  vpc_peering_connection_id = aws_vpc_peering_connection.hub_to_dr_hub.id
  
  depends_on = [aws_vpc_peering_connection_accepter.hub_to_dr_hub_accepter]
}

resource "aws_route" "hub_to_eu_hub" {
  provider = aws.primary
  
  route_table_id            = data.aws_route_table.hub_vpc_main.id
  destination_cidr_block    = var.vpc_cidrs.eu_hub_vpc
  vpc_peering_connection_id = aws_vpc_peering_connection.hub_to_eu_hub.id
  
  depends_on = [aws_vpc_peering_connection_accepter.hub_to_eu_hub_accepter]
}

resource "aws_route" "hub_to_eu_prod_via_eu_hub" {
  provider = aws.primary
  
  route_table_id            = data.aws_route_table.hub_vpc_main.id
  destination_cidr_block    = var.vpc_cidrs.eu_prod_vpc
  vpc_peering_connection_id = aws_vpc_peering_connection.hub_to_eu_hub.id
  
  depends_on = [aws_vpc_peering_connection_accepter.hub_to_eu_hub_accepter]
}

resource "aws_route" "hub_to_apac_via_eu_hub" {
  provider = aws.primary
  
  route_table_id            = data.aws_route_table.hub_vpc_main.id
  destination_cidr_block    = var.vpc_cidrs.apac_vpc
  vpc_peering_connection_id = aws_vpc_peering_connection.hub_to_eu_hub.id
  
  depends_on = [aws_vpc_peering_connection_accepter.hub_to_eu_hub_accepter]
}

resource "aws_route" "hub_to_prod" {
  provider = aws.primary
  
  route_table_id            = data.aws_route_table.hub_vpc_main.id
  destination_cidr_block    = var.vpc_cidrs.prod_vpc
  vpc_peering_connection_id = aws_vpc_peering_connection.hub_to_prod.id
}

resource "aws_route" "hub_to_dev" {
  provider = aws.primary
  
  route_table_id            = data.aws_route_table.hub_vpc_main.id
  destination_cidr_block    = var.vpc_cidrs.dev_vpc
  vpc_peering_connection_id = aws_vpc_peering_connection.hub_to_dev.id
}

# DR Hub (US-West-2) Routes
resource "aws_route" "dr_hub_to_primary_hub" {
  provider = aws.secondary
  
  route_table_id            = data.aws_route_table.dr_hub_vpc_main.id
  destination_cidr_block    = var.vpc_cidrs.hub_vpc
  vpc_peering_connection_id = aws_vpc_peering_connection.hub_to_dr_hub.id
  
  depends_on = [aws_vpc_peering_connection_accepter.hub_to_dr_hub_accepter]
}

resource "aws_route" "dr_hub_to_prod_via_primary_hub" {
  provider = aws.secondary
  
  route_table_id            = data.aws_route_table.dr_hub_vpc_main.id
  destination_cidr_block    = var.vpc_cidrs.prod_vpc
  vpc_peering_connection_id = aws_vpc_peering_connection.hub_to_dr_hub.id
  
  depends_on = [aws_vpc_peering_connection_accepter.hub_to_dr_hub_accepter]
}

resource "aws_route" "dr_hub_to_dev_via_primary_hub" {
  provider = aws.secondary
  
  route_table_id            = data.aws_route_table.dr_hub_vpc_main.id
  destination_cidr_block    = var.vpc_cidrs.dev_vpc
  vpc_peering_connection_id = aws_vpc_peering_connection.hub_to_dr_hub.id
  
  depends_on = [aws_vpc_peering_connection_accepter.hub_to_dr_hub_accepter]
}

resource "aws_route" "dr_hub_to_eu_hub" {
  provider = aws.secondary
  
  route_table_id            = data.aws_route_table.dr_hub_vpc_main.id
  destination_cidr_block    = var.vpc_cidrs.eu_hub_vpc
  vpc_peering_connection_id = aws_vpc_peering_connection.dr_hub_to_eu_hub.id
  
  depends_on = [aws_vpc_peering_connection_accepter.dr_hub_to_eu_hub_accepter]
}

resource "aws_route" "dr_hub_to_eu_prod_via_eu_hub" {
  provider = aws.secondary
  
  route_table_id            = data.aws_route_table.dr_hub_vpc_main.id
  destination_cidr_block    = var.vpc_cidrs.eu_prod_vpc
  vpc_peering_connection_id = aws_vpc_peering_connection.dr_hub_to_eu_hub.id
  
  depends_on = [aws_vpc_peering_connection_accepter.dr_hub_to_eu_hub_accepter]
}

resource "aws_route" "dr_hub_to_apac_via_eu_hub" {
  provider = aws.secondary
  
  route_table_id            = data.aws_route_table.dr_hub_vpc_main.id
  destination_cidr_block    = var.vpc_cidrs.apac_vpc
  vpc_peering_connection_id = aws_vpc_peering_connection.dr_hub_to_eu_hub.id
  
  depends_on = [aws_vpc_peering_connection_accepter.dr_hub_to_eu_hub_accepter]
}

resource "aws_route" "dr_hub_to_dr_prod" {
  provider = aws.secondary
  
  route_table_id            = data.aws_route_table.dr_hub_vpc_main.id
  destination_cidr_block    = var.vpc_cidrs.dr_prod_vpc
  vpc_peering_connection_id = aws_vpc_peering_connection.dr_hub_to_dr_prod.id
}

# EU Hub (EU-West-1) Routes
resource "aws_route" "eu_hub_to_primary_hub" {
  provider = aws.eu
  
  route_table_id            = data.aws_route_table.eu_hub_vpc_main.id
  destination_cidr_block    = var.vpc_cidrs.hub_vpc
  vpc_peering_connection_id = aws_vpc_peering_connection.hub_to_eu_hub.id
  
  depends_on = [aws_vpc_peering_connection_accepter.hub_to_eu_hub_accepter]
}

resource "aws_route" "eu_hub_to_prod_via_primary_hub" {
  provider = aws.eu
  
  route_table_id            = data.aws_route_table.eu_hub_vpc_main.id
  destination_cidr_block    = var.vpc_cidrs.prod_vpc
  vpc_peering_connection_id = aws_vpc_peering_connection.hub_to_eu_hub.id
  
  depends_on = [aws_vpc_peering_connection_accepter.hub_to_eu_hub_accepter]
}

resource "aws_route" "eu_hub_to_dev_via_primary_hub" {
  provider = aws.eu
  
  route_table_id            = data.aws_route_table.eu_hub_vpc_main.id
  destination_cidr_block    = var.vpc_cidrs.dev_vpc
  vpc_peering_connection_id = aws_vpc_peering_connection.hub_to_eu_hub.id
  
  depends_on = [aws_vpc_peering_connection_accepter.hub_to_eu_hub_accepter]
}

resource "aws_route" "eu_hub_to_dr_hub" {
  provider = aws.eu
  
  route_table_id            = data.aws_route_table.eu_hub_vpc_main.id
  destination_cidr_block    = var.vpc_cidrs.dr_hub_vpc
  vpc_peering_connection_id = aws_vpc_peering_connection.dr_hub_to_eu_hub.id
  
  depends_on = [aws_vpc_peering_connection_accepter.dr_hub_to_eu_hub_accepter]
}

resource "aws_route" "eu_hub_to_dr_prod_via_dr_hub" {
  provider = aws.eu
  
  route_table_id            = data.aws_route_table.eu_hub_vpc_main.id
  destination_cidr_block    = var.vpc_cidrs.dr_prod_vpc
  vpc_peering_connection_id = aws_vpc_peering_connection.dr_hub_to_eu_hub.id
  
  depends_on = [aws_vpc_peering_connection_accepter.dr_hub_to_eu_hub_accepter]
}

resource "aws_route" "eu_hub_to_apac" {
  provider = aws.eu
  
  route_table_id            = data.aws_route_table.eu_hub_vpc_main.id
  destination_cidr_block    = var.vpc_cidrs.apac_vpc
  vpc_peering_connection_id = aws_vpc_peering_connection.apac_to_eu_hub.id
  
  depends_on = [aws_vpc_peering_connection_accepter.apac_to_eu_hub_accepter]
}

resource "aws_route" "eu_hub_to_eu_prod" {
  provider = aws.eu
  
  route_table_id            = data.aws_route_table.eu_hub_vpc_main.id
  destination_cidr_block    = var.vpc_cidrs.eu_prod_vpc
  vpc_peering_connection_id = aws_vpc_peering_connection.eu_hub_to_eu_prod.id
}

#===============================================================================
# SPOKE ROUTE TABLE CONFIGURATIONS - INTELLIGENT ROUTING
#===============================================================================

# Primary Production VPC Routes
resource "aws_route" "prod_to_hub" {
  provider = aws.primary
  
  route_table_id            = data.aws_route_table.prod_vpc_main.id
  destination_cidr_block    = var.vpc_cidrs.hub_vpc
  vpc_peering_connection_id = aws_vpc_peering_connection.hub_to_prod.id
}

resource "aws_route" "prod_to_others_via_hub" {
  provider = aws.primary
  
  route_table_id            = data.aws_route_table.prod_vpc_main.id
  destination_cidr_block    = "10.10.0.0/8"
  vpc_peering_connection_id = aws_vpc_peering_connection.hub_to_prod.id
}

# Primary Development VPC Routes
resource "aws_route" "dev_to_hub" {
  provider = aws.primary
  
  route_table_id            = data.aws_route_table.dev_vpc_main.id
  destination_cidr_block    = var.vpc_cidrs.hub_vpc
  vpc_peering_connection_id = aws_vpc_peering_connection.hub_to_dev.id
}

resource "aws_route" "dev_to_others_via_hub" {
  provider = aws.primary
  
  route_table_id            = data.aws_route_table.dev_vpc_main.id
  destination_cidr_block    = "10.10.0.0/8"
  vpc_peering_connection_id = aws_vpc_peering_connection.hub_to_dev.id
}

# DR Production VPC Routes
resource "aws_route" "dr_prod_to_dr_hub" {
  provider = aws.secondary
  
  route_table_id            = data.aws_route_table.dr_prod_vpc_main.id
  destination_cidr_block    = var.vpc_cidrs.dr_hub_vpc
  vpc_peering_connection_id = aws_vpc_peering_connection.dr_hub_to_dr_prod.id
}

resource "aws_route" "dr_prod_to_others_via_dr_hub" {
  provider = aws.secondary
  
  route_table_id            = data.aws_route_table.dr_prod_vpc_main.id
  destination_cidr_block    = "10.0.0.0/8"
  vpc_peering_connection_id = aws_vpc_peering_connection.dr_hub_to_dr_prod.id
}

# EU Production VPC Routes
resource "aws_route" "eu_prod_to_eu_hub" {
  provider = aws.eu
  
  route_table_id            = data.aws_route_table.eu_prod_vpc_main.id
  destination_cidr_block    = var.vpc_cidrs.eu_hub_vpc
  vpc_peering_connection_id = aws_vpc_peering_connection.eu_hub_to_eu_prod.id
}

resource "aws_route" "eu_prod_to_others_via_eu_hub" {
  provider = aws.eu
  
  route_table_id            = data.aws_route_table.eu_prod_vpc_main.id
  destination_cidr_block    = "10.0.0.0/8"
  vpc_peering_connection_id = aws_vpc_peering_connection.eu_hub_to_eu_prod.id
}

# APAC VPC Routes (via EU Hub)
resource "aws_route" "apac_to_eu_hub" {
  provider = aws.apac
  
  route_table_id            = data.aws_route_table.apac_vpc_main.id
  destination_cidr_block    = var.vpc_cidrs.eu_hub_vpc
  vpc_peering_connection_id = aws_vpc_peering_connection.apac_to_eu_hub.id
  
  depends_on = [aws_vpc_peering_connection_accepter.apac_to_eu_hub_accepter]
}

resource "aws_route" "apac_to_others_via_eu_hub" {
  provider = aws.apac
  
  route_table_id            = data.aws_route_table.apac_vpc_main.id
  destination_cidr_block    = "10.0.0.0/8"
  vpc_peering_connection_id = aws_vpc_peering_connection.apac_to_eu_hub.id
  
  depends_on = [aws_vpc_peering_connection_accepter.apac_to_eu_hub_accepter]
}

#===============================================================================
# ROUTE 53 RESOLVER FOR CROSS-REGION DNS
#===============================================================================

# Route 53 Resolver Rule for internal domain resolution
resource "aws_route53_resolver_rule" "internal_domain" {
  count = var.enable_route53_resolver ? 1 : 0
  
  provider = aws.primary
  
  domain_name = var.internal_domain_name
  name        = "${local.name_prefix}-internal-domain-resolver"
  rule_type   = "FORWARD"
  
  target_ip {
    ip   = cidrhost(var.subnet_cidrs.hub_subnet, 100)
    port = 53
  }
  
  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-internal-domain-resolver"
    Type = "dns-resolver"
  })
}

# Associate resolver rule with VPCs in primary region
resource "aws_route53_resolver_rule_association" "hub_vpc" {
  count = var.enable_route53_resolver ? 1 : 0
  
  provider = aws.primary
  
  resolver_rule_id = aws_route53_resolver_rule.internal_domain[0].id
  vpc_id           = aws_vpc.hub_vpc.id
}

resource "aws_route53_resolver_rule_association" "prod_vpc" {
  count = var.enable_route53_resolver ? 1 : 0
  
  provider = aws.primary
  
  resolver_rule_id = aws_route53_resolver_rule.internal_domain[0].id
  vpc_id           = aws_vpc.prod_vpc.id
}

resource "aws_route53_resolver_rule_association" "dev_vpc" {
  count = var.enable_route53_resolver ? 1 : 0
  
  provider = aws.primary
  
  resolver_rule_id = aws_route53_resolver_rule.internal_domain[0].id
  vpc_id           = aws_vpc.dev_vpc.id
}

#===============================================================================
# VPC FLOW LOGS FOR MONITORING AND SECURITY
#===============================================================================

# CloudWatch Log Group for VPC Flow Logs
resource "aws_cloudwatch_log_group" "vpc_flow_logs" {
  count = var.enable_flow_logs ? 1 : 0
  
  provider = aws.primary
  
  name              = "/aws/vpc/flowlogs/${local.name_prefix}"
  retention_in_days = var.cloudwatch_log_retention_days
  
  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-vpc-flow-logs"
    Type = "monitoring"
  })
}

# IAM Role for VPC Flow Logs
resource "aws_iam_role" "vpc_flow_logs_role" {
  count = var.enable_flow_logs ? 1 : 0
  
  provider = aws.primary
  
  name = "${local.name_prefix}-vpc-flow-logs-role"
  
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
    Name = "${local.name_prefix}-vpc-flow-logs-role"
    Type = "iam"
  })
}

# IAM Policy for VPC Flow Logs
resource "aws_iam_role_policy" "vpc_flow_logs_policy" {
  count = var.enable_flow_logs ? 1 : 0
  
  provider = aws.primary
  
  name = "${local.name_prefix}-vpc-flow-logs-policy"
  role = aws_iam_role.vpc_flow_logs_role[0].id
  
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
        Effect = "Allow"
        Resource = "arn:aws:logs:*:*:*"
      }
    ]
  })
}

# VPC Flow Logs for Hub VPC
resource "aws_flow_log" "hub_vpc_flow_logs" {
  count = var.enable_flow_logs ? 1 : 0
  
  provider = aws.primary
  
  iam_role_arn    = aws_iam_role.vpc_flow_logs_role[0].arn
  log_destination = aws_cloudwatch_log_group.vpc_flow_logs[0].arn
  traffic_type    = var.flow_logs_traffic_type
  vpc_id          = aws_vpc.hub_vpc.id
  
  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-hub-vpc-flow-logs"
    Type = "monitoring"
  })
}

#===============================================================================
# CLOUDWATCH MONITORING AND ALARMS
#===============================================================================

# CloudWatch Alarm for Route53 Resolver Query Failures
resource "aws_cloudwatch_metric_alarm" "route53_resolver_query_failures" {
  count = var.enable_cloudwatch_monitoring && var.enable_route53_resolver ? 1 : 0
  
  provider = aws.primary
  
  alarm_name          = "${local.name_prefix}-route53-resolver-query-failures"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "QueryCount"
  namespace           = "AWS/Route53Resolver"
  period              = "300"
  statistic           = "Sum"
  threshold           = "100"
  alarm_description   = "High DNS query failures in Route53 Resolver"
  alarm_actions       = []
  
  dimensions = {
    ResolverRuleId = aws_route53_resolver_rule.internal_domain[0].id
  }
  
  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-route53-resolver-alarm"
    Type = "monitoring"
  })
}

# CloudWatch Alarm for VPC Peering Connection Failures
resource "aws_cloudwatch_metric_alarm" "vpc_peering_failures" {
  count = var.enable_cloudwatch_monitoring ? 1 : 0
  
  provider = aws.primary
  
  alarm_name          = "${local.name_prefix}-vpc-peering-failures"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "PacketDropCount"
  namespace           = "AWS/VPC"
  period              = "300"
  statistic           = "Sum"
  threshold           = "1000"
  alarm_description   = "High packet drop count on VPC peering connections"
  alarm_actions       = []
  
  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-vpc-peering-failures-alarm"
    Type = "monitoring"
  })
}