# outputs.tf - Output values for the Kubernetes VPC Lattice integration

# ================================
# Infrastructure Identifiers
# ================================

output "resource_suffix" {
  description = "Random suffix used for resource naming"
  value       = local.resource_suffix
}

output "vpc_a_id" {
  description = "ID of VPC A (Kubernetes cluster A)"
  value       = aws_vpc.vpc_a.id
}

output "vpc_b_id" {
  description = "ID of VPC B (Kubernetes cluster B)"
  value       = aws_vpc.vpc_b.id
}

output "subnet_a_id" {
  description = "ID of subnet in VPC A"
  value       = aws_subnet.subnet_a.id
}

output "subnet_b_id" {
  description = "ID of subnet in VPC B"
  value       = aws_subnet.subnet_b.id
}

# ================================
# EC2 Instance Information
# ================================

output "k8s_cluster_a_instance_id" {
  description = "Instance ID of Kubernetes cluster A control plane"
  value       = aws_instance.k8s_cluster_a.id
}

output "k8s_cluster_b_instance_id" {
  description = "Instance ID of Kubernetes cluster B control plane"
  value       = aws_instance.k8s_cluster_b.id
}

output "k8s_cluster_a_public_ip" {
  description = "Public IP address of Kubernetes cluster A"
  value       = aws_instance.k8s_cluster_a.public_ip
}

output "k8s_cluster_b_public_ip" {
  description = "Public IP address of Kubernetes cluster B"
  value       = aws_instance.k8s_cluster_b.public_ip
}

output "k8s_cluster_a_private_ip" {
  description = "Private IP address of Kubernetes cluster A (simulating pod IP)"
  value       = aws_instance.k8s_cluster_a.private_ip
}

output "k8s_cluster_b_private_ip" {
  description = "Private IP address of Kubernetes cluster B (simulating pod IP)"
  value       = aws_instance.k8s_cluster_b.private_ip
}

# ================================
# SSH Access Information
# ================================

output "ssh_key_name" {
  description = "Name of the SSH key pair for EC2 access"
  value       = var.create_key_pair ? aws_key_pair.k8s_key[0].key_name : "N/A (existing key pair)"
}

output "ssh_private_key_pem" {
  description = "Private SSH key in PEM format (sensitive)"
  value       = var.create_key_pair ? tls_private_key.k8s_key[0].private_key_pem : "N/A (existing key pair)"
  sensitive   = true
}

output "ssh_connection_commands" {
  description = "SSH commands to connect to the Kubernetes clusters"
  value = var.create_key_pair ? {
    cluster_a = "ssh -i ${aws_key_pair.k8s_key[0].key_name}.pem ec2-user@${aws_instance.k8s_cluster_a.public_ip}"
    cluster_b = "ssh -i ${aws_key_pair.k8s_key[0].key_name}.pem ec2-user@${aws_instance.k8s_cluster_b.public_ip}"
  } : {
    cluster_a = "ssh -i <your-key>.pem ec2-user@${aws_instance.k8s_cluster_a.public_ip}"
    cluster_b = "ssh -i <your-key>.pem ec2-user@${aws_instance.k8s_cluster_b.public_ip}"
  }
}

# ================================
# VPC Lattice Service Network
# ================================

output "service_network_id" {
  description = "ID of the VPC Lattice service network"
  value       = aws_vpclattice_service_network.k8s_mesh.id
}

output "service_network_arn" {
  description = "ARN of the VPC Lattice service network"
  value       = aws_vpclattice_service_network.k8s_mesh.arn
}

output "service_network_domain" {
  description = "DNS domain name for the VPC Lattice service network"
  value       = aws_vpclattice_service_network.k8s_mesh.dns_entry[0].domain_name
}

# ================================
# VPC Lattice Services
# ================================

output "frontend_service_id" {
  description = "ID of the frontend VPC Lattice service"
  value       = aws_vpclattice_service.frontend.id
}

output "backend_service_id" {
  description = "ID of the backend VPC Lattice service"
  value       = aws_vpclattice_service.backend.id
}

output "frontend_service_arn" {
  description = "ARN of the frontend VPC Lattice service"
  value       = aws_vpclattice_service.frontend.arn
}

output "backend_service_arn" {
  description = "ARN of the backend VPC Lattice service"
  value       = aws_vpclattice_service.backend.arn
}

output "frontend_service_domain" {
  description = "DNS domain name for the frontend service"
  value       = aws_vpclattice_service.frontend.dns_entry[0].domain_name
}

output "backend_service_domain" {
  description = "DNS domain name for the backend service"
  value       = aws_vpclattice_service.backend.dns_entry[0].domain_name
}

# ================================
# VPC Lattice Target Groups
# ================================

output "frontend_target_group_id" {
  description = "ID of the frontend target group"
  value       = aws_vpclattice_target_group.frontend.id
}

output "backend_target_group_id" {
  description = "ID of the backend target group"
  value       = aws_vpclattice_target_group.backend.id
}

output "frontend_target_group_arn" {
  description = "ARN of the frontend target group"
  value       = aws_vpclattice_target_group.frontend.arn
}

output "backend_target_group_arn" {
  description = "ARN of the backend target group"
  value       = aws_vpclattice_target_group.backend.arn
}

# ================================
# Service Discovery Endpoints
# ================================

output "service_discovery_endpoints" {
  description = "Service discovery endpoints for cross-cluster communication"
  value = {
    frontend_service = "${aws_vpclattice_service.frontend.name}.${aws_vpclattice_service_network.k8s_mesh.dns_entry[0].domain_name}"
    backend_service  = "${aws_vpclattice_service.backend.name}.${aws_vpclattice_service_network.k8s_mesh.dns_entry[0].domain_name}"
  }
}

# ================================
# Security Groups
# ================================

output "cluster_a_security_group_id" {
  description = "Security group ID for Kubernetes cluster A"
  value       = aws_security_group.k8s_cluster_a.id
}

output "cluster_b_security_group_id" {
  description = "Security group ID for Kubernetes cluster B"
  value       = aws_security_group.k8s_cluster_b.id
}

# ================================
# Monitoring Resources
# ================================

output "cloudwatch_log_group_name" {
  description = "CloudWatch log group name for VPC Lattice access logs"
  value       = var.enable_monitoring ? aws_cloudwatch_log_group.vpc_lattice[0].name : "N/A (monitoring disabled)"
}

output "cloudwatch_dashboard_url" {
  description = "URL to the CloudWatch dashboard for service mesh monitoring"
  value = var.enable_monitoring ? "https://${var.aws_region}.console.aws.amazon.com/cloudwatch/home?region=${var.aws_region}#dashboards:name=${aws_cloudwatch_dashboard.vpc_lattice[0].dashboard_name}" : "N/A (monitoring disabled)"
}

# ================================
# Deployment Information
# ================================

output "deployment_summary" {
  description = "Summary of the deployed infrastructure"
  value = {
    vpcs_created                = 2
    ec2_instances_created      = 2
    service_network_created    = true
    services_created           = 2
    target_groups_created      = 2
    monitoring_enabled         = var.enable_monitoring
    ssh_key_created           = var.create_key_pair
    estimated_monthly_cost    = "$50-100 (varies by region and usage)"
  }
}

# ================================
# Validation Commands
# ================================

output "validation_commands" {
  description = "Commands to validate the deployment"
  value = {
    check_service_network = "aws vpc-lattice get-service-network --service-network-identifier ${aws_vpclattice_service_network.k8s_mesh.id}"
    check_vpc_associations = "aws vpc-lattice list-service-network-vpc-associations --service-network-identifier ${aws_vpclattice_service_network.k8s_mesh.id}"
    check_target_health = {
      frontend = "aws vpc-lattice list-targets --target-group-identifier ${aws_vpclattice_target_group.frontend.id}"
      backend  = "aws vpc-lattice list-targets --target-group-identifier ${aws_vpclattice_target_group.backend.id}"
    }
  }
}

# ================================
# Next Steps
# ================================

output "next_steps" {
  description = "Recommended next steps after deployment"
  value = [
    "1. SSH into EC2 instances to complete Kubernetes cluster setup",
    "2. Deploy sample applications that listen on ports 8080 (cluster A) and 9090 (cluster B)",
    "3. Test cross-VPC service discovery using the provided endpoints",
    "4. Monitor service mesh performance in CloudWatch dashboards",
    "5. Configure VPC Lattice auth policies for production security"
  ]
}