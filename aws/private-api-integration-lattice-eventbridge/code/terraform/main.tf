# Data sources for current AWS account and region
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}
data "aws_availability_zones" "available" {
  state = "available"
}

# Random suffix for unique resource naming
resource "random_id" "suffix" {
  byte_length = 3
}

locals {
  account_id = data.aws_caller_identity.current.account_id
  region     = data.aws_region.current.name
  suffix     = random_id.suffix.hex
  
  # Common tags applied to all resources
  common_tags = merge(
    {
      Project     = var.project_name
      Environment = var.environment
      Purpose     = "private-api-integration"
    },
    var.additional_tags
  )
}

#------------------------------------------------------------------------------
# VPC and Networking Infrastructure
#------------------------------------------------------------------------------

# Target VPC for private API Gateway
resource "aws_vpc" "target_vpc" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = merge(local.common_tags, {
    Name = "target-vpc-${local.suffix}"
  })
}

# Internet Gateway for VPC (required for VPC endpoint DNS resolution)
resource "aws_internet_gateway" "target_igw" {
  vpc_id = aws_vpc.target_vpc.id

  tags = merge(local.common_tags, {
    Name = "target-igw-${local.suffix}"
  })
}

# Subnets in different availability zones for high availability
resource "aws_subnet" "target_subnets" {
  count = length(var.subnet_cidrs)

  vpc_id            = aws_vpc.target_vpc.id
  cidr_block        = var.subnet_cidrs[count.index]
  availability_zone = data.aws_availability_zones.available.names[count.index]

  # Enable auto-assign public IP for outbound internet access
  map_public_ip_on_launch = true

  tags = merge(local.common_tags, {
    Name = "target-subnet-${count.index + 1}-${local.suffix}"
    AZ   = data.aws_availability_zones.available.names[count.index]
  })
}

# Route table for subnets with internet gateway route
resource "aws_route_table" "target_route_table" {
  vpc_id = aws_vpc.target_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.target_igw.id
  }

  tags = merge(local.common_tags, {
    Name = "target-route-table-${local.suffix}"
  })
}

# Associate route table with subnets
resource "aws_route_table_association" "target_subnet_associations" {
  count = length(aws_subnet.target_subnets)

  subnet_id      = aws_subnet.target_subnets[count.index].id
  route_table_id = aws_route_table.target_route_table.id
}

# Security group for VPC endpoint
resource "aws_security_group" "vpc_endpoint_sg" {
  name_prefix = "vpc-endpoint-sg-${local.suffix}"
  vpc_id      = aws_vpc.target_vpc.id
  description = "Security group for API Gateway VPC endpoint"

  ingress {
    description = "HTTPS traffic for API Gateway"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  egress {
    description = "All outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, {
    Name = "vpc-endpoint-sg-${local.suffix}"
  })
}

# VPC Endpoint for API Gateway Execute API
resource "aws_vpc_endpoint" "api_gateway_endpoint" {
  vpc_id              = aws_vpc.target_vpc.id
  service_name        = "com.amazonaws.${local.region}.execute-api"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = aws_subnet.target_subnets[*].id
  security_group_ids  = [aws_security_group.vpc_endpoint_sg.id]
  private_dns_enabled = true

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Principal = "*"
        Action    = "execute-api:*"
        Resource  = "*"
      }
    ]
  })

  tags = merge(local.common_tags, {
    Name = "api-gateway-endpoint-${local.suffix}"
  })
}

#------------------------------------------------------------------------------
# Private API Gateway
#------------------------------------------------------------------------------

# Private API Gateway
resource "aws_api_gateway_rest_api" "private_api" {
  name        = "${var.api_gateway_name}-${local.suffix}"
  description = "Private API Gateway for VPC Lattice integration demo"

  endpoint_configuration {
    types            = ["PRIVATE"]
    vpc_endpoint_ids = [aws_vpc_endpoint.api_gateway_endpoint.id]
  }

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Principal = "*"
        Action    = "execute-api:Invoke"
        Resource  = "*"
        Condition = {
          StringEquals = {
            "aws:sourceVpce" = aws_vpc_endpoint.api_gateway_endpoint.id
          }
        }
      }
    ]
  })

  tags = local.common_tags
}

# API Gateway resource for /orders
resource "aws_api_gateway_resource" "orders_resource" {
  rest_api_id = aws_api_gateway_rest_api.private_api.id
  parent_id   = aws_api_gateway_rest_api.private_api.root_resource_id
  path_part   = "orders"
}

# POST method for orders resource
resource "aws_api_gateway_method" "orders_post" {
  rest_api_id   = aws_api_gateway_rest_api.private_api.id
  resource_id   = aws_api_gateway_resource.orders_resource.id
  http_method   = "POST"
  authorization = "AWS_IAM"
}

# Mock integration for demonstration purposes
resource "aws_api_gateway_integration" "orders_integration" {
  rest_api_id = aws_api_gateway_rest_api.private_api.id
  resource_id = aws_api_gateway_resource.orders_resource.id
  http_method = aws_api_gateway_method.orders_post.http_method

  integration_http_method = "POST"
  type                    = "MOCK"
  
  request_templates = {
    "application/json" = jsonencode({
      statusCode = 200
    })
  }
}

# Method response
resource "aws_api_gateway_method_response" "orders_response" {
  rest_api_id = aws_api_gateway_rest_api.private_api.id
  resource_id = aws_api_gateway_resource.orders_resource.id
  http_method = aws_api_gateway_method.orders_post.http_method
  status_code = "200"

  response_models = {
    "application/json" = "Empty"
  }
}

# Integration response with mock data
resource "aws_api_gateway_integration_response" "orders_integration_response" {
  rest_api_id = aws_api_gateway_rest_api.private_api.id
  resource_id = aws_api_gateway_resource.orders_resource.id
  http_method = aws_api_gateway_method.orders_post.http_method
  status_code = aws_api_gateway_method_response.orders_response.status_code

  response_templates = {
    "application/json" = jsonencode({
      orderId   = "12345"
      status    = "created"
      timestamp = "$context.requestTime"
    })
  }

  depends_on = [aws_api_gateway_integration.orders_integration]
}

# API Gateway deployment
resource "aws_api_gateway_deployment" "api_deployment" {
  depends_on = [
    aws_api_gateway_method.orders_post,
    aws_api_gateway_integration.orders_integration,
    aws_api_gateway_integration_response.orders_integration_response
  ]

  rest_api_id = aws_api_gateway_rest_api.private_api.id
  stage_name  = var.api_gateway_stage_name

  lifecycle {
    create_before_destroy = true
  }

  triggers = {
    redeployment = sha1(jsonencode([
      aws_api_gateway_resource.orders_resource.id,
      aws_api_gateway_method.orders_post.id,
      aws_api_gateway_integration.orders_integration.id,
    ]))
  }
}

#------------------------------------------------------------------------------
# VPC Lattice Infrastructure
#------------------------------------------------------------------------------

# VPC Lattice Service Network
resource "aws_vpclattice_service_network" "private_api_network" {
  name      = "${var.vpc_lattice_service_network_name}-${local.suffix}"
  auth_type = "AWS_IAM"

  tags = local.common_tags
}

# VPC Lattice Resource Gateway
resource "aws_vpclattice_resource_gateway" "api_gateway_resource_gateway" {
  name           = "${var.resource_gateway_name}-${local.suffix}"
  vpc_identifier = aws_vpc.target_vpc.id
  subnet_ids     = aws_subnet.target_subnets[*].id

  tags = merge(local.common_tags, {
    Purpose = "private-api-access"
  })
}

# VPC Lattice Resource Configuration
resource "aws_vpclattice_resource_configuration" "private_api_config" {
  name                     = "${var.resource_configuration_name}-${local.suffix}"
  type                     = "SINGLE"
  resource_gateway_identifier = aws_vpclattice_resource_gateway.api_gateway_resource_gateway.id

  resource_configuration_definition {
    type                = "RESOURCE"
    resource_identifier = aws_vpc_endpoint.api_gateway_endpoint.id
    
    port_ranges {
      from_port = var.api_port
      to_port   = var.api_port
      protocol  = "TCP"
    }
  }

  allow_association_to_shareable_service_network = var.enable_resource_sharing

  tags = merge(local.common_tags, {
    Purpose = "private-api-integration"
  })
}

# Associate Resource Configuration with Service Network
resource "aws_vpclattice_service_network_resource_association" "private_api_association" {
  service_network_identifier        = aws_vpclattice_service_network.private_api_network.id
  resource_configuration_identifier = aws_vpclattice_resource_configuration.private_api_config.arn
}

#------------------------------------------------------------------------------
# IAM Roles and Policies
#------------------------------------------------------------------------------

# IAM role for EventBridge and Step Functions
resource "aws_iam_role" "eventbridge_stepfunctions_role" {
  name = "${var.iam_role_name}-${local.suffix}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = [
            "events.amazonaws.com",
            "states.amazonaws.com"
          ]
        }
      }
    ]
  })

  tags = local.common_tags
}

# IAM policy for VPC Lattice operations
resource "aws_iam_role_policy" "vpc_lattice_connection_policy" {
  name = "VPCLatticeConnectionPolicy"
  role = aws_iam_role.eventbridge_stepfunctions_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "events:CreateConnection",
          "events:UpdateConnection", 
          "events:InvokeApiDestination",
          "execute-api:Invoke",
          "vpc-lattice:GetResourceConfiguration",
          "states:StartExecution"
        ]
        Resource = "*"
      }
    ]
  })
}

#------------------------------------------------------------------------------
# EventBridge Infrastructure
#------------------------------------------------------------------------------

# Custom EventBridge bus
resource "aws_cloudwatch_event_bus" "private_api_bus" {
  name = "${var.eventbridge_bus_name}-${local.suffix}"

  tags = local.common_tags
}

# EventBridge connection for private API
resource "aws_cloudwatch_event_connection" "private_api_connection" {
  name        = "${var.eventbridge_connection_name}-${local.suffix}"
  description = "Connection to private API Gateway via VPC Lattice"

  authorization_type = "INVOCATION_HTTP_PARAMETERS"
  
  auth_parameters {
    invocation_http_parameters {
      header = {
        "Content-Type" = "application/json"
      }
    }
  }
}

# EventBridge API destination for private API
resource "aws_cloudwatch_event_api_destination" "private_api_destination" {
  name                             = "private-api-destination-${local.suffix}"
  description                      = "API destination for private API Gateway"
  invocation_endpoint              = "https://${aws_api_gateway_rest_api.private_api.id}-${aws_vpc_endpoint.api_gateway_endpoint.id}.execute-api.${local.region}.amazonaws.com/${var.api_gateway_stage_name}/orders"
  http_method                      = "POST"
  invocation_rate_limit_per_second = 10
  connection_arn                   = aws_cloudwatch_event_connection.private_api_connection.arn
}

#------------------------------------------------------------------------------
# Step Functions State Machine
#------------------------------------------------------------------------------

# Step Functions state machine definition
locals {
  step_function_definition = jsonencode({
    Comment = "Workflow that invokes private API via VPC Lattice"
    StartAt = "ProcessOrder"
    States = {
      ProcessOrder = {
        Type     = "Task"
        Resource = "arn:aws:states:::http:invoke"
        Parameters = {
          ApiEndpoint = aws_cloudwatch_event_api_destination.private_api_destination.arn
          Method      = "POST"
          RequestBody = {
            customerId = "12345"
            orderItems = ["item1", "item2"]
            "timestamp.$" = "$$.State.EnteredTime"
          }
          Headers = {
            "Content-Type" = "application/json"
          }
        }
        Retry = [
          {
            ErrorEquals     = ["States.Http.StatusCodeFailure"]
            IntervalSeconds = 2
            MaxAttempts     = 3
            BackoffRate     = 2.0
          }
        ]
        Catch = [
          {
            ErrorEquals = ["States.TaskFailed"]
            Next        = "HandleError"
          }
        ]
        Next = "ProcessSuccess"
      }
      ProcessSuccess = {
        Type   = "Pass"
        Result = "Order processed successfully"
        End    = true
      }
      HandleError = {
        Type   = "Pass"
        Result = "Order processing failed"
        End    = true
      }
    }
  })
}

# Step Functions state machine
resource "aws_sfn_state_machine" "private_api_workflow" {
  name       = "${var.step_function_name}-${local.suffix}"
  role_arn   = aws_iam_role.eventbridge_stepfunctions_role.arn
  definition = local.step_function_definition

  tags = local.common_tags
}

#------------------------------------------------------------------------------
# EventBridge Rule and Target
#------------------------------------------------------------------------------

# EventBridge rule to trigger Step Functions
resource "aws_cloudwatch_event_rule" "trigger_workflow" {
  name           = "${var.eventbridge_rule_name}-${local.suffix}"
  description    = "Trigger private API workflow on order events"
  event_bus_name = aws_cloudwatch_event_bus.private_api_bus.name
  state          = "ENABLED"

  event_pattern = jsonencode({
    source        = ["demo.application"]
    "detail-type" = ["Order Received"]
  })

  tags = local.common_tags
}

# EventBridge target for Step Functions
resource "aws_cloudwatch_event_target" "stepfunctions_target" {
  rule           = aws_cloudwatch_event_rule.trigger_workflow.name
  event_bus_name = aws_cloudwatch_event_bus.private_api_bus.name
  target_id      = "StepFunctionsTarget"
  arn            = aws_sfn_state_machine.private_api_workflow.arn
  role_arn       = aws_iam_role.eventbridge_stepfunctions_role.arn
}