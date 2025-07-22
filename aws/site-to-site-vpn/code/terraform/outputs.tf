# Output values for the VPN Site-to-Site infrastructure

# VPC Information
output "vpc_id" {
  description = "ID of the VPC"
  value       = aws_vpc.main.id
}

output "vpc_cidr_block" {
  description = "CIDR block of the VPC"
  value       = aws_vpc.main.cidr_block
}

# Subnet Information
output "public_subnet_id" {
  description = "ID of the public subnet"
  value       = aws_subnet.public.id
}

output "private_subnet_id" {
  description = "ID of the private subnet"
  value       = aws_subnet.private.id
}

output "public_subnet_cidr" {
  description = "CIDR block of the public subnet"
  value       = aws_subnet.public.cidr_block
}

output "private_subnet_cidr" {
  description = "CIDR block of the private subnet"
  value       = aws_subnet.private.cidr_block
}

# VPN Gateway Information
output "vpn_gateway_id" {
  description = "ID of the VPN Gateway"
  value       = aws_vpn_gateway.main.id
}

output "vpn_gateway_asn" {
  description = "Amazon side ASN of the VPN Gateway"
  value       = aws_vpn_gateway.main.amazon_side_asn
}

# Customer Gateway Information
output "customer_gateway_id" {
  description = "ID of the Customer Gateway"
  value       = aws_customer_gateway.main.id
}

output "customer_gateway_ip" {
  description = "IP address of the Customer Gateway"
  value       = aws_customer_gateway.main.ip_address
}

output "customer_gateway_bgp_asn" {
  description = "BGP ASN of the Customer Gateway"
  value       = aws_customer_gateway.main.bgp_asn
}

# VPN Connection Information
output "vpn_connection_id" {
  description = "ID of the VPN Connection"
  value       = aws_vpn_connection.main.id
}

output "vpn_connection_type" {
  description = "Type of the VPN Connection"
  value       = aws_vpn_connection.main.type
}

output "vpn_connection_static_routes_only" {
  description = "Whether the VPN connection uses static routes only"
  value       = aws_vpn_connection.main.static_routes_only
}

# VPN Tunnel Information
output "tunnel1_address" {
  description = "Public IP address of the first VPN tunnel"
  value       = aws_vpn_connection.main.tunnel1_address
}

output "tunnel2_address" {
  description = "Public IP address of the second VPN tunnel"
  value       = aws_vpn_connection.main.tunnel2_address
}

output "tunnel1_cgw_inside_address" {
  description = "RFC 6890 link-local address of the first VPN tunnel (Customer Gateway side)"
  value       = aws_vpn_connection.main.tunnel1_cgw_inside_address
}

output "tunnel2_cgw_inside_address" {
  description = "RFC 6890 link-local address of the second VPN tunnel (Customer Gateway side)"
  value       = aws_vpn_connection.main.tunnel2_cgw_inside_address
}

output "tunnel1_vgw_inside_address" {
  description = "RFC 6890 link-local address of the first VPN tunnel (Virtual Private Gateway side)"
  value       = aws_vpn_connection.main.tunnel1_vgw_inside_address
}

output "tunnel2_vgw_inside_address" {
  description = "RFC 6890 link-local address of the second VPN tunnel (Virtual Private Gateway side)"
  value       = aws_vpn_connection.main.tunnel2_vgw_inside_address
}

output "tunnel1_preshared_key" {
  description = "Pre-shared key for the first VPN tunnel"
  value       = aws_vpn_connection.main.tunnel1_preshared_key
  sensitive   = true
}

output "tunnel2_preshared_key" {
  description = "Pre-shared key for the second VPN tunnel"
  value       = aws_vpn_connection.main.tunnel2_preshared_key
  sensitive   = true
}

# Customer Gateway Configuration
output "customer_gateway_configuration" {
  description = "Configuration information for the Customer Gateway"
  value       = aws_vpn_connection.main.customer_gateway_configuration
  sensitive   = true
}

# Security Group Information
output "security_group_id" {
  description = "ID of the VPN security group"
  value       = aws_security_group.vpn.id
}

output "security_group_arn" {
  description = "ARN of the VPN security group"
  value       = aws_security_group.vpn.arn
}

# Test Instance Information (conditional)
output "test_instance_id" {
  description = "ID of the test EC2 instance"
  value       = var.create_test_instance ? aws_instance.test[0].id : null
}

output "test_instance_private_ip" {
  description = "Private IP address of the test EC2 instance"
  value       = var.create_test_instance ? aws_instance.test[0].private_ip : null
}

output "test_instance_availability_zone" {
  description = "Availability zone of the test EC2 instance"
  value       = var.create_test_instance ? aws_instance.test[0].availability_zone : null
}

# Route Table Information
output "private_route_table_id" {
  description = "ID of the private route table"
  value       = aws_route_table.private.id
}

output "public_route_table_id" {
  description = "ID of the public route table"
  value       = aws_route_table.public.id
}

# CloudWatch Dashboard Information (conditional)
output "cloudwatch_dashboard_url" {
  description = "URL to the CloudWatch dashboard"
  value = var.create_cloudwatch_dashboard ? "https://${data.aws_region.current.name}.console.aws.amazon.com/cloudwatch/home?region=${data.aws_region.current.name}#dashboards:name=${aws_cloudwatch_dashboard.vpn[0].dashboard_name}" : null
}

output "cloudwatch_dashboard_name" {
  description = "Name of the CloudWatch dashboard"
  value       = var.create_cloudwatch_dashboard ? aws_cloudwatch_dashboard.vpn[0].dashboard_name : null
}

# CloudWatch Log Group Information (conditional)
output "cloudwatch_log_group_name" {
  description = "Name of the CloudWatch log group for VPN logs"
  value       = var.enable_vpn_logs ? aws_cloudwatch_log_group.vpn[0].name : null
}

output "cloudwatch_log_group_arn" {
  description = "ARN of the CloudWatch log group for VPN logs"
  value       = var.enable_vpn_logs ? aws_cloudwatch_log_group.vpn[0].arn : null
}

# Connection Status Commands
output "vpn_connection_status_command" {
  description = "AWS CLI command to check VPN connection status"
  value       = "aws ec2 describe-vpn-connections --vpn-connection-ids ${aws_vpn_connection.main.id} --query 'VpnConnections[0].State' --output text"
}

output "vpn_tunnel_status_command" {
  description = "AWS CLI command to check VPN tunnel status"
  value       = "aws ec2 describe-vpn-connections --vpn-connection-ids ${aws_vpn_connection.main.id} --query 'VpnConnections[0].VgwTelemetry[*].{IP:OutsideIpAddress,Status:Status,Routes:AcceptedRouteCount}' --output table"
}

output "route_table_check_command" {
  description = "AWS CLI command to check propagated routes"
  value       = "aws ec2 describe-route-tables --route-table-ids ${aws_route_table.private.id} --query 'RouteTables[0].Routes[*].{Destination:DestinationCidrBlock,Gateway:GatewayId,State:State}' --output table"
}

# Configuration File Information
output "configuration_file_instructions" {
  description = "Instructions for downloading and using the VPN configuration"
  value = <<-EOT
    To download the VPN configuration for your Customer Gateway:
    
    1. Save configuration to file:
       aws ec2 describe-vpn-connections --vpn-connection-ids ${aws_vpn_connection.main.id} --query 'VpnConnections[0].CustomerGatewayConfiguration' --output text > vpn-config.txt
    
    2. Review tunnel details:
       aws ec2 describe-vpn-connections --vpn-connection-ids ${aws_vpn_connection.main.id} --query 'VpnConnections[0].VgwTelemetry' --output table
    
    3. Configure your on-premises VPN device using the downloaded configuration
    
    4. Test connectivity to the test instance: ${var.create_test_instance ? aws_instance.test[0].private_ip : "N/A (test instance not created)"}
  EOT
}

# Resource Summary
output "resource_summary" {
  description = "Summary of created resources"
  value = {
    vpc_id              = aws_vpc.main.id
    vpn_connection_id   = aws_vpn_connection.main.id
    customer_gateway_id = aws_customer_gateway.main.id
    vpn_gateway_id      = aws_vpn_gateway.main.id
    security_group_id   = aws_security_group.vpn.id
    test_instance_id    = var.create_test_instance ? aws_instance.test[0].id : null
    dashboard_created   = var.create_cloudwatch_dashboard
    logs_enabled        = var.enable_vpn_logs
    project_name        = var.project_name
    environment         = var.environment
    aws_region          = data.aws_region.current.name
  }
}