# Main Terraform configuration for VPC Lattice Service Catalog solution
# This file creates a complete Service Catalog portfolio with standardized VPC Lattice templates

# Data sources for current AWS account and region information
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# Data source for available availability zones
data "aws_availability_zones" "available" {
  state = "available"
}

# Generate random suffix for unique resource naming
resource "random_id" "suffix" {
  byte_length = 3
}

# Local values for computed names and configurations
locals {
  resource_suffix        = random_id.suffix.hex
  portfolio_name        = var.portfolio_name != "" ? var.portfolio_name : "${var.project_name}-portfolio-${local.resource_suffix}"
  s3_bucket_name        = var.s3_bucket_name != "" ? var.s3_bucket_name : "${var.project_name}-templates-${local.resource_suffix}"
  cloudtrail_bucket_name = var.cloudtrail_s3_bucket_name != "" ? var.cloudtrail_s3_bucket_name : "${var.project_name}-cloudtrail-${local.resource_suffix}"
  test_service_network_name = var.test_service_network_name != "" ? var.test_service_network_name : "test-network-${local.resource_suffix}"
  test_service_name      = var.test_service_name != "" ? var.test_service_name : "test-service-${local.resource_suffix}"
  
  common_tags = merge(var.tags, {
    Project     = var.project_name
    Environment = var.environment
    Purpose     = "VPCLatticeStandardization"
    ManagedBy   = "Terraform"
  })
}

# S3 bucket for storing CloudFormation templates
resource "aws_s3_bucket" "cloudformation_templates" {
  bucket = local.s3_bucket_name
  tags   = local.common_tags
}

# S3 bucket versioning configuration
resource "aws_s3_bucket_versioning" "cloudformation_templates" {
  bucket = aws_s3_bucket.cloudformation_templates.id
  versioning_configuration {
    status = "Enabled"
  }
}

# S3 bucket encryption configuration
resource "aws_s3_bucket_server_side_encryption_configuration" "cloudformation_templates" {
  bucket = aws_s3_bucket.cloudformation_templates.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
    bucket_key_enabled = true
  }
}

# S3 bucket public access block
resource "aws_s3_bucket_public_access_block" "cloudformation_templates" {
  bucket = aws_s3_bucket.cloudformation_templates.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# CloudFormation template for VPC Lattice Service Network
resource "aws_s3_object" "service_network_template" {
  bucket = aws_s3_bucket.cloudformation_templates.bucket
  key    = "service-network-template.yaml"
  content = yamlencode({
    AWSTemplateFormatVersion = "2010-09-09"
    Description              = "Standardized VPC Lattice Service Network"
    
    Parameters = {
      NetworkName = {
        Type        = "String"
        Default     = "standard-service-network"
        Description = "Name for the VPC Lattice service network"
      }
      AuthType = {
        Type           = "String"
        Default        = "AWS_IAM"
        AllowedValues  = ["AWS_IAM", "NONE"]
        Description    = "Authentication type for the service network"
      }
    }
    
    Resources = {
      ServiceNetwork = {
        Type = "AWS::VpcLattice::ServiceNetwork"
        Properties = {
          Name     = { Ref = "NetworkName" }
          AuthType = { Ref = "AuthType" }
          Tags = [
            {
              Key   = "Purpose"
              Value = "StandardizedDeployment"
            },
            {
              Key   = "ManagedBy"
              Value = "ServiceCatalog"
            }
          ]
        }
      }
      
      ServiceNetworkPolicy = {
        Type = "AWS::VpcLattice::AuthPolicy"
        Properties = {
          ResourceIdentifier = { Ref = "ServiceNetwork" }
          Policy = {
            Version = "2012-10-17"
            Statement = [
              {
                Effect    = "Allow"
                Principal = "*"
                Action    = "vpc-lattice-svcs:Invoke"
                Resource  = "*"
                Condition = {
                  StringEquals = {
                    "aws:PrincipalAccount" = { Ref = "AWS::AccountId" }
                  }
                }
              }
            ]
          }
        }
      }
    }
    
    Outputs = {
      ServiceNetworkId = {
        Description = "Service Network ID"
        Value       = { Ref = "ServiceNetwork" }
        Export = {
          Name = { "Fn::Sub" = "\${AWS::StackName}-ServiceNetworkId" }
        }
      }
      ServiceNetworkArn = {
        Description = "Service Network ARN"
        Value       = { "Fn::GetAtt" = ["ServiceNetwork", "Arn"] }
        Export = {
          Name = { "Fn::Sub" = "\${AWS::StackName}-ServiceNetworkArn" }
        }
      }
    }
  })

  tags = local.common_tags
}

# CloudFormation template for VPC Lattice Service
resource "aws_s3_object" "lattice_service_template" {
  bucket = aws_s3_bucket.cloudformation_templates.bucket
  key    = "lattice-service-template.yaml"
  content = yamlencode({
    AWSTemplateFormatVersion = "2010-09-09"
    Description              = "Standardized VPC Lattice Service with Target Group"
    
    Parameters = {
      ServiceName = {
        Type        = "String"
        Description = "Name for the VPC Lattice service"
      }
      ServiceNetworkId = {
        Type        = "String"
        Description = "Service Network ID to associate with"
      }
      TargetType = {
        Type          = "String"
        Default       = "IP"
        AllowedValues = ["IP", "LAMBDA", "ALB"]
        Description   = "Type of targets for the target group"
      }
      VpcId = {
        Type        = "AWS::EC2::VPC::Id"
        Description = "VPC ID for the target group"
      }
      Port = {
        Type        = "Number"
        Default     = 80
        MinValue    = 1
        MaxValue    = 65535
        Description = "Port for the service listener"
      }
      Protocol = {
        Type          = "String"
        Default       = "HTTP"
        AllowedValues = ["HTTP", "HTTPS"]
        Description   = "Protocol for the service listener"
      }
    }
    
    Resources = {
      TargetGroup = {
        Type = "AWS::VpcLattice::TargetGroup"
        Properties = {
          Name          = { "Fn::Sub" = "\${ServiceName}-targets" }
          Type          = { Ref = "TargetType" }
          Port          = { Ref = "Port" }
          Protocol      = { Ref = "Protocol" }
          VpcIdentifier = { Ref = "VpcId" }
          HealthCheck = {
            Enabled                     = true
            HealthCheckIntervalSeconds  = 30
            HealthCheckTimeoutSeconds   = 5
            HealthyThresholdCount      = 2
            UnhealthyThresholdCount    = 3
            Matcher = {
              HttpCode = "200"
            }
            Path     = "/health"
            Port     = { Ref = "Port" }
            Protocol = { Ref = "Protocol" }
          }
          Tags = [
            {
              Key   = "Purpose"
              Value = "StandardizedDeployment"
            },
            {
              Key   = "ManagedBy"
              Value = "ServiceCatalog"
            }
          ]
        }
      }
      
      Service = {
        Type = "AWS::VpcLattice::Service"
        Properties = {
          Name     = { Ref = "ServiceName" }
          AuthType = "AWS_IAM"
          Tags = [
            {
              Key   = "Purpose"
              Value = "StandardizedDeployment"
            },
            {
              Key   = "ManagedBy"
              Value = "ServiceCatalog"
            }
          ]
        }
      }
      
      Listener = {
        Type = "AWS::VpcLattice::Listener"
        Properties = {
          ServiceIdentifier = { Ref = "Service" }
          Name              = "default-listener"
          Port              = { Ref = "Port" }
          Protocol          = { Ref = "Protocol" }
          DefaultAction = {
            Forward = {
              TargetGroups = [
                {
                  TargetGroupIdentifier = { Ref = "TargetGroup" }
                  Weight               = 100
                }
              ]
            }
          }
        }
      }
      
      ServiceNetworkAssociation = {
        Type = "AWS::VpcLattice::ServiceNetworkServiceAssociation"
        Properties = {
          ServiceIdentifier        = { Ref = "Service" }
          ServiceNetworkIdentifier = { Ref = "ServiceNetworkId" }
        }
      }
    }
    
    Outputs = {
      ServiceId = {
        Description = "VPC Lattice Service ID"
        Value       = { Ref = "Service" }
      }
      ServiceArn = {
        Description = "VPC Lattice Service ARN"
        Value       = { "Fn::GetAtt" = ["Service", "Arn"] }
      }
      TargetGroupId = {
        Description = "Target Group ID"
        Value       = { Ref = "TargetGroup" }
      }
      TargetGroupArn = {
        Description = "Target Group ARN"
        Value       = { "Fn::GetAtt" = ["TargetGroup", "Arn"] }
      }
    }
  })

  tags = local.common_tags
}

# IAM role for Service Catalog launch constraints
resource "aws_iam_role" "service_catalog_launch_role" {
  name = "ServiceCatalogVpcLatticeRole-${local.resource_suffix}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "servicecatalog.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = local.common_tags
}

# IAM policy for VPC Lattice operations
resource "aws_iam_role_policy" "vpc_lattice_permissions" {
  name = "VpcLatticePermissions"
  role = aws_iam_role.service_catalog_launch_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "vpc-lattice:*",
          "ec2:DescribeVpcs",
          "ec2:DescribeSubnets",
          "ec2:DescribeSecurityGroups",
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "cloudformation:*"
        ]
        Resource = "*"
      }
    ]
  })
}

# Service Catalog Portfolio
resource "aws_servicecatalog_portfolio" "vpc_lattice_portfolio" {
  name          = local.portfolio_name
  description   = var.portfolio_description
  provider_name = var.portfolio_provider_name

  tags = local.common_tags
}

# Service Catalog Product for Service Network
resource "aws_servicecatalog_product" "service_network_product" {
  name  = var.service_network_product_name
  owner = var.portfolio_provider_name
  type  = "CLOUD_FORMATION_TEMPLATE"

  description = "Standardized VPC Lattice Service Network"

  provisioning_artifact_parameters {
    name        = "v1.0"
    description = "Initial version"
    template_url = "https://s3.${data.aws_region.current.name}.amazonaws.com/${aws_s3_bucket.cloudformation_templates.bucket}/${aws_s3_object.service_network_template.key}"
    type        = "CLOUD_FORMATION_TEMPLATE"
  }

  tags = local.common_tags

  depends_on = [aws_s3_object.service_network_template]
}

# Service Catalog Product for Lattice Service
resource "aws_servicecatalog_product" "lattice_service_product" {
  name  = var.lattice_service_product_name
  owner = var.portfolio_provider_name
  type  = "CLOUD_FORMATION_TEMPLATE"

  description = "Standardized VPC Lattice Service with Target Group"

  provisioning_artifact_parameters {
    name        = "v1.0"
    description = "Initial version"
    template_url = "https://s3.${data.aws_region.current.name}.amazonaws.com/${aws_s3_bucket.cloudformation_templates.bucket}/${aws_s3_object.lattice_service_template.key}"
    type        = "CLOUD_FORMATION_TEMPLATE"
  }

  tags = local.common_tags

  depends_on = [aws_s3_object.lattice_service_template]
}

# Associate Service Network Product with Portfolio
resource "aws_servicecatalog_product_portfolio_association" "service_network_association" {
  portfolio_id = aws_servicecatalog_portfolio.vpc_lattice_portfolio.id
  product_id   = aws_servicecatalog_product.service_network_product.id
}

# Associate Lattice Service Product with Portfolio
resource "aws_servicecatalog_product_portfolio_association" "lattice_service_association" {
  portfolio_id = aws_servicecatalog_portfolio.vpc_lattice_portfolio.id
  product_id   = aws_servicecatalog_product.lattice_service_product.id
}

# Launch Constraint for Service Network Product
resource "aws_servicecatalog_constraint" "service_network_launch_constraint" {
  description   = "IAM role for VPC Lattice service network deployment"
  portfolio_id  = aws_servicecatalog_portfolio.vpc_lattice_portfolio.id
  product_id    = aws_servicecatalog_product.service_network_product.id
  type          = "LAUNCH"
  parameters    = jsonencode({
    RoleArn = aws_iam_role.service_catalog_launch_role.arn
  })

  depends_on = [aws_servicecatalog_product_portfolio_association.service_network_association]
}

# Launch Constraint for Lattice Service Product
resource "aws_servicecatalog_constraint" "lattice_service_launch_constraint" {
  description   = "IAM role for VPC Lattice service deployment"
  portfolio_id  = aws_servicecatalog_portfolio.vpc_lattice_portfolio.id
  product_id    = aws_servicecatalog_product.lattice_service_product.id
  type          = "LAUNCH"
  parameters    = jsonencode({
    RoleArn = aws_iam_role.service_catalog_launch_role.arn
  })

  depends_on = [aws_servicecatalog_product_portfolio_association.lattice_service_association]
}

# Grant portfolio access to specified principals
resource "aws_servicecatalog_principal_portfolio_association" "portfolio_access" {
  count = length(var.principal_arns)
  
  portfolio_id  = aws_servicecatalog_portfolio.vpc_lattice_portfolio.id
  principal_arn = var.principal_arns[count.index]
  principal_type = startswith(var.principal_arns[count.index], "arn:aws:iam::") ? "IAM" : "IAM"
}

# Grant portfolio access to current user if no principals specified
data "aws_caller_identity" "current_user" {}

resource "aws_servicecatalog_principal_portfolio_association" "current_user_access" {
  count = length(var.principal_arns) == 0 ? 1 : 0
  
  portfolio_id   = aws_servicecatalog_portfolio.vpc_lattice_portfolio.id
  principal_arn  = data.aws_caller_identity.current_user.arn
  principal_type = "IAM"
}

# Optional: Create test VPC for demonstration
resource "aws_vpc" "test_vpc" {
  count = var.create_test_vpc ? 1 : 0
  
  cidr_block           = var.test_vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-test-vpc-${local.resource_suffix}"
  })
}

# Internet Gateway for test VPC
resource "aws_internet_gateway" "test_igw" {
  count = var.create_test_vpc ? 1 : 0
  
  vpc_id = aws_vpc.test_vpc[0].id

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-test-igw-${local.resource_suffix}"
  })
}

# Test subnets in different availability zones
resource "aws_subnet" "test_subnets" {
  count = var.create_test_vpc ? length(var.test_subnet_cidrs) : 0
  
  vpc_id                  = aws_vpc.test_vpc[0].id
  cidr_block              = var.test_subnet_cidrs[count.index]
  availability_zone       = data.aws_availability_zones.available.names[count.index % length(data.aws_availability_zones.available.names)]
  map_public_ip_on_launch = true

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-test-subnet-${count.index + 1}-${local.resource_suffix}"
  })
}

# Route table for test VPC
resource "aws_route_table" "test_rt" {
  count = var.create_test_vpc ? 1 : 0
  
  vpc_id = aws_vpc.test_vpc[0].id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.test_igw[0].id
  }

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-test-rt-${local.resource_suffix}"
  })
}

# Associate route table with test subnets
resource "aws_route_table_association" "test_subnet_associations" {
  count = var.create_test_vpc ? length(aws_subnet.test_subnets) : 0
  
  subnet_id      = aws_subnet.test_subnets[count.index].id
  route_table_id = aws_route_table.test_rt[0].id
}

# Optional: Deploy test VPC Lattice resources
resource "aws_vpclattice_service_network" "test_service_network" {
  count = var.deploy_test_resources ? 1 : 0
  
  name      = local.test_service_network_name
  auth_type = "AWS_IAM"

  tags = merge(local.common_tags, {
    Purpose = "TestDeployment"
  })
}

# Test VPC Lattice service
resource "aws_vpclattice_service" "test_service" {
  count = var.deploy_test_resources ? 1 : 0
  
  name      = local.test_service_name
  auth_type = "AWS_IAM"

  tags = merge(local.common_tags, {
    Purpose = "TestDeployment"
  })
}

# Test target group
resource "aws_vpclattice_target_group" "test_target_group" {
  count = var.deploy_test_resources && var.create_test_vpc ? 1 : 0
  
  name   = "${local.test_service_name}-targets"
  type   = var.test_target_type
  port   = var.test_service_port
  protocol = var.test_service_protocol
  vpc_identifier = aws_vpc.test_vpc[0].id

  config {
    health_check {
      enabled                       = true
      health_check_interval_seconds = 30
      health_check_timeout_seconds  = 5
      healthy_threshold_count       = 2
      unhealthy_threshold_count     = 3
      matcher {
        value = "200"
      }
      path     = "/health"
      port     = var.test_service_port
      protocol = var.test_service_protocol
    }
  }

  tags = merge(local.common_tags, {
    Purpose = "TestDeployment"
  })
}

# Test listener
resource "aws_vpclattice_listener" "test_listener" {
  count = var.deploy_test_resources ? 1 : 0
  
  name               = "default-listener"
  port               = var.test_service_port
  protocol           = var.test_service_protocol
  service_identifier = aws_vpclattice_service.test_service[0].id

  default_action {
    forward {
      target_groups {
        target_group_identifier = var.create_test_vpc ? aws_vpclattice_target_group.test_target_group[0].id : ""
        weight                  = 100
      }
    }
  }

  tags = merge(local.common_tags, {
    Purpose = "TestDeployment"
  })

  depends_on = [aws_vpclattice_target_group.test_target_group]
}

# Test service network association
resource "aws_vpclattice_service_network_service_association" "test_association" {
  count = var.deploy_test_resources ? 1 : 0
  
  service_identifier         = aws_vpclattice_service.test_service[0].id
  service_network_identifier = aws_vpclattice_service_network.test_service_network[0].id

  tags = merge(local.common_tags, {
    Purpose = "TestDeployment"
  })
}

# Optional: CloudTrail for auditing Service Catalog events
resource "aws_s3_bucket" "cloudtrail_logs" {
  count = var.enable_cloudtrail_logging ? 1 : 0
  
  bucket = local.cloudtrail_bucket_name
  tags   = local.common_tags
}

resource "aws_s3_bucket_versioning" "cloudtrail_logs" {
  count = var.enable_cloudtrail_logging ? 1 : 0
  
  bucket = aws_s3_bucket.cloudtrail_logs[0].id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "cloudtrail_logs" {
  count = var.enable_cloudtrail_logging ? 1 : 0
  
  bucket = aws_s3_bucket.cloudtrail_logs[0].id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_public_access_block" "cloudtrail_logs" {
  count = var.enable_cloudtrail_logging ? 1 : 0
  
  bucket = aws_s3_bucket.cloudtrail_logs[0].id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_policy" "cloudtrail_logs" {
  count = var.enable_cloudtrail_logging ? 1 : 0
  
  bucket = aws_s3_bucket.cloudtrail_logs[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AWSCloudTrailAclCheck"
        Effect = "Allow"
        Principal = {
          Service = "cloudtrail.amazonaws.com"
        }
        Action   = "s3:GetBucketAcl"
        Resource = aws_s3_bucket.cloudtrail_logs[0].arn
        Condition = {
          StringEquals = {
            "AWS:SourceArn" = "arn:aws:cloudtrail:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:trail/${var.project_name}-service-catalog-trail-${local.resource_suffix}"
          }
        }
      },
      {
        Sid    = "AWSCloudTrailWrite"
        Effect = "Allow"
        Principal = {
          Service = "cloudtrail.amazonaws.com"
        }
        Action   = "s3:PutObject"
        Resource = "${aws_s3_bucket.cloudtrail_logs[0].arn}/*"
        Condition = {
          StringEquals = {
            "s3:x-amz-acl" = "bucket-owner-full-control"
            "AWS:SourceArn" = "arn:aws:cloudtrail:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:trail/${var.project_name}-service-catalog-trail-${local.resource_suffix}"
          }
        }
      }
    ]
  })

  depends_on = [aws_s3_bucket_public_access_block.cloudtrail_logs]
}

resource "aws_cloudtrail" "service_catalog_trail" {
  count = var.enable_cloudtrail_logging ? 1 : 0
  
  name           = "${var.project_name}-service-catalog-trail-${local.resource_suffix}"
  s3_bucket_name = aws_s3_bucket.cloudtrail_logs[0].bucket

  event_selector {
    read_write_type                 = "All"
    include_management_events       = true
    exclude_management_event_sources = []

    data_resource {
      type   = "AWS::ServiceCatalog::Product"
      values = ["arn:aws:servicecatalog:*"]
    }
  }

  tags = local.common_tags

  depends_on = [aws_s3_bucket_policy.cloudtrail_logs]
}