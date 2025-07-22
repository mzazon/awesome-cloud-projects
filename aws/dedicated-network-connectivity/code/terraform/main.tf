# Generate random suffix for unique resource naming
resource "random_id" "suffix" {
  byte_length = 4
}

# Get current caller identity for account ID
data "aws_caller_identity" "current" {}

# Get available AZs
data "aws_availability_zones" "available" {
  state = "available"
}

locals {
  project_id = random_id.suffix.hex
  azs        = length(var.availability_zones) > 0 ? var.availability_zones : slice(data.aws_availability_zones.available.names, 0, 2)
  
  common_tags = merge(
    {
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "Terraform"
      Recipe      = "hybrid-cloud-connectivity-aws-direct-connect"
    },
    var.additional_tags
  )
}

# ============================================================================
# VPC Infrastructure
# ============================================================================

# Production VPC
resource "aws_vpc" "production" {
  cidr_block           = var.prod_vpc_cidr
  enable_dns_hostnames = var.enable_dns_hostnames
  enable_dns_support   = var.enable_dns_support

  tags = merge(local.common_tags, {
    Name        = "Production-VPC-${local.project_id}"
    Environment = "Production"
  })
}

# Development VPC
resource "aws_vpc" "development" {
  cidr_block           = var.dev_vpc_cidr
  enable_dns_hostnames = var.enable_dns_hostnames
  enable_dns_support   = var.enable_dns_support

  tags = merge(local.common_tags, {
    Name        = "Development-VPC-${local.project_id}"
    Environment = "Development"
  })
}

# Shared Services VPC
resource "aws_vpc" "shared_services" {
  cidr_block           = var.shared_vpc_cidr
  enable_dns_hostnames = var.enable_dns_hostnames
  enable_dns_support   = var.enable_dns_support

  tags = merge(local.common_tags, {
    Name        = "Shared-Services-VPC-${local.project_id}"
    Environment = "Shared"
  })
}

# ============================================================================
# Transit Gateway and VPC Attachments
# ============================================================================

# Transit Gateway
resource "aws_ec2_transit_gateway" "main" {
  description                     = "Corporate hybrid connectivity gateway"
  amazon_side_asn                 = var.aws_asn
  auto_accept_shared_attachments  = "enable"
  default_route_table_association = "enable"
  default_route_table_propagation = "enable"

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-tgw-${local.project_id}"
  })
}

# Subnets for Transit Gateway attachments
resource "aws_subnet" "prod_tgw" {
  vpc_id            = aws_vpc.production.id
  cidr_block        = cidrsubnet(var.prod_vpc_cidr, 8, 1)
  availability_zone = local.azs[0]

  tags = merge(local.common_tags, {
    Name = "Prod-TGW-Subnet-${local.project_id}"
  })
}

resource "aws_subnet" "dev_tgw" {
  vpc_id            = aws_vpc.development.id
  cidr_block        = cidrsubnet(var.dev_vpc_cidr, 8, 1)
  availability_zone = local.azs[0]

  tags = merge(local.common_tags, {
    Name = "Dev-TGW-Subnet-${local.project_id}"
  })
}

resource "aws_subnet" "shared_tgw" {
  vpc_id            = aws_vpc.shared_services.id
  cidr_block        = cidrsubnet(var.shared_vpc_cidr, 8, 1)
  availability_zone = local.azs[0]

  tags = merge(local.common_tags, {
    Name = "Shared-TGW-Subnet-${local.project_id}"
  })
}

# Transit Gateway VPC Attachments
resource "aws_ec2_transit_gateway_vpc_attachment" "production" {
  subnet_ids         = [aws_subnet.prod_tgw.id]
  transit_gateway_id = aws_ec2_transit_gateway.main.id
  vpc_id             = aws_vpc.production.id

  tags = merge(local.common_tags, {
    Name = "Prod-TGW-Attachment-${local.project_id}"
  })
}

resource "aws_ec2_transit_gateway_vpc_attachment" "development" {
  subnet_ids         = [aws_subnet.dev_tgw.id]
  transit_gateway_id = aws_ec2_transit_gateway.main.id
  vpc_id             = aws_vpc.development.id

  tags = merge(local.common_tags, {
    Name = "Dev-TGW-Attachment-${local.project_id}"
  })
}

resource "aws_ec2_transit_gateway_vpc_attachment" "shared_services" {
  subnet_ids         = [aws_subnet.shared_tgw.id]
  transit_gateway_id = aws_ec2_transit_gateway.main.id
  vpc_id             = aws_vpc.shared_services.id

  tags = merge(local.common_tags, {
    Name = "Shared-TGW-Attachment-${local.project_id}"
  })
}

# ============================================================================
# Direct Connect Gateway and Virtual Interfaces
# ============================================================================

# Direct Connect Gateway
resource "aws_dx_gateway" "main" {
  name           = "${var.dx_gateway_name}-${local.project_id}"
  amazon_side_asn = var.aws_asn

  tags = merge(local.common_tags, {
    Name = "${var.dx_gateway_name}-${local.project_id}"
  })
}

# Direct Connect Gateway Association with Transit Gateway
resource "aws_dx_gateway_association" "main" {
  dx_gateway_id         = aws_dx_gateway.main.id
  associated_gateway_id = aws_ec2_transit_gateway.main.id

  tags = merge(local.common_tags, {
    Name = "DX-TGW-Association-${local.project_id}"
  })
}

# Transit Virtual Interface (requires existing DX connection)
resource "aws_dx_transit_virtual_interface" "main" {
  count = var.dx_connection_id != "" ? 1 : 0

  connection_id   = var.dx_connection_id
  dx_gateway_id   = aws_dx_gateway.main.id
  name            = "transit-vif-${local.project_id}"
  vlan            = var.transit_vif_vlan
  address_family  = "ipv4"
  bgp_asn         = var.on_premises_asn
  customer_address = split("/", var.customer_address)[0]
  amazon_address  = split("/", var.amazon_address)[0]
  bgp_auth_key    = var.bgp_auth_key != "" ? var.bgp_auth_key : null

  tags = merge(local.common_tags, {
    Name = "Transit-VIF-${local.project_id}"
  })
}

# ============================================================================
# Route Tables and Routing
# ============================================================================

# Update main route tables for each VPC to route on-premises traffic through TGW
resource "aws_route" "prod_to_onprem" {
  route_table_id         = aws_vpc.production.main_route_table_id
  destination_cidr_block = var.on_premises_cidr
  transit_gateway_id     = aws_ec2_transit_gateway.main.id

  depends_on = [aws_ec2_transit_gateway_vpc_attachment.production]
}

resource "aws_route" "dev_to_onprem" {
  route_table_id         = aws_vpc.development.main_route_table_id
  destination_cidr_block = var.on_premises_cidr
  transit_gateway_id     = aws_ec2_transit_gateway.main.id

  depends_on = [aws_ec2_transit_gateway_vpc_attachment.development]
}

resource "aws_route" "shared_to_onprem" {
  route_table_id         = aws_vpc.shared_services.main_route_table_id
  destination_cidr_block = var.on_premises_cidr
  transit_gateway_id     = aws_ec2_transit_gateway.main.id

  depends_on = [aws_ec2_transit_gateway_vpc_attachment.shared_services]
}

# ============================================================================
# DNS Resolution (Route 53 Resolver)
# ============================================================================

# Security Group for Route 53 Resolver endpoints
resource "aws_security_group" "resolver_endpoints" {
  count = var.dns_resolver_endpoints ? 1 : 0

  name_prefix = "resolver-endpoints-sg-${local.project_id}"
  description = "Security group for Route 53 Resolver endpoints"
  vpc_id      = aws_vpc.shared_services.id

  ingress {
    description = "DNS UDP from on-premises"
    from_port   = 53
    to_port     = 53
    protocol    = "udp"
    cidr_blocks = [var.on_premises_cidr]
  }

  ingress {
    description = "DNS TCP from on-premises"
    from_port   = 53
    to_port     = 53
    protocol    = "tcp"
    cidr_blocks = [var.on_premises_cidr]
  }

  egress {
    description = "All outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, {
    Name = "Resolver-SG-${local.project_id}"
  })
}

# Route 53 Resolver Inbound Endpoint
resource "aws_route53_resolver_endpoint" "inbound" {
  count = var.dns_resolver_endpoints ? 1 : 0

  name      = "Inbound-Resolver-${local.project_id}"
  direction = "INBOUND"

  security_group_ids = [aws_security_group.resolver_endpoints[0].id]

  ip_address {
    subnet_id = aws_subnet.shared_tgw.id
    ip        = cidrhost(aws_subnet.shared_tgw.cidr_block, 100)
  }

  tags = merge(local.common_tags, {
    Name = "Inbound-Resolver-${local.project_id}"
  })
}

# Route 53 Resolver Outbound Endpoint
resource "aws_route53_resolver_endpoint" "outbound" {
  count = var.dns_resolver_endpoints ? 1 : 0

  name      = "Outbound-Resolver-${local.project_id}"
  direction = "OUTBOUND"

  security_group_ids = [aws_security_group.resolver_endpoints[0].id]

  ip_address {
    subnet_id = aws_subnet.shared_tgw.id
    ip        = cidrhost(aws_subnet.shared_tgw.cidr_block, 101)
  }

  tags = merge(local.common_tags, {
    Name = "Outbound-Resolver-${local.project_id}"
  })
}

# ============================================================================
# Network Security (NACLs)
# ============================================================================

# Network ACL for Shared Services VPC
resource "aws_network_acl" "shared_services" {
  count  = var.enable_nacl_rules ? 1 : 0
  vpc_id = aws_vpc.shared_services.id

  tags = merge(local.common_tags, {
    Name = "Shared-Services-NACL-${local.project_id}"
  })
}

# NACL Rules for HTTPS traffic
resource "aws_network_acl_rule" "https_inbound" {
  count = var.enable_nacl_rules ? 1 : 0

  network_acl_id = aws_network_acl.shared_services[0].id
  rule_number    = 100
  protocol       = "tcp"
  rule_action    = "allow"
  from_port      = 443
  to_port        = 443
  cidr_block     = var.on_premises_cidr
}

# NACL Rules for SSH traffic
resource "aws_network_acl_rule" "ssh_inbound" {
  count = var.enable_nacl_rules ? 1 : 0

  network_acl_id = aws_network_acl.shared_services[0].id
  rule_number    = 200
  protocol       = "tcp"
  rule_action    = "allow"
  from_port      = 22
  to_port        = 22
  cidr_block     = var.on_premises_cidr
}

# NACL Rules for DNS traffic
resource "aws_network_acl_rule" "dns_udp_inbound" {
  count = var.enable_nacl_rules ? 1 : 0

  network_acl_id = aws_network_acl.shared_services[0].id
  rule_number    = 300
  protocol       = "udp"
  rule_action    = "allow"
  from_port      = 53
  to_port        = 53
  cidr_block     = var.on_premises_cidr
}

resource "aws_network_acl_rule" "dns_tcp_inbound" {
  count = var.enable_nacl_rules ? 1 : 0

  network_acl_id = aws_network_acl.shared_services[0].id
  rule_number    = 301
  protocol       = "tcp"
  rule_action    = "allow"
  from_port      = 53
  to_port        = 53
  cidr_block     = var.on_premises_cidr
}

# Outbound allow all (default behavior)
resource "aws_network_acl_rule" "outbound_all" {
  count = var.enable_nacl_rules ? 1 : 0

  network_acl_id = aws_network_acl.shared_services[0].id
  rule_number    = 100
  protocol       = "-1"
  rule_action    = "allow"
  from_port      = 0
  to_port        = 0
  cidr_block     = "0.0.0.0/0"
}

# ============================================================================
# VPC Flow Logs
# ============================================================================

# CloudWatch Log Group for VPC Flow Logs
resource "aws_cloudwatch_log_group" "vpc_flow_logs" {
  count = var.enable_flow_logs ? 1 : 0

  name              = "/aws/vpc/flowlogs-${local.project_id}"
  retention_in_days = var.flow_logs_retention_days

  tags = merge(local.common_tags, {
    Name = "VPC-Flow-Logs-${local.project_id}"
  })
}

# IAM Role for VPC Flow Logs
resource "aws_iam_role" "flow_logs_role" {
  count = var.enable_flow_logs ? 1 : 0

  name = "flowlogs-role-${local.project_id}"

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
    Name = "Flow-Logs-Role-${local.project_id}"
  })
}

# IAM Policy for VPC Flow Logs
resource "aws_iam_role_policy" "flow_logs_policy" {
  count = var.enable_flow_logs ? 1 : 0

  name = "flowlogs-policy-${local.project_id}"
  role = aws_iam_role.flow_logs_role[0].id

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
        Resource = "*"
      }
    ]
  })
}

# VPC Flow Logs
resource "aws_flow_log" "vpc_flow_logs" {
  count = var.enable_flow_logs ? 3 : 0

  iam_role_arn    = aws_iam_role.flow_logs_role[0].arn
  log_destination = aws_cloudwatch_log_group.vpc_flow_logs[0].arn
  traffic_type    = "ALL"
  vpc_id          = [aws_vpc.production.id, aws_vpc.development.id, aws_vpc.shared_services.id][count.index]

  tags = merge(local.common_tags, {
    Name = "VPC-Flow-Log-${count.index + 1}-${local.project_id}"
  })
}

# ============================================================================
# CloudWatch Monitoring and Alerting
# ============================================================================

# CloudWatch Dashboard for Direct Connect monitoring
resource "aws_cloudwatch_dashboard" "dx_monitoring" {
  count = var.enable_cloudwatch_monitoring ? 1 : 0

  dashboard_name = "DirectConnect-${local.project_id}"

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
            ["AWS/DX", "ConnectionState", "ConnectionId", var.dx_connection_id != "" ? var.dx_connection_id : "placeholder"],
            [".", "ConnectionBpsEgress", ".", "."],
            [".", "ConnectionBpsIngress", ".", "."],
            [".", "ConnectionPacketsInEgress", ".", "."],
            [".", "ConnectionPacketsInIngress", ".", "."]
          ]
          period = 300
          stat   = "Average"
          region = var.aws_region
          title  = "Direct Connect Connection Metrics"
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
            ["AWS/TransitGateway", "BytesIn", "TransitGateway", aws_ec2_transit_gateway.main.id],
            [".", "BytesOut", ".", "."],
            [".", "PacketsIn", ".", "."],
            [".", "PacketsOut", ".", "."]
          ]
          period = 300
          stat   = "Sum"
          region = var.aws_region
          title  = "Transit Gateway Metrics"
        }
      }
    ]
  })
}

# SNS Topic for alerts
resource "aws_sns_topic" "dx_alerts" {
  count = var.enable_cloudwatch_monitoring ? 1 : 0

  name = "dx-alerts-${local.project_id}"

  tags = merge(local.common_tags, {
    Name = "DX-Alerts-${local.project_id}"
  })
}

# CloudWatch Alarm for Direct Connect connection state
resource "aws_cloudwatch_metric_alarm" "dx_connection_down" {
  count = var.enable_cloudwatch_monitoring && var.dx_connection_id != "" ? 1 : 0

  alarm_name          = "DX-Connection-Down-${local.project_id}"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "ConnectionState"
  namespace           = "AWS/DX"
  period              = "300"
  statistic           = "Maximum"
  threshold           = "1"
  alarm_description   = "This metric monitors Direct Connect connection state"
  alarm_actions       = [aws_sns_topic.dx_alerts[0].arn]

  dimensions = {
    ConnectionId = var.dx_connection_id
  }

  tags = merge(local.common_tags, {
    Name = "DX-Connection-Down-${local.project_id}"
  })
}

# CloudWatch Alarm for Transit Gateway bytes
resource "aws_cloudwatch_metric_alarm" "tgw_high_bytes" {
  count = var.enable_cloudwatch_monitoring ? 1 : 0

  alarm_name          = "TGW-High-Bytes-${local.project_id}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "BytesIn"
  namespace           = "AWS/TransitGateway"
  period              = "300"
  statistic           = "Sum"
  threshold           = "1000000000" # 1GB
  alarm_description   = "This metric monitors Transit Gateway data transfer"
  alarm_actions       = [aws_sns_topic.dx_alerts[0].arn]

  dimensions = {
    TransitGateway = aws_ec2_transit_gateway.main.id
  }

  tags = merge(local.common_tags, {
    Name = "TGW-High-Bytes-${local.project_id}"
  })
}