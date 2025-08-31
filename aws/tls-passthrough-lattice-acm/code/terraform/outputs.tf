# Outputs for VPC Lattice TLS Passthrough Infrastructure

output "vpc_id" {
  description = "ID of the VPC created for target instances"
  value       = aws_vpc.main.id
}

output "subnet_id" {
  description = "ID of the subnet containing target instances"
  value       = aws_subnet.targets.id
}

output "security_group_id" {
  description = "ID of the security group for target instances"
  value       = aws_security_group.targets.id
}

output "target_instance_ids" {
  description = "List of target EC2 instance IDs"
  value       = aws_instance.targets[*].id
}

output "target_instance_private_ips" {
  description = "List of private IP addresses for target instances"
  value       = aws_instance.targets[*].private_ip
}

output "target_instance_public_ips" {
  description = "List of public IP addresses for target instances"
  value       = aws_instance.targets[*].public_ip
}

output "certificate_arn" {
  description = "ARN of the ACM certificate (if created)"
  value       = var.create_certificate ? aws_acm_certificate.main[0].arn : var.certificate_arn
  sensitive   = false
}

output "certificate_status" {
  description = "Status of the ACM certificate (if created)"
  value       = var.create_certificate ? aws_acm_certificate.main[0].status : "External"
}

output "certificate_validation_records" {
  description = "DNS validation records for the ACM certificate (if created)"
  value = var.create_certificate ? {
    for dvo in aws_acm_certificate.main[0].domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
  } : {}
  sensitive = false
}

output "service_network_id" {
  description = "ID of the VPC Lattice service network"
  value       = aws_vpclattice_service_network.main.id
}

output "service_network_arn" {
  description = "ARN of the VPC Lattice service network"
  value       = aws_vpclattice_service_network.main.arn
}

output "target_group_id" {
  description = "ID of the VPC Lattice target group"
  value       = aws_vpclattice_target_group.main.id
}

output "target_group_arn" {
  description = "ARN of the VPC Lattice target group"
  value       = aws_vpclattice_target_group.main.arn
}

output "service_id" {
  description = "ID of the VPC Lattice service"
  value       = aws_vpclattice_service.main.id
}

output "service_arn" {
  description = "ARN of the VPC Lattice service"
  value       = aws_vpclattice_service.main.arn
}

output "service_dns_name" {
  description = "DNS name of the VPC Lattice service"
  value       = aws_vpclattice_service.main.dns_entry[0].domain_name
}

output "service_hosted_zone_id" {
  description = "Hosted zone ID of the VPC Lattice service DNS entry"
  value       = aws_vpclattice_service.main.dns_entry[0].hosted_zone_id
}

output "custom_domain_name" {
  description = "Custom domain name configured for the service"
  value       = var.custom_domain_name
}

output "listener_id" {
  description = "ID of the TLS passthrough listener"
  value       = aws_vpclattice_listener.main.id
}

output "listener_arn" {
  description = "ARN of the TLS passthrough listener"
  value       = aws_vpclattice_listener.main.arn
}

output "route53_zone_id" {
  description = "Route 53 hosted zone ID (if created or provided)"
  value       = local.hosted_zone_id
}

output "route53_name_servers" {
  description = "Name servers for the Route 53 hosted zone (if created)"
  value       = var.create_route53_zone ? aws_route53_zone.main[0].name_servers : []
}

output "test_commands" {
  description = "Commands to test the TLS passthrough setup"
  value = {
    curl_test = "curl -k -v https://${var.custom_domain_name}"
    openssl_test = "openssl s_client -connect ${var.custom_domain_name}:443 -servername ${var.custom_domain_name}"
    health_check = "aws vpc-lattice list-targets --target-group-identifier ${aws_vpclattice_target_group.main.id}"
  }
}

output "deployment_notes" {
  description = "Important notes for completing the deployment"
  value = var.create_certificate ? join("\n", [
    "IMPORTANT: Complete the following steps to finish deployment:",
    "1. Certificate Validation:",
    "   - Go to ACM console: https://console.aws.amazon.com/acm/",
    "   - Find certificate: ${aws_acm_certificate.main[0].arn}",
    "   - Create DNS validation records shown in 'certificate_validation_records' output",
    "   - Wait for certificate status to become 'ISSUED' (5-10 minutes)",
    "",
    "2. DNS Configuration:",
    local.hosted_zone_id != "" ? "   - DNS record created automatically" : "   - Create CNAME record: ${var.custom_domain_name} -> ${aws_vpclattice_service.main.dns_entry[0].domain_name}",
    "",
    "3. Testing:",
    "   - Wait 5-10 minutes after certificate validation",
    "   - Test with: curl -k -v https://${var.custom_domain_name}",
    "   - Check target health with provided health_check command",
    "",
    "4. Security:",
    "   - Target instances use self-signed certificates for demonstration",
    "   - In production, use properly signed certificates on targets",
    "   - Consider implementing proper certificate rotation"
  ]) : join("\n", [
    "IMPORTANT: Complete the following steps:",
    "1. Ensure certificate ARN is valid and issued: ${var.certificate_arn}",
    "2. Configure DNS to point ${var.custom_domain_name} to ${aws_vpclattice_service.main.dns_entry[0].domain_name}",
    "3. Test connectivity after DNS propagation",
    "4. Monitor target health and certificate expiration"
  ])
}

output "cleanup_commands" {
  description = "Commands to clean up resources"
  value = {
    terraform_destroy = "terraform destroy"
    manual_cleanup = [
      "# If Route 53 hosted zone was created externally:",
      "aws route53 delete-hosted-zone --id ${local.hosted_zone_id}",
      "# If certificate was created externally:",
      "aws acm delete-certificate --certificate-arn ${var.create_certificate ? aws_acm_certificate.main[0].arn : var.certificate_arn}"
    ]
  }
}

output "monitoring_resources" {
  description = "Resources to monitor for operational health"
  value = {
    target_instances = aws_instance.targets[*].id
    target_group = aws_vpclattice_target_group.main.id
    service = aws_vpclattice_service.main.id
    certificate = var.create_certificate ? aws_acm_certificate.main[0].arn : var.certificate_arn
    security_group = aws_security_group.targets.id
  }
}

output "cost_optimization_notes" {
  description = "Recommendations for cost optimization"
  value = join("\n", [
    "Cost Optimization Recommendations:",
    "1. Instance Types: Consider t4g instances for better price-performance",
    "2. Monitoring: Disable detailed monitoring if not needed",
    "3. Storage: Use gp3 volumes with appropriate IOPS/throughput settings",
    "4. Auto Scaling: Implement auto scaling groups for variable workloads",
    "5. Spot Instances: Consider spot instances for non-critical workloads",
    "6. Reserved Instances: Use Reserved Instances for predictable workloads"
  ])
}