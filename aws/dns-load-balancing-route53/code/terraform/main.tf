# Generate random suffix for unique resource naming
resource "random_id" "suffix" {
  byte_length = 3
}

locals {
  random_suffix = random_id.suffix.hex
  full_domain   = "${var.subdomain}.${var.domain_name}"
  
  # Common tags for all resources
  common_tags = merge(var.additional_tags, {
    Environment = var.environment
    Project     = "dns-load-balancing"
    Recipe      = "route53-multi-region-lb"
    RandomId    = local.random_suffix
  })
}

# Data sources for availability zones
data "aws_availability_zones" "primary" {
  state = "available"
}

data "aws_availability_zones" "secondary" {
  provider = aws.secondary
  state    = "available"
}

data "aws_availability_zones" "tertiary" {
  provider = aws.tertiary
  state    = "available"
}

# ===================================================================
# Route 53 Hosted Zone
# ===================================================================

resource "aws_route53_zone" "main" {
  name = var.domain_name
  
  tags = merge(local.common_tags, {
    Name = "dns-lb-zone-${local.random_suffix}"
  })
}

# ===================================================================
# SNS Topic for Health Check Notifications
# ===================================================================

resource "aws_sns_topic" "health_check_alerts" {
  count = var.enable_health_check_notifications ? 1 : 0
  
  name = "route53-health-alerts-${local.random_suffix}"
  
  tags = merge(local.common_tags, {
    Name = "health-alerts-${local.random_suffix}"
  })
}

resource "aws_sns_topic_subscription" "email_notification" {
  count = var.enable_health_check_notifications && var.notification_email != "" ? 1 : 0
  
  topic_arn = aws_sns_topic.health_check_alerts[0].arn
  protocol  = "email"
  endpoint  = var.notification_email
}

# ===================================================================
# PRIMARY REGION INFRASTRUCTURE
# ===================================================================

# VPC for Primary Region
module "primary_vpc" {
  source = "terraform-aws-modules/vpc/aws"
  version = "~> 5.0"
  
  name = "dns-lb-primary-vpc-${local.random_suffix}"
  cidr = var.vpc_cidr
  
  azs             = slice(data.aws_availability_zones.primary.names, 0, 2)
  public_subnets  = var.public_subnet_cidrs
  
  enable_internet_gateway = true
  enable_dns_hostnames    = true
  enable_dns_support      = true
  
  public_subnet_tags = {
    Name = "dns-lb-primary-public"
    Type = "Public"
  }
  
  tags = merge(local.common_tags, {
    Name   = "dns-lb-primary-vpc-${local.random_suffix}"
    Region = var.primary_region
  })
}

# Security Group for Primary ALB
resource "aws_security_group" "primary_alb" {
  name_prefix = "dns-lb-primary-alb-${local.random_suffix}"
  vpc_id      = module.primary_vpc.vpc_id
  description = "Security group for Primary region ALB"
  
  ingress {
    description = "HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  
  ingress {
    description = "HTTPS"
    from_port   = 443
    to_port     = 443
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
    Name   = "dns-lb-primary-alb-sg-${local.random_suffix}"
    Region = var.primary_region
  })
}

# Application Load Balancer for Primary Region
resource "aws_lb" "primary" {
  name               = "dns-lb-primary-${local.random_suffix}"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.primary_alb.id]
  subnets            = module.primary_vpc.public_subnets
  
  enable_deletion_protection = var.enable_deletion_protection
  idle_timeout              = var.alb_idle_timeout
  
  tags = merge(local.common_tags, {
    Name   = "dns-lb-primary-alb-${local.random_suffix}"
    Region = var.primary_region
  })
}

# Target Group for Primary Region
resource "aws_lb_target_group" "primary" {
  name     = "dns-lb-primary-tg-${local.random_suffix}"
  port     = 80
  protocol = "HTTP"
  vpc_id   = module.primary_vpc.vpc_id
  
  health_check {
    enabled             = true
    healthy_threshold   = 2
    unhealthy_threshold = var.failure_threshold
    timeout             = var.health_check_timeout
    interval            = 30
    path                = var.health_check_path
    matcher             = "200"
    port                = "traffic-port"
    protocol            = "HTTP"
  }
  
  tags = merge(local.common_tags, {
    Name   = "dns-lb-primary-tg-${local.random_suffix}"
    Region = var.primary_region
  })
}

# Listener for Primary ALB
resource "aws_lb_listener" "primary" {
  load_balancer_arn = aws_lb.primary.arn
  port              = "80"
  protocol          = "HTTP"
  
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.primary.arn
  }
  
  tags = merge(local.common_tags, {
    Name   = "dns-lb-primary-listener-${local.random_suffix}"
    Region = var.primary_region
  })
}

# ===================================================================
# SECONDARY REGION INFRASTRUCTURE
# ===================================================================

# VPC for Secondary Region
module "secondary_vpc" {
  source = "terraform-aws-modules/vpc/aws"
  version = "~> 5.0"
  
  providers = {
    aws = aws.secondary
  }
  
  name = "dns-lb-secondary-vpc-${local.random_suffix}"
  cidr = var.vpc_cidr
  
  azs             = slice(data.aws_availability_zones.secondary.names, 0, 2)
  public_subnets  = var.public_subnet_cidrs
  
  enable_internet_gateway = true
  enable_dns_hostnames    = true
  enable_dns_support      = true
  
  public_subnet_tags = {
    Name = "dns-lb-secondary-public"
    Type = "Public"
  }
  
  tags = merge(local.common_tags, {
    Name   = "dns-lb-secondary-vpc-${local.random_suffix}"
    Region = var.secondary_region
  })
}

# Security Group for Secondary ALB
resource "aws_security_group" "secondary_alb" {
  provider = aws.secondary
  
  name_prefix = "dns-lb-secondary-alb-${local.random_suffix}"
  vpc_id      = module.secondary_vpc.vpc_id
  description = "Security group for Secondary region ALB"
  
  ingress {
    description = "HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  
  ingress {
    description = "HTTPS"
    from_port   = 443
    to_port     = 443
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
    Name   = "dns-lb-secondary-alb-sg-${local.random_suffix}"
    Region = var.secondary_region
  })
}

# Application Load Balancer for Secondary Region
resource "aws_lb" "secondary" {
  provider = aws.secondary
  
  name               = "dns-lb-secondary-${local.random_suffix}"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.secondary_alb.id]
  subnets            = module.secondary_vpc.public_subnets
  
  enable_deletion_protection = var.enable_deletion_protection
  idle_timeout              = var.alb_idle_timeout
  
  tags = merge(local.common_tags, {
    Name   = "dns-lb-secondary-alb-${local.random_suffix}"
    Region = var.secondary_region
  })
}

# Target Group for Secondary Region
resource "aws_lb_target_group" "secondary" {
  provider = aws.secondary
  
  name     = "dns-lb-secondary-tg-${local.random_suffix}"
  port     = 80
  protocol = "HTTP"
  vpc_id   = module.secondary_vpc.vpc_id
  
  health_check {
    enabled             = true
    healthy_threshold   = 2
    unhealthy_threshold = var.failure_threshold
    timeout             = var.health_check_timeout
    interval            = 30
    path                = var.health_check_path
    matcher             = "200"
    port                = "traffic-port"
    protocol            = "HTTP"
  }
  
  tags = merge(local.common_tags, {
    Name   = "dns-lb-secondary-tg-${local.random_suffix}"
    Region = var.secondary_region
  })
}

# Listener for Secondary ALB
resource "aws_lb_listener" "secondary" {
  provider = aws.secondary
  
  load_balancer_arn = aws_lb.secondary.arn
  port              = "80"
  protocol          = "HTTP"
  
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.secondary.arn
  }
  
  tags = merge(local.common_tags, {
    Name   = "dns-lb-secondary-listener-${local.random_suffix}"
    Region = var.secondary_region
  })
}

# ===================================================================
# TERTIARY REGION INFRASTRUCTURE
# ===================================================================

# VPC for Tertiary Region
module "tertiary_vpc" {
  source = "terraform-aws-modules/vpc/aws"
  version = "~> 5.0"
  
  providers = {
    aws = aws.tertiary
  }
  
  name = "dns-lb-tertiary-vpc-${local.random_suffix}"
  cidr = var.vpc_cidr
  
  azs             = slice(data.aws_availability_zones.tertiary.names, 0, 2)
  public_subnets  = var.public_subnet_cidrs
  
  enable_internet_gateway = true
  enable_dns_hostnames    = true
  enable_dns_support      = true
  
  public_subnet_tags = {
    Name = "dns-lb-tertiary-public"
    Type = "Public"
  }
  
  tags = merge(local.common_tags, {
    Name   = "dns-lb-tertiary-vpc-${local.random_suffix}"
    Region = var.tertiary_region
  })
}

# Security Group for Tertiary ALB
resource "aws_security_group" "tertiary_alb" {
  provider = aws.tertiary
  
  name_prefix = "dns-lb-tertiary-alb-${local.random_suffix}"
  vpc_id      = module.tertiary_vpc.vpc_id
  description = "Security group for Tertiary region ALB"
  
  ingress {
    description = "HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  
  ingress {
    description = "HTTPS"
    from_port   = 443
    to_port     = 443
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
    Name   = "dns-lb-tertiary-alb-sg-${local.random_suffix}"
    Region = var.tertiary_region
  })
}

# Application Load Balancer for Tertiary Region
resource "aws_lb" "tertiary" {
  provider = aws.tertiary
  
  name               = "dns-lb-tertiary-${local.random_suffix}"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.tertiary_alb.id]
  subnets            = module.tertiary_vpc.public_subnets
  
  enable_deletion_protection = var.enable_deletion_protection
  idle_timeout              = var.alb_idle_timeout
  
  tags = merge(local.common_tags, {
    Name   = "dns-lb-tertiary-alb-${local.random_suffix}"
    Region = var.tertiary_region
  })
}

# Target Group for Tertiary Region
resource "aws_lb_target_group" "tertiary" {
  provider = aws.tertiary
  
  name     = "dns-lb-tertiary-tg-${local.random_suffix}"
  port     = 80
  protocol = "HTTP"
  vpc_id   = module.tertiary_vpc.vpc_id
  
  health_check {
    enabled             = true
    healthy_threshold   = 2
    unhealthy_threshold = var.failure_threshold
    timeout             = var.health_check_timeout
    interval            = 30
    path                = var.health_check_path
    matcher             = "200"
    port                = "traffic-port"
    protocol            = "HTTP"
  }
  
  tags = merge(local.common_tags, {
    Name   = "dns-lb-tertiary-tg-${local.random_suffix}"
    Region = var.tertiary_region
  })
}

# Listener for Tertiary ALB
resource "aws_lb_listener" "tertiary" {
  provider = aws.tertiary
  
  load_balancer_arn = aws_lb.tertiary.arn
  port              = "80"
  protocol          = "HTTP"
  
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.tertiary.arn
  }
  
  tags = merge(local.common_tags, {
    Name   = "dns-lb-tertiary-listener-${local.random_suffix}"
    Region = var.tertiary_region
  })
}

# ===================================================================
# ROUTE 53 HEALTH CHECKS
# ===================================================================

# Health Check for Primary Region
resource "aws_route53_health_check" "primary" {
  fqdn                            = aws_lb.primary.dns_name
  port                           = 80
  type                           = "HTTP"
  resource_path                  = var.health_check_path
  failure_threshold              = var.failure_threshold
  request_interval               = var.health_check_interval
  
  tags = merge(local.common_tags, {
    Name   = "dns-lb-primary-hc-${local.random_suffix}"
    Region = var.primary_region
  })
}

# Health Check for Secondary Region
resource "aws_route53_health_check" "secondary" {
  fqdn                            = aws_lb.secondary.dns_name
  port                           = 80
  type                           = "HTTP"
  resource_path                  = var.health_check_path
  failure_threshold              = var.failure_threshold
  request_interval               = var.health_check_interval
  
  tags = merge(local.common_tags, {
    Name   = "dns-lb-secondary-hc-${local.random_suffix}"
    Region = var.secondary_region
  })
}

# Health Check for Tertiary Region
resource "aws_route53_health_check" "tertiary" {
  fqdn                            = aws_lb.tertiary.dns_name
  port                           = 80
  type                           = "HTTP"
  resource_path                  = var.health_check_path
  failure_threshold              = var.failure_threshold
  request_interval               = var.health_check_interval
  
  tags = merge(local.common_tags, {
    Name   = "dns-lb-tertiary-hc-${local.random_suffix}"
    Region = var.tertiary_region
  })
}

# ===================================================================
# ROUTE 53 DNS RECORDS - WEIGHTED ROUTING
# ===================================================================

# Weighted Routing - Primary Region
resource "aws_route53_record" "weighted_primary" {
  count = var.enable_routing_policies.weighted ? 1 : 0
  
  zone_id = aws_route53_zone.main.zone_id
  name    = local.full_domain
  type    = "A"
  
  set_identifier = "Primary-Weighted"
  weighted_routing_policy {
    weight = var.weighted_routing.primary
  }
  
  alias {
    name                   = aws_lb.primary.dns_name
    zone_id                = aws_lb.primary.zone_id
    evaluate_target_health = true
  }
  
  health_check_id = aws_route53_health_check.primary.id
}

# Weighted Routing - Secondary Region
resource "aws_route53_record" "weighted_secondary" {
  count = var.enable_routing_policies.weighted ? 1 : 0
  
  zone_id = aws_route53_zone.main.zone_id
  name    = local.full_domain
  type    = "A"
  
  set_identifier = "Secondary-Weighted"
  weighted_routing_policy {
    weight = var.weighted_routing.secondary
  }
  
  alias {
    name                   = aws_lb.secondary.dns_name
    zone_id                = aws_lb.secondary.zone_id
    evaluate_target_health = true
  }
  
  health_check_id = aws_route53_health_check.secondary.id
}

# Weighted Routing - Tertiary Region
resource "aws_route53_record" "weighted_tertiary" {
  count = var.enable_routing_policies.weighted ? 1 : 0
  
  zone_id = aws_route53_zone.main.zone_id
  name    = local.full_domain
  type    = "A"
  
  set_identifier = "Tertiary-Weighted"
  weighted_routing_policy {
    weight = var.weighted_routing.tertiary
  }
  
  alias {
    name                   = aws_lb.tertiary.dns_name
    zone_id                = aws_lb.tertiary.zone_id
    evaluate_target_health = true
  }
  
  health_check_id = aws_route53_health_check.tertiary.id
}

# ===================================================================
# ROUTE 53 DNS RECORDS - LATENCY-BASED ROUTING
# ===================================================================

# Latency-Based Routing - Primary Region
resource "aws_route53_record" "latency_primary" {
  count = var.enable_routing_policies.latency ? 1 : 0
  
  zone_id = aws_route53_zone.main.zone_id
  name    = "latency.${local.full_domain}"
  type    = "A"
  
  set_identifier = "Primary-Latency"
  latency_routing_policy {
    region = var.primary_region
  }
  
  alias {
    name                   = aws_lb.primary.dns_name
    zone_id                = aws_lb.primary.zone_id
    evaluate_target_health = true
  }
  
  health_check_id = aws_route53_health_check.primary.id
}

# Latency-Based Routing - Secondary Region
resource "aws_route53_record" "latency_secondary" {
  count = var.enable_routing_policies.latency ? 1 : 0
  
  zone_id = aws_route53_zone.main.zone_id
  name    = "latency.${local.full_domain}"
  type    = "A"
  
  set_identifier = "Secondary-Latency"
  latency_routing_policy {
    region = var.secondary_region
  }
  
  alias {
    name                   = aws_lb.secondary.dns_name
    zone_id                = aws_lb.secondary.zone_id
    evaluate_target_health = true
  }
  
  health_check_id = aws_route53_health_check.secondary.id
}

# Latency-Based Routing - Tertiary Region
resource "aws_route53_record" "latency_tertiary" {
  count = var.enable_routing_policies.latency ? 1 : 0
  
  zone_id = aws_route53_zone.main.zone_id
  name    = "latency.${local.full_domain}"
  type    = "A"
  
  set_identifier = "Tertiary-Latency"
  latency_routing_policy {
    region = var.tertiary_region
  }
  
  alias {
    name                   = aws_lb.tertiary.dns_name
    zone_id                = aws_lb.tertiary.zone_id
    evaluate_target_health = true
  }
  
  health_check_id = aws_route53_health_check.tertiary.id
}

# ===================================================================
# ROUTE 53 DNS RECORDS - GEOLOCATION ROUTING
# ===================================================================

# Geolocation Routing - North America to Primary Region
resource "aws_route53_record" "geo_north_america" {
  count = var.enable_routing_policies.geolocation ? 1 : 0
  
  zone_id = aws_route53_zone.main.zone_id
  name    = "geo.${local.full_domain}"
  type    = "A"
  
  set_identifier = "North-America-Geo"
  geolocation_routing_policy {
    continent = "NA"
  }
  
  alias {
    name                   = aws_lb.primary.dns_name
    zone_id                = aws_lb.primary.zone_id
    evaluate_target_health = true
  }
  
  health_check_id = aws_route53_health_check.primary.id
}

# Geolocation Routing - Europe to Secondary Region
resource "aws_route53_record" "geo_europe" {
  count = var.enable_routing_policies.geolocation ? 1 : 0
  
  zone_id = aws_route53_zone.main.zone_id
  name    = "geo.${local.full_domain}"
  type    = "A"
  
  set_identifier = "Europe-Geo"
  geolocation_routing_policy {
    continent = "EU"
  }
  
  alias {
    name                   = aws_lb.secondary.dns_name
    zone_id                = aws_lb.secondary.zone_id
    evaluate_target_health = true
  }
  
  health_check_id = aws_route53_health_check.secondary.id
}

# Geolocation Routing - Asia Pacific to Tertiary Region
resource "aws_route53_record" "geo_asia_pacific" {
  count = var.enable_routing_policies.geolocation ? 1 : 0
  
  zone_id = aws_route53_zone.main.zone_id
  name    = "geo.${local.full_domain}"
  type    = "A"
  
  set_identifier = "Asia-Pacific-Geo"
  geolocation_routing_policy {
    continent = "AS"
  }
  
  alias {
    name                   = aws_lb.tertiary.dns_name
    zone_id                = aws_lb.tertiary.zone_id
    evaluate_target_health = true
  }
  
  health_check_id = aws_route53_health_check.tertiary.id
}

# Geolocation Routing - Default (Fallback)
resource "aws_route53_record" "geo_default" {
  count = var.enable_routing_policies.geolocation ? 1 : 0
  
  zone_id = aws_route53_zone.main.zone_id
  name    = "geo.${local.full_domain}"
  type    = "A"
  
  set_identifier = "Default-Geo"
  geolocation_routing_policy {
    country = "*"
  }
  
  alias {
    name                   = aws_lb.primary.dns_name
    zone_id                = aws_lb.primary.zone_id
    evaluate_target_health = true
  }
  
  health_check_id = aws_route53_health_check.primary.id
}

# ===================================================================
# ROUTE 53 DNS RECORDS - FAILOVER ROUTING
# ===================================================================

# Failover Routing - Primary
resource "aws_route53_record" "failover_primary" {
  count = var.enable_routing_policies.failover ? 1 : 0
  
  zone_id = aws_route53_zone.main.zone_id
  name    = "failover.${local.full_domain}"
  type    = "A"
  
  set_identifier = "Primary-Failover"
  failover_routing_policy {
    type = "PRIMARY"
  }
  
  alias {
    name                   = aws_lb.primary.dns_name
    zone_id                = aws_lb.primary.zone_id
    evaluate_target_health = true
  }
  
  health_check_id = aws_route53_health_check.primary.id
}

# Failover Routing - Secondary
resource "aws_route53_record" "failover_secondary" {
  count = var.enable_routing_policies.failover ? 1 : 0
  
  zone_id = aws_route53_zone.main.zone_id
  name    = "failover.${local.full_domain}"
  type    = "A"
  
  set_identifier = "Secondary-Failover"
  failover_routing_policy {
    type = "SECONDARY"
  }
  
  alias {
    name                   = aws_lb.secondary.dns_name
    zone_id                = aws_lb.secondary.zone_id
    evaluate_target_health = true
  }
  
  health_check_id = aws_route53_health_check.secondary.id
}

# ===================================================================
# ROUTE 53 DNS RECORDS - MULTIVALUE ANSWER ROUTING
# ===================================================================

# Multivalue Answer Routing - Primary Region
resource "aws_route53_record" "multivalue_primary" {
  count = var.enable_routing_policies.multivalue ? 1 : 0
  
  zone_id = aws_route53_zone.main.zone_id
  name    = "multivalue.${local.full_domain}"
  type    = "A"
  
  set_identifier = "Primary-Multivalue"
  multivalue_answer_routing_policy = true
  
  alias {
    name                   = aws_lb.primary.dns_name
    zone_id                = aws_lb.primary.zone_id
    evaluate_target_health = true
  }
  
  health_check_id = aws_route53_health_check.primary.id
}

# Multivalue Answer Routing - Secondary Region
resource "aws_route53_record" "multivalue_secondary" {
  count = var.enable_routing_policies.multivalue ? 1 : 0
  
  zone_id = aws_route53_zone.main.zone_id
  name    = "multivalue.${local.full_domain}"
  type    = "A"
  
  set_identifier = "Secondary-Multivalue"
  multivalue_answer_routing_policy = true
  
  alias {
    name                   = aws_lb.secondary.dns_name
    zone_id                = aws_lb.secondary.zone_id
    evaluate_target_health = true
  }
  
  health_check_id = aws_route53_health_check.secondary.id
}

# Multivalue Answer Routing - Tertiary Region
resource "aws_route53_record" "multivalue_tertiary" {
  count = var.enable_routing_policies.multivalue ? 1 : 0
  
  zone_id = aws_route53_zone.main.zone_id
  name    = "multivalue.${local.full_domain}"
  type    = "A"
  
  set_identifier = "Tertiary-Multivalue"
  multivalue_answer_routing_policy = true
  
  alias {
    name                   = aws_lb.tertiary.dns_name
    zone_id                = aws_lb.tertiary.zone_id
    evaluate_target_health = true
  }
  
  health_check_id = aws_route53_health_check.tertiary.id
}