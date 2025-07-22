# -----------------------------------------------------------------------------
# Blockchain Network Outputs
# -----------------------------------------------------------------------------

output "blockchain_network_id" {
  description = "The unique identifier of the Amazon Managed Blockchain network"
  value       = aws_managedblockchain_network.blockchain_network.id
}

output "blockchain_network_name" {
  description = "The name of the blockchain network"
  value       = aws_managedblockchain_network.blockchain_network.name
}

output "blockchain_network_arn" {
  description = "The ARN of the blockchain network"
  value       = aws_managedblockchain_network.blockchain_network.arn
}

output "blockchain_network_status" {
  description = "The current status of the blockchain network"
  value       = aws_managedblockchain_network.blockchain_network.status
}

output "blockchain_framework" {
  description = "The blockchain framework used (Hyperledger Fabric)"
  value       = aws_managedblockchain_network.blockchain_network.framework
}

output "voting_policy" {
  description = "The voting policy configuration for the network"
  value = {
    threshold_percentage    = var.voting_threshold_percentage
    proposal_duration_hours = var.proposal_duration_hours
    threshold_comparator    = var.threshold_comparator
  }
}

# -----------------------------------------------------------------------------
# Member Outputs
# -----------------------------------------------------------------------------

output "founding_member_id" {
  description = "The unique identifier of the founding blockchain member"
  value       = data.aws_managedblockchain_member.founding_member.id
}

output "founding_member_name" {
  description = "The name of the founding blockchain member"
  value       = data.aws_managedblockchain_member.founding_member.name
}

output "founding_member_arn" {
  description = "The ARN of the founding blockchain member"
  value       = data.aws_managedblockchain_member.founding_member.arn
}

output "founding_member_status" {
  description = "The current status of the founding member"
  value       = data.aws_managedblockchain_member.founding_member.status
}

output "ca_endpoint" {
  description = "The Certificate Authority endpoint for the founding member"
  value       = data.aws_managedblockchain_member.founding_member.framework_attributes[0].fabric[0].ca_endpoint
}

output "admin_username" {
  description = "The administrator username for the founding member"
  value       = data.aws_managedblockchain_member.founding_member.framework_attributes[0].fabric[0].admin_username
}

# -----------------------------------------------------------------------------
# Peer Node Outputs
# -----------------------------------------------------------------------------

output "peer_node_id" {
  description = "The unique identifier of the peer node"
  value       = aws_managedblockchain_node.peer_node.id
}

output "peer_node_arn" {
  description = "The ARN of the peer node"
  value       = aws_managedblockchain_node.peer_node.arn
}

output "peer_node_status" {
  description = "The current status of the peer node"
  value       = aws_managedblockchain_node.peer_node.status
}

output "peer_node_instance_type" {
  description = "The instance type of the peer node"
  value       = aws_managedblockchain_node.peer_node.instance_type
}

output "peer_node_availability_zone" {
  description = "The availability zone of the peer node"
  value       = aws_managedblockchain_node.peer_node.node_configuration[0].availability_zone
}

output "peer_endpoint" {
  description = "The endpoint URL for peer operations"
  value       = aws_managedblockchain_node.peer_node.framework_attributes[0].fabric[0].peer_endpoint
}

output "peer_event_endpoint" {
  description = "The endpoint URL for peer events"
  value       = aws_managedblockchain_node.peer_node.framework_attributes[0].fabric[0].peer_event_endpoint
}

# -----------------------------------------------------------------------------
# VPC and Networking Outputs
# -----------------------------------------------------------------------------

output "vpc_id" {
  description = "The ID of the VPC used for blockchain resources"
  value       = local.vpc_id
}

output "subnet_ids" {
  description = "The IDs of the subnets used for blockchain resources"
  value       = local.subnet_ids
}

output "blockchain_security_group_id" {
  description = "The ID of the security group for blockchain endpoint"
  value       = aws_security_group.blockchain_endpoint.id
}

output "client_security_group_id" {
  description = "The ID of the security group for blockchain client (if created)"
  value       = var.create_ec2_client ? aws_security_group.blockchain_client[0].id : null
}

output "vpc_endpoint_id" {
  description = "The ID of the VPC endpoint for Managed Blockchain (if created)"
  value       = var.create_vpc_endpoint ? aws_vpc_endpoint.managedblockchain[0].id : null
}

output "vpc_endpoint_dns_names" {
  description = "The DNS names of the VPC endpoint for Managed Blockchain (if created)"
  value       = var.create_vpc_endpoint ? aws_vpc_endpoint.managedblockchain[0].dns_entry[*].dns_name : null
}

# -----------------------------------------------------------------------------
# EC2 Client Outputs
# -----------------------------------------------------------------------------

output "ec2_client_instance_id" {
  description = "The ID of the EC2 blockchain client instance (if created)"
  value       = var.create_ec2_client ? aws_instance.blockchain_client[0].id : null
}

output "ec2_client_public_ip" {
  description = "The public IP address of the EC2 blockchain client (if created)"
  value       = var.create_ec2_client ? aws_instance.blockchain_client[0].public_ip : null
}

output "ec2_client_private_ip" {
  description = "The private IP address of the EC2 blockchain client (if created)"
  value       = var.create_ec2_client ? aws_instance.blockchain_client[0].private_ip : null
}

output "ec2_client_public_dns" {
  description = "The public DNS name of the EC2 blockchain client (if created)"
  value       = var.create_ec2_client ? aws_instance.blockchain_client[0].public_dns : null
}

output "ec2_key_pair_name" {
  description = "The name of the EC2 key pair for SSH access (if created)"
  value       = var.create_ec2_client ? aws_key_pair.blockchain_client[0].key_name : null
}

output "ec2_private_key_path" {
  description = "The local path to the private key file for SSH access (if created)"
  value       = var.create_ec2_client ? local_file.private_key[0].filename : null
  sensitive   = true
}

# -----------------------------------------------------------------------------
# IAM Outputs
# -----------------------------------------------------------------------------

output "managed_blockchain_role_arn" {
  description = "The ARN of the IAM role for Managed Blockchain (if created)"
  value       = var.create_iam_roles ? aws_iam_role.managed_blockchain[0].arn : null
}

output "chaincode_execution_role_arn" {
  description = "The ARN of the IAM role for chaincode execution (if created)"
  value       = var.create_iam_roles ? aws_iam_role.chaincode_execution[0].arn : null
}

output "chaincode_execution_instance_profile_name" {
  description = "The name of the instance profile for chaincode execution (if created)"
  value       = var.create_iam_roles ? aws_iam_instance_profile.chaincode_execution[0].name : null
}

# -----------------------------------------------------------------------------
# Monitoring and Logging Outputs
# -----------------------------------------------------------------------------

output "cloudwatch_log_group_name" {
  description = "The name of the CloudWatch log group for blockchain logs (if created)"
  value       = var.enable_cloudwatch_logs ? aws_cloudwatch_log_group.blockchain_logs[0].name : null
}

output "cloudwatch_log_group_arn" {
  description = "The ARN of the CloudWatch log group for blockchain logs (if created)"
  value       = var.enable_cloudwatch_logs ? aws_cloudwatch_log_group.blockchain_logs[0].arn : null
}

output "vpc_flow_logs_group_name" {
  description = "The name of the CloudWatch log group for VPC flow logs (if created)"
  value       = var.enable_vpc_flow_logs ? aws_cloudwatch_log_group.vpc_flow_logs[0].name : null
}

output "vpc_flow_logs_id" {
  description = "The ID of the VPC flow logs configuration (if created)"
  value       = var.enable_vpc_flow_logs ? aws_flow_log.vpc_flow_logs[0].id : null
}

# -----------------------------------------------------------------------------
# Connection Information
# -----------------------------------------------------------------------------

output "blockchain_connection_info" {
  description = "Complete connection information for the blockchain network"
  value = {
    network_id                = aws_managedblockchain_network.blockchain_network.id
    network_name              = aws_managedblockchain_network.blockchain_network.name
    member_id                 = data.aws_managedblockchain_member.founding_member.id
    member_name               = data.aws_managedblockchain_member.founding_member.name
    node_id                   = aws_managedblockchain_node.peer_node.id
    ca_endpoint               = data.aws_managedblockchain_member.founding_member.framework_attributes[0].fabric[0].ca_endpoint
    peer_endpoint             = aws_managedblockchain_node.peer_node.framework_attributes[0].fabric[0].peer_endpoint
    peer_event_endpoint       = aws_managedblockchain_node.peer_node.framework_attributes[0].fabric[0].peer_event_endpoint
    admin_username            = data.aws_managedblockchain_member.founding_member.framework_attributes[0].fabric[0].admin_username
    hyperledger_fabric_version = var.hyperledger_fabric_version
    fabric_edition            = var.fabric_edition
    region                    = data.aws_region.current.name
  }
  sensitive = false
}

# -----------------------------------------------------------------------------
# SSH Connection Command
# -----------------------------------------------------------------------------

output "ssh_connection_command" {
  description = "SSH command to connect to the blockchain client instance (if created)"
  value = var.create_ec2_client ? format(
    "ssh -i %s ec2-user@%s",
    local_file.private_key[0].filename,
    aws_instance.blockchain_client[0].public_ip
  ) : null
}

# -----------------------------------------------------------------------------
# Next Steps Information
# -----------------------------------------------------------------------------

output "next_steps" {
  description = "Instructions for using the deployed blockchain infrastructure"
  value = {
    step_1 = "Connect to EC2 client: ${var.create_ec2_client ? format("ssh -i %s ec2-user@%s", try(local_file.private_key[0].filename, ""), try(aws_instance.blockchain_client[0].public_ip, "")) : "EC2 client not created"}"
    step_2 = "Check blockchain status: cd ~/blockchain-client && ./scripts/check-blockchain-status.sh"
    step_3 = "Set up peer connection: ./scripts/setup-peer-connection.sh && source network-endpoints.env"
    step_4 = "Review sample chaincode: cat chaincode/asset-chaincode.go"
    step_5 = "Create channels and deploy chaincode following Hyperledger Fabric documentation"
    note   = "Ensure all blockchain components show 'AVAILABLE' status before proceeding with development"
  }
}

# -----------------------------------------------------------------------------
# Cost Information
# -----------------------------------------------------------------------------

output "estimated_monthly_cost" {
  description = "Estimated monthly cost breakdown for the deployed resources"
  value = {
    network_membership = "~$30/month per member"
    peer_node         = format("~$%d/month for %s instance", var.peer_node_instance_type == "bc.t3.small" ? 50 : 100, var.peer_node_instance_type)
    ec2_client        = var.create_ec2_client ? format("~$%d/month for %s instance", var.ec2_instance_type == "t3.medium" ? 30 : 50, var.ec2_instance_type) : "Not created"
    vpc_endpoint      = var.create_vpc_endpoint ? "~$7/month for VPC endpoint" : "Not created"
    cloudwatch_logs   = var.enable_cloudwatch_logs ? "~$1-5/month depending on log volume" : "Not enabled"
    total_estimate    = format("~$%d-$%d/month", 
      var.create_ec2_client && var.create_vpc_endpoint ? 118 : (var.create_ec2_client ? 111 : (var.create_vpc_endpoint ? 87 : 80)),
      var.create_ec2_client && var.create_vpc_endpoint ? 192 : (var.create_ec2_client ? 185 : (var.create_vpc_endpoint ? 162 : 155))
    )
    note = "Costs vary by region and actual usage. Review AWS Managed Blockchain pricing for accurate estimates."
  }
}

# -----------------------------------------------------------------------------
# Troubleshooting Information
# -----------------------------------------------------------------------------

output "troubleshooting" {
  description = "Common troubleshooting steps and useful commands"
  value = {
    check_network_status = format("aws managedblockchain get-network --network-id %s --region %s", 
                                 aws_managedblockchain_network.blockchain_network.id, 
                                 data.aws_region.current.name)
    check_member_status  = format("aws managedblockchain get-member --network-id %s --member-id %s --region %s",
                                 aws_managedblockchain_network.blockchain_network.id,
                                 data.aws_managedblockchain_member.founding_member.id,
                                 data.aws_region.current.name)
    check_node_status   = format("aws managedblockchain get-node --network-id %s --member-id %s --node-id %s --region %s",
                                aws_managedblockchain_network.blockchain_network.id,
                                data.aws_managedblockchain_member.founding_member.id,
                                aws_managedblockchain_node.peer_node.id,
                                data.aws_region.current.name)
    vpc_endpoint_status = var.create_vpc_endpoint ? format("aws ec2 describe-vpc-endpoints --vpc-endpoint-ids %s --region %s",
                                                          aws_vpc_endpoint.managedblockchain[0].id,
                                                          data.aws_region.current.name) : "VPC endpoint not created"
    common_issues = [
      "Ensure all resources show 'AVAILABLE' status before operations",
      "Check security group rules for proper port access (30001, 30002, 7051, 7053)",
      "Verify VPC endpoint connectivity if using private subnets",
      "Review CloudWatch logs for detailed error messages"
    ]
  }
}