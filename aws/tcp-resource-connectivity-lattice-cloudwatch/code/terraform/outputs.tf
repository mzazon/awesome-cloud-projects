# =========================================================================
# Outputs for TCP Resource Connectivity with VPC Lattice and CloudWatch
# =========================================================================

# ---------------------------------------------------------------------------
# VPC Lattice Service Network Outputs
# ---------------------------------------------------------------------------

output "service_network_id" {
  description = "ID of the VPC Lattice service network"
  value       = aws_vpclattice_service_network.database_service_network.id
}

output "service_network_arn" {
  description = "ARN of the VPC Lattice service network"
  value       = aws_vpclattice_service_network.database_service_network.arn
}

output "service_network_name" {
  description = "Name of the VPC Lattice service network"
  value       = aws_vpclattice_service_network.database_service_network.name
}

# ---------------------------------------------------------------------------
# VPC Lattice Service Outputs
# ---------------------------------------------------------------------------

output "database_service_id" {
  description = "ID of the VPC Lattice database service"
  value       = aws_vpclattice_service.database_service.id
}

output "database_service_arn" {
  description = "ARN of the VPC Lattice database service"
  value       = aws_vpclattice_service.database_service.arn
}

output "database_service_name" {
  description = "Name of the VPC Lattice database service"
  value       = aws_vpclattice_service.database_service.name
}

output "database_service_dns_name" {
  description = "DNS name of the VPC Lattice database service"
  value       = aws_vpclattice_service.database_service.dns_entry[0].domain_name
}

output "database_service_endpoint" {
  description = "Complete endpoint for connecting to the database through VPC Lattice"
  value       = "${aws_vpclattice_service.database_service.name}.${aws_vpclattice_service_network.database_service_network.id}.vpc-lattice-svcs.${data.aws_region.current.name}.on.aws"
}

# ---------------------------------------------------------------------------
# Target Group Outputs
# ---------------------------------------------------------------------------

output "target_group_id" {
  description = "ID of the VPC Lattice target group"
  value       = aws_vpclattice_target_group.rds_tcp_targets.id
}

output "target_group_arn" {
  description = "ARN of the VPC Lattice target group"
  value       = aws_vpclattice_target_group.rds_tcp_targets.arn
}

output "target_group_name" {
  description = "Name of the VPC Lattice target group"
  value       = aws_vpclattice_target_group.rds_tcp_targets.name
}

# ---------------------------------------------------------------------------
# TCP Listener Outputs
# ---------------------------------------------------------------------------

output "tcp_listener_id" {
  description = "ID of the TCP listener"
  value       = aws_vpclattice_listener.mysql_tcp_listener.listener_id
}

output "tcp_listener_arn" {
  description = "ARN of the TCP listener"
  value       = aws_vpclattice_listener.mysql_tcp_listener.arn
}

output "tcp_listener_port" {
  description = "Port number of the TCP listener"
  value       = aws_vpclattice_listener.mysql_tcp_listener.port
}

# ---------------------------------------------------------------------------
# RDS Database Outputs
# ---------------------------------------------------------------------------

output "rds_instance_id" {
  description = "ID of the RDS database instance"
  value       = aws_db_instance.mysql_instance.id
}

output "rds_instance_arn" {
  description = "ARN of the RDS database instance"
  value       = aws_db_instance.mysql_instance.arn
}

output "rds_endpoint" {
  description = "Connection endpoint for the RDS database instance"
  value       = aws_db_instance.mysql_instance.endpoint
}

output "rds_address" {
  description = "Address of the RDS database instance"
  value       = aws_db_instance.mysql_instance.address
}

output "rds_port" {
  description = "Port number of the RDS database instance"
  value       = aws_db_instance.mysql_instance.port
}

output "rds_engine_version" {
  description = "Engine version of the RDS database instance"
  value       = aws_db_instance.mysql_instance.engine_version
}

output "rds_instance_class" {
  description = "Instance class of the RDS database instance"
  value       = aws_db_instance.mysql_instance.instance_class
}

# ---------------------------------------------------------------------------
# Network Configuration Outputs
# ---------------------------------------------------------------------------

output "vpc_id" {
  description = "ID of the VPC used for deployment"
  value       = data.aws_vpc.default.id
}

output "subnet_ids" {
  description = "List of subnet IDs used for RDS deployment"
  value       = data.aws_subnets.default.ids
}

output "security_group_id" {
  description = "ID of the security group used"
  value       = data.aws_security_group.default.id
}

output "vpc_association_id" {
  description = "ID of the VPC Lattice service network VPC association"
  value       = aws_vpclattice_service_network_vpc_association.vpc_association.id
}

# ---------------------------------------------------------------------------
# CloudWatch Monitoring Outputs
# ---------------------------------------------------------------------------

output "cloudwatch_dashboard_name" {
  description = "Name of the CloudWatch dashboard"
  value       = aws_cloudwatch_dashboard.vpc_lattice_dashboard.dashboard_name
}

output "cloudwatch_dashboard_url" {
  description = "URL to access the CloudWatch dashboard"
  value       = "https://${data.aws_region.current.name}.console.aws.amazon.com/cloudwatch/home?region=${data.aws_region.current.name}#dashboards:name=${aws_cloudwatch_dashboard.vpc_lattice_dashboard.dashboard_name}"
}

output "connection_errors_alarm_name" {
  description = "Name of the connection errors CloudWatch alarm"
  value       = aws_cloudwatch_metric_alarm.database_connection_errors.alarm_name
}

output "high_connections_alarm_name" {
  description = "Name of the high connections CloudWatch alarm"
  value       = aws_cloudwatch_metric_alarm.database_high_connections.alarm_name
}

# ---------------------------------------------------------------------------
# IAM Outputs
# ---------------------------------------------------------------------------

output "vpc_lattice_service_role_arn" {
  description = "ARN of the VPC Lattice service IAM role"
  value       = aws_iam_role.vpc_lattice_service_role.arn
}

output "vpc_lattice_service_role_name" {
  description = "Name of the VPC Lattice service IAM role"
  value       = aws_iam_role.vpc_lattice_service_role.name
}

# ---------------------------------------------------------------------------
# Connection Information Outputs
# ---------------------------------------------------------------------------

output "database_connection_info" {
  description = "Database connection information through VPC Lattice"
  value = {
    vpc_lattice_endpoint = "${aws_vpclattice_service.database_service.name}.${aws_vpclattice_service_network.database_service_network.id}.vpc-lattice-svcs.${data.aws_region.current.name}.on.aws"
    port                 = var.mysql_port
    username             = var.db_username
    database_name        = aws_db_instance.mysql_instance.db_name
    engine               = "mysql"
    engine_version       = var.mysql_engine_version
  }
  sensitive = false
}

output "monitoring_endpoints" {
  description = "Monitoring and observability endpoints"
  value = {
    cloudwatch_dashboard = "https://${data.aws_region.current.name}.console.aws.amazon.com/cloudwatch/home?region=${data.aws_region.current.name}#dashboards:name=${aws_cloudwatch_dashboard.vpc_lattice_dashboard.dashboard_name}"
    vpc_lattice_console  = "https://${data.aws_region.current.name}.console.aws.amazon.com/vpc/home?region=${data.aws_region.current.name}#ServiceNetworks:"
    rds_console         = "https://${data.aws_region.current.name}.console.aws.amazon.com/rds/home?region=${data.aws_region.current.name}#database:id=${aws_db_instance.mysql_instance.id}"
  }
}

# ---------------------------------------------------------------------------
# Cost Information Outputs
# ---------------------------------------------------------------------------

output "estimated_monthly_cost" {
  description = "Estimated monthly cost breakdown for deployed resources"
  value = {
    rds_instance     = "~$15-25 USD (db.t3.micro, 20GB storage)"
    vpc_lattice      = "~$10-15 USD (service network + data processing)"
    cloudwatch       = "~$1-3 USD (dashboards + alarms)"
    total_estimated  = "~$26-43 USD per month"
    note            = "Costs vary by region and actual usage. Review AWS pricing for current rates."
  }
}

# ---------------------------------------------------------------------------
# Validation and Testing Outputs
# ---------------------------------------------------------------------------

output "validation_commands" {
  description = "Commands to validate the deployment"
  value = {
    check_service_network = "aws vpc-lattice get-service-network --service-network-identifier ${aws_vpclattice_service_network.database_service_network.id}"
    check_target_health   = "aws vpc-lattice list-targets --target-group-identifier ${aws_vpclattice_target_group.rds_tcp_targets.id}"
    check_rds_status     = "aws rds describe-db-instances --db-instance-identifier ${aws_db_instance.mysql_instance.id}"
    test_connectivity    = "telnet ${aws_vpclattice_service.database_service.name}.${aws_vpclattice_service_network.database_service_network.id}.vpc-lattice-svcs.${data.aws_region.current.name}.on.aws ${var.mysql_port}"
  }
}

output "cleanup_commands" {
  description = "Commands to clean up resources (use with caution)"
  value = {
    note = "These resources will be destroyed when running 'terraform destroy'"
    terraform_destroy = "terraform destroy -auto-approve"
    manual_cleanup   = "Use AWS Console or CLI to remove individual resources if needed"
  }
}