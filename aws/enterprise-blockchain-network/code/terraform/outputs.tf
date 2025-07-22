# Output values for Hyperledger Fabric Managed Blockchain infrastructure
# These outputs provide essential information for connecting to and managing the blockchain network

output "network_id" {
  description = "ID of the Managed Blockchain network"
  value       = aws_managedblockchain_network.fabric_network.id
}

output "network_name" {
  description = "Name of the Managed Blockchain network"
  value       = aws_managedblockchain_network.fabric_network.name
}

output "network_arn" {
  description = "ARN of the Managed Blockchain network"
  value       = aws_managedblockchain_network.fabric_network.arn
}

output "member_id" {
  description = "ID of the founding member organization"
  value       = data.aws_managedblockchain_member.fabric_member.id
}

output "member_name" {
  description = "Name of the founding member organization"
  value       = data.aws_managedblockchain_member.fabric_member.name
}

output "peer_node_id" {
  description = "ID of the peer node"
  value       = aws_managedblockchain_node.fabric_peer.id
}

output "peer_node_endpoint" {
  description = "Endpoint URL for the peer node"
  value       = aws_managedblockchain_node.fabric_peer.peer_endpoint
}

output "peer_node_event_endpoint" {
  description = "Event endpoint URL for the peer node"
  value       = aws_managedblockchain_node.fabric_peer.peer_event_endpoint
}

output "ca_endpoint" {
  description = "Certificate Authority endpoint for the member"
  value       = data.aws_managedblockchain_member.fabric_member.ca_endpoint
}

output "vpc_id" {
  description = "ID of the VPC created for blockchain infrastructure"
  value       = aws_vpc.blockchain_vpc.id
}

output "subnet_id" {
  description = "ID of the subnet for blockchain client instances"
  value       = aws_subnet.blockchain_subnet.id
}

output "vpc_endpoint_id" {
  description = "ID of the VPC endpoint for Managed Blockchain access"
  value       = aws_vpc_endpoint.managedblockchain.id
}

output "vpc_endpoint_dns_names" {
  description = "DNS names for the VPC endpoint"
  value       = aws_vpc_endpoint.managedblockchain.dns_entry[*].dns_name
}

output "client_instance_id" {
  description = "ID of the blockchain client EC2 instance (if created)"
  value       = var.create_client_instance ? aws_instance.blockchain_client[0].id : null
}

output "client_instance_public_ip" {
  description = "Public IP address of the blockchain client instance (if created)"
  value       = var.create_client_instance ? aws_instance.blockchain_client[0].public_ip : null
}

output "client_instance_private_ip" {
  description = "Private IP address of the blockchain client instance (if created)"
  value       = var.create_client_instance ? aws_instance.blockchain_client[0].private_ip : null
}

output "client_security_group_id" {
  description = "ID of the security group for blockchain client instances"
  value       = var.create_client_instance ? aws_security_group.blockchain_client_sg[0].id : null
}

output "cloudwatch_log_group_name" {
  description = "Name of the CloudWatch log group for blockchain logs"
  value       = var.enable_logging ? aws_cloudwatch_log_group.blockchain_logs[0].name : null
}

output "cloudwatch_log_group_arn" {
  description = "ARN of the CloudWatch log group for blockchain logs"
  value       = var.enable_logging ? aws_cloudwatch_log_group.blockchain_logs[0].arn : null
}

output "network_framework_version" {
  description = "Version of Hyperledger Fabric used in the network"
  value       = aws_managedblockchain_network.fabric_network.framework_version
}

output "network_status" {
  description = "Current status of the blockchain network"
  value       = aws_managedblockchain_network.fabric_network.status
}

output "member_status" {
  description = "Status of the founding member organization"
  value       = data.aws_managedblockchain_member.fabric_member.status
}

output "peer_node_status" {
  description = "Status of the peer node"
  value       = aws_managedblockchain_node.fabric_peer.status
}

output "connection_instructions" {
  description = "Instructions for connecting to the blockchain network"
  value = var.create_client_instance ? {
    ssh_command = var.key_pair_name != "" ? "ssh -i /path/to/${var.key_pair_name}.pem ec2-user@${aws_instance.blockchain_client[0].public_ip}" : "SSH key pair not specified"
    
    client_setup = {
      application_directory = "/home/ec2-user/fabric-client-app"
      environment_file     = "/home/ec2-user/fabric-client-app/.env"
      chaincode_directory  = "/home/ec2-user/fabric-client-app/chaincode"
      setup_status_file    = "/home/ec2-user/setup-complete"
    }
    
    network_details = {
      network_id     = aws_managedblockchain_network.fabric_network.id
      member_id      = data.aws_managedblockchain_member.fabric_member.id
      peer_endpoint  = aws_managedblockchain_node.fabric_peer.peer_endpoint
      ca_endpoint    = data.aws_managedblockchain_member.fabric_member.ca_endpoint
    }
  } : null
}

output "cost_estimation" {
  description = "Estimated monthly costs for the blockchain infrastructure"
  value = {
    network_cost = var.network_edition == "STARTER" ? "~$30/month base network cost" : "~$250/month base network cost"
    peer_node_cost = var.peer_node_instance_type == "bc.t3.small" ? "~$30/month per peer node" : "Variable based on instance type"
    data_transfer = "Additional charges apply for data transfer and storage"
    total_estimate = var.network_edition == "STARTER" ? "~$60-100/month for basic setup" : "~$280-320/month for standard setup"
    note = "Costs vary by region and actual usage. See AWS Managed Blockchain pricing for current rates."
  }
}

output "security_recommendations" {
  description = "Security best practices for the blockchain deployment"
  value = {
    vpc_access = "Network is deployed in isolated VPC with private subnets recommended for production"
    ssh_access = "Restrict SSH access to specific IP ranges instead of 0.0.0.0/0"
    admin_credentials = "Change default admin password immediately after deployment"
    monitoring = var.enable_logging ? "CloudWatch logging enabled for audit trails" : "Enable CloudWatch logging for production deployments"
    certificate_management = "Use proper certificate management for production workloads"
    network_policies = "Implement proper network policies and firewall rules"
  }
}

output "getting_started" {
  description = "Quick start guide for using the blockchain network"
  value = {
    step_1 = "Connect to client instance using SSH"
    step_2 = "Navigate to /home/ec2-user/fabric-client-app"
    step_3 = "Review environment configuration in .env file"
    step_4 = "Develop and test smart contracts in chaincode/ directory"
    step_5 = "Use Fabric SDK to interact with the blockchain network"
    documentation = "Refer to Hyperledger Fabric documentation for chaincode development"
    aws_docs = "See AWS Managed Blockchain documentation for network management"
  }
}