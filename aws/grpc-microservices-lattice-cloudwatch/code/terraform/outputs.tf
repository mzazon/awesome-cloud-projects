# Outputs for gRPC microservices with VPC Lattice and CloudWatch

# Network and VPC information
output "vpc_id" {
  description = "ID of the VPC created for gRPC microservices"
  value       = aws_vpc.grpc_vpc.id
}

output "vpc_cidr" {
  description = "CIDR block of the VPC"
  value       = aws_vpc.grpc_vpc.cidr_block
}

output "subnet_id" {
  description = "ID of the subnet where EC2 instances are deployed"
  value       = aws_subnet.grpc_subnet.id
}

output "security_group_id" {
  description = "ID of the security group for gRPC services"
  value       = aws_security_group.grpc_services_sg.id
}

# VPC Lattice Service Network information
output "service_network_id" {
  description = "ID of the VPC Lattice service network"
  value       = aws_vpclattice_service_network.grpc_service_network.id
}

output "service_network_arn" {
  description = "ARN of the VPC Lattice service network"
  value       = aws_vpclattice_service_network.grpc_service_network.arn
}

output "service_network_name" {
  description = "Name of the VPC Lattice service network"
  value       = aws_vpclattice_service_network.grpc_service_network.name
}

# VPC Lattice Services information
output "grpc_services" {
  description = "Information about all gRPC services"
  value = {
    for service_key, service in var.microservices : service_key => {
      service_id   = aws_vpclattice_service.grpc_services[service_key].id
      service_arn  = aws_vpclattice_service.grpc_services[service_key].arn
      service_name = aws_vpclattice_service.grpc_services[service_key].name
      dns_name     = aws_vpclattice_service.grpc_services[service_key].dns_entry[0].domain_name
      hosted_zone_id = aws_vpclattice_service.grpc_services[service_key].dns_entry[0].hosted_zone_id
      port         = service.port
      health_port  = service.health_port
    }
  }
}

# Service endpoints for easy access
output "service_endpoints" {
  description = "gRPC service endpoints for client connections"
  value = {
    for service_key, service in var.microservices : service_key => {
      https_endpoint = "https://${aws_vpclattice_service.grpc_services[service_key].dns_entry[0].domain_name}"
      service_name   = service.name
      port          = service.port
    }
  }
}

# Target Groups information
output "target_groups" {
  description = "Information about VPC Lattice target groups"
  value = {
    for service_key, service in var.microservices : service_key => {
      target_group_id   = aws_vpclattice_target_group.grpc_target_groups[service_key].id
      target_group_arn  = aws_vpclattice_target_group.grpc_target_groups[service_key].arn
      target_group_name = aws_vpclattice_target_group.grpc_target_groups[service_key].name
      port             = service.port
      protocol         = "HTTP2"
    }
  }
}

# EC2 instances information
output "ec2_instances" {
  description = "Information about EC2 instances hosting gRPC services"
  value = {
    for service_key, service in var.microservices : service_key => {
      instance_id      = aws_instance.grpc_instances[service_key].id
      instance_type    = aws_instance.grpc_instances[service_key].instance_type
      private_ip       = aws_instance.grpc_instances[service_key].private_ip
      public_ip        = aws_instance.grpc_instances[service_key].public_ip
      availability_zone = aws_instance.grpc_instances[service_key].availability_zone
      service_name     = service.name
      service_port     = service.port
      health_endpoint  = "http://${aws_instance.grpc_instances[service_key].private_ip}:${service.health_port}/health"
    }
  }
}

# CloudWatch monitoring information
output "cloudwatch_dashboard_url" {
  description = "URL to the CloudWatch dashboard (if created)"
  value = var.create_dashboard ? "https://console.aws.amazon.com/cloudwatch/home?region=${data.aws_region.current.name}#dashboards:name=${aws_cloudwatch_dashboard.grpc_dashboard[0].dashboard_name}" : null
}

output "cloudwatch_log_group" {
  description = "CloudWatch log group for VPC Lattice access logs"
  value = var.enable_access_logs ? {
    name = aws_cloudwatch_log_group.vpc_lattice_logs[0].name
    arn  = aws_cloudwatch_log_group.vpc_lattice_logs[0].arn
  } : null
}

output "cloudwatch_alarms" {
  description = "CloudWatch alarms created for monitoring (if enabled)"
  value = var.enable_monitoring ? {
    high_error_rate = {
      for service_key, service in var.microservices : service_key => {
        alarm_name = aws_cloudwatch_metric_alarm.high_error_rate[service_key].alarm_name
        alarm_arn  = aws_cloudwatch_metric_alarm.high_error_rate[service_key].arn
      }
    }
    high_latency = {
      for service_key, service in var.microservices : service_key => {
        alarm_name = aws_cloudwatch_metric_alarm.high_latency[service_key].alarm_name
        alarm_arn  = aws_cloudwatch_metric_alarm.high_latency[service_key].arn
      }
    }
    connection_failures = {
      for service_key, service in var.microservices : service_key => {
        alarm_name = aws_cloudwatch_metric_alarm.connection_failures[service_key].alarm_name
        alarm_arn  = aws_cloudwatch_metric_alarm.connection_failures[service_key].arn
      }
    }
  } : null
}

# Useful connection information
output "connection_info" {
  description = "Connection information for testing and integration"
  value = {
    region                = data.aws_region.current.name
    account_id           = data.aws_caller_identity.current.account_id
    service_network_name = aws_vpclattice_service_network.grpc_service_network.name
    random_suffix        = random_string.suffix.result
    
    # Health check URLs for testing
    health_check_urls = {
      for service_key, service in var.microservices : service_key => 
      "http://${aws_instance.grpc_instances[service_key].public_ip}:${service.health_port}/health"
    }
    
    # Service discovery information
    service_discovery = {
      for service_key, service in var.microservices : service_key => {
        service_name = "${service.name}-${random_string.suffix.result}"
        dns_name     = aws_vpclattice_service.grpc_services[service_key].dns_entry[0].domain_name
        grpc_port    = service.port
      }
    }
  }
}

# Resource tagging information
output "resource_tags" {
  description = "Common tags applied to all resources"
  value = {
    Project     = "gRPC-Microservices"
    Environment = var.environment
    ManagedBy   = "Terraform"
    Recipe      = "grpc-microservices-lattice-cloudwatch"
    Suffix      = random_string.suffix.result
  }
}

# Cost optimization information
output "cost_optimization_info" {
  description = "Information for cost optimization"
  value = {
    instance_count = length(var.microservices)
    instance_type  = var.instance_type
    
    # Estimated monthly costs (rough estimates)
    estimated_monthly_cost = {
      ec2_instances = "~$${length(var.microservices) * 8} (${length(var.microservices)} x t3.micro instances)"
      vpc_lattice   = "~$5-10 (service network + request processing)"
      cloudwatch    = "~$2-5 (logs + metrics + alarms)"
      total_estimate = "~$${length(var.microservices) * 8 + 10} per month"
    }
    
    cost_optimization_tips = [
      "Use Spot instances for non-production environments",
      "Consider using AWS Graviton instances for better price-performance",
      "Monitor CloudWatch logs retention and adjust as needed",
      "Use AWS Cost Explorer to track actual costs",
      "Consider using Reserved Instances for production workloads"
    ]
  }
}