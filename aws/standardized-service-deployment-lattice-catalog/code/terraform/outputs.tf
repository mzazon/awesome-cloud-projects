# Output values for the VPC Lattice Service Catalog solution
# These outputs provide important information about the deployed resources

# Service Catalog Outputs
output "portfolio_id" {
  description = "ID of the Service Catalog portfolio"
  value       = aws_servicecatalog_portfolio.vpc_lattice_portfolio.id
}

output "portfolio_arn" {
  description = "ARN of the Service Catalog portfolio"
  value       = aws_servicecatalog_portfolio.vpc_lattice_portfolio.arn
}

output "service_network_product_id" {
  description = "ID of the VPC Lattice service network product"
  value       = aws_servicecatalog_product.service_network_product.id
}

output "lattice_service_product_id" {
  description = "ID of the VPC Lattice service product"
  value       = aws_servicecatalog_product.lattice_service_product.id
}

# S3 Bucket Outputs
output "cloudformation_templates_bucket" {
  description = "Name of the S3 bucket containing CloudFormation templates"
  value       = aws_s3_bucket.cloudformation_templates.bucket
}

output "cloudformation_templates_bucket_arn" {
  description = "ARN of the S3 bucket containing CloudFormation templates"
  value       = aws_s3_bucket.cloudformation_templates.arn
}

# IAM Role Outputs
output "service_catalog_launch_role_arn" {
  description = "ARN of the IAM role used for Service Catalog launches"
  value       = aws_iam_role.service_catalog_launch_role.arn
}

output "service_catalog_launch_role_name" {
  description = "Name of the IAM role used for Service Catalog launches"
  value       = aws_iam_role.service_catalog_launch_role.name
}

# CloudFormation Template URLs
output "service_network_template_url" {
  description = "S3 URL of the service network CloudFormation template"
  value       = "https://s3.${data.aws_region.current.name}.amazonaws.com/${aws_s3_bucket.cloudformation_templates.bucket}/${aws_s3_object.service_network_template.key}"
}

output "lattice_service_template_url" {
  description = "S3 URL of the lattice service CloudFormation template"
  value       = "https://s3.${data.aws_region.current.name}.amazonaws.com/${aws_s3_bucket.cloudformation_templates.bucket}/${aws_s3_object.lattice_service_template.key}"
}

# Test VPC Outputs (conditional)
output "test_vpc_id" {
  description = "ID of the test VPC (if created)"
  value       = var.create_test_vpc ? aws_vpc.test_vpc[0].id : null
}

output "test_vpc_cidr" {
  description = "CIDR block of the test VPC (if created)"
  value       = var.create_test_vpc ? aws_vpc.test_vpc[0].cidr_block : null
}

output "test_subnet_ids" {
  description = "IDs of the test subnets (if created)"
  value       = var.create_test_vpc ? aws_subnet.test_subnets[*].id : null
}

# Test VPC Lattice Resources (conditional)
output "test_service_network_id" {
  description = "ID of the test service network (if deployed)"
  value       = var.deploy_test_resources ? aws_vpclattice_service_network.test_service_network[0].id : null
}

output "test_service_network_arn" {
  description = "ARN of the test service network (if deployed)"
  value       = var.deploy_test_resources ? aws_vpclattice_service_network.test_service_network[0].arn : null
}

output "test_service_id" {
  description = "ID of the test VPC Lattice service (if deployed)"
  value       = var.deploy_test_resources ? aws_vpclattice_service.test_service[0].id : null
}

output "test_service_arn" {
  description = "ARN of the test VPC Lattice service (if deployed)"
  value       = var.deploy_test_resources ? aws_vpclattice_service.test_service[0].arn : null
}

output "test_target_group_id" {
  description = "ID of the test target group (if deployed)"
  value       = var.deploy_test_resources ? aws_vpclattice_target_group.test_target_group[0].id : null
}

output "test_target_group_arn" {
  description = "ARN of the test target group (if deployed)"
  value       = var.deploy_test_resources ? aws_vpclattice_target_group.test_target_group[0].arn : null
}

# CloudTrail Outputs (conditional)
output "cloudtrail_name" {
  description = "Name of the CloudTrail (if enabled)"
  value       = var.enable_cloudtrail_logging ? aws_cloudtrail.service_catalog_trail[0].name : null
}

output "cloudtrail_arn" {
  description = "ARN of the CloudTrail (if enabled)"
  value       = var.enable_cloudtrail_logging ? aws_cloudtrail.service_catalog_trail[0].arn : null
}

output "cloudtrail_s3_bucket" {
  description = "S3 bucket name for CloudTrail logs (if enabled)"
  value       = var.enable_cloudtrail_logging ? aws_s3_bucket.cloudtrail_logs[0].bucket : null
}

# Usage Instructions
output "service_catalog_console_url" {
  description = "AWS Console URL for Service Catalog"
  value       = "https://console.aws.amazon.com/servicecatalog/home?region=${data.aws_region.current.name}#/portfolios/${aws_servicecatalog_portfolio.vpc_lattice_portfolio.id}"
}

output "deployment_instructions" {
  description = "Instructions for using the deployed Service Catalog portfolio"
  value = <<-EOT
    Service Catalog Portfolio Successfully Deployed!
    
    Portfolio ID: ${aws_servicecatalog_portfolio.vpc_lattice_portfolio.id}
    
    Available Products:
    1. ${var.service_network_product_name} (ID: ${aws_servicecatalog_product.service_network_product.id})
    2. ${var.lattice_service_product_name} (ID: ${aws_servicecatalog_product.lattice_service_product.id})
    
    To use the Service Catalog:
    1. Navigate to: ${try("https://console.aws.amazon.com/servicecatalog/home?region=${data.aws_region.current.name}#/portfolios/${aws_servicecatalog_portfolio.vpc_lattice_portfolio.id}", "Service Catalog Console")}
    2. Select a product to launch
    3. Provide required parameters
    4. Launch the product
    
    CLI Usage:
    aws servicecatalog provision-product --product-id ${aws_servicecatalog_product.service_network_product.id} --provisioned-product-name my-service-network --provisioning-artifact-name v1.0
  EOT
}