# ===============================================
# Outputs for Simple Configuration Management
# with Parameter Store and CloudShell
# ===============================================

# ===============================================
# Application Configuration Outputs
# ===============================================

output "application_name" {
  description = "Name of the application with generated unique suffix"
  value       = local.app_name
}

output "parameter_prefix" {
  description = "Base parameter path prefix for all application parameters"
  value       = local.param_prefix
}

output "environment" {
  description = "Environment name for the deployment"
  value       = var.environment
}

output "random_suffix" {
  description = "Generated random suffix for unique resource naming"
  value       = local.random_suffix
}

# ===============================================
# Parameter Store Resource Outputs
# ===============================================

output "parameter_names" {
  description = "List of all created parameter names"
  value = [
    aws_ssm_parameter.database_url.name,
    aws_ssm_parameter.environment.name,
    aws_ssm_parameter.debug_mode.name,
    aws_ssm_parameter.app_port.name,
    aws_ssm_parameter.api_key.name,
    aws_ssm_parameter.database_password.name,
    aws_ssm_parameter.jwt_secret.name,
    aws_ssm_parameter.allowed_origins.name,
    aws_ssm_parameter.deployment_regions.name,
    aws_ssm_parameter.feature_flags.name
  ]
}

output "standard_parameters" {
  description = "Map of standard (non-encrypted) parameter names and their values"
  value = {
    database_url      = aws_ssm_parameter.database_url.name
    environment       = aws_ssm_parameter.environment.name
    debug_mode        = aws_ssm_parameter.debug_mode.name
    app_port          = aws_ssm_parameter.app_port.name
    allowed_origins   = aws_ssm_parameter.allowed_origins.name
    deployment_regions = aws_ssm_parameter.deployment_regions.name
    feature_flags     = aws_ssm_parameter.feature_flags.name
  }
}

output "secure_parameters" {
  description = "Map of secure (encrypted) parameter names"
  value = {
    api_key           = aws_ssm_parameter.api_key.name
    database_password = aws_ssm_parameter.database_password.name
    jwt_secret        = aws_ssm_parameter.jwt_secret.name
  }
  sensitive = true
}

output "parameter_arns" {
  description = "List of all parameter ARNs for IAM policy configuration"
  value = [
    aws_ssm_parameter.database_url.arn,
    aws_ssm_parameter.environment.arn,
    aws_ssm_parameter.debug_mode.arn,
    aws_ssm_parameter.app_port.arn,
    aws_ssm_parameter.api_key.arn,
    aws_ssm_parameter.database_password.arn,
    aws_ssm_parameter.jwt_secret.arn,
    aws_ssm_parameter.allowed_origins.arn,
    aws_ssm_parameter.deployment_regions.arn,
    aws_ssm_parameter.feature_flags.arn
  ]
}

# ===============================================
# KMS Configuration Outputs
# ===============================================

output "kms_key_id" {
  description = "ID of the KMS key used for parameter encryption (if created)"
  value       = var.create_kms_key ? aws_kms_key.parameter_store[0].id : null
}

output "kms_key_arn" {
  description = "ARN of the KMS key used for parameter encryption (if created)"
  value       = var.create_kms_key ? aws_kms_key.parameter_store[0].arn : null
}

output "kms_key_alias" {
  description = "Alias of the KMS key used for parameter encryption (if created)"
  value       = var.create_kms_key ? aws_kms_alias.parameter_store[0].name : null
}

# ===============================================
# IAM Configuration Outputs
# ===============================================

output "cloudshell_role_arn" {
  description = "ARN of the CloudShell IAM role for Parameter Store access (if created)"
  value       = var.create_cloudshell_role ? aws_iam_role.cloudshell_parameter_access[0].arn : null
}

output "cloudshell_role_name" {
  description = "Name of the CloudShell IAM role for Parameter Store access (if created)"
  value       = var.create_cloudshell_role ? aws_iam_role.cloudshell_parameter_access[0].name : null
}

# ===============================================
# CLI Commands for Parameter Operations
# ===============================================

output "cli_commands" {
  description = "Useful AWS CLI commands for working with the created parameters"
  value = {
    # Get all parameters by path
    get_all_parameters = "aws ssm get-parameters-by-path --path '${local.param_prefix}' --recursive --with-decryption --output table"
    
    # Get specific parameter
    get_database_url = "aws ssm get-parameter --name '${aws_ssm_parameter.database_url.name}' --query 'Parameter.Value' --output text"
    
    # Get encrypted parameter with decryption
    get_api_key = "aws ssm get-parameter --name '${aws_ssm_parameter.api_key.name}' --with-decryption --query 'Parameter.Value' --output text"
    
    # List all parameters with metadata
    describe_parameters = "aws ssm describe-parameters --parameter-filters 'Key=Name,Option=BeginsWith,Values=${local.param_prefix}' --output table"
    
    # Export parameters as environment variables
    export_env_vars = "eval $(aws ssm get-parameters-by-path --path '${local.param_prefix}' --recursive --with-decryption --query 'Parameters[].[Name,Value]' --output text | while read name value; do env_name=$(echo \"$name\" | sed 's|${local.param_prefix}/||' | tr '/' '_' | tr '[:lower:]' '[:upper:]'); echo \"export $env_name='$value'\"; done)"
  }
}

# ===============================================
# CloudShell Setup Commands
# ===============================================

output "cloudshell_setup" {
  description = "Commands to set up environment variables in CloudShell"
  value = {
    # Environment setup commands
    setup_environment = <<-EOT
      # Set up environment variables in CloudShell
      export AWS_REGION=$(aws configure get region)
      export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
      export APP_NAME="${local.app_name}"
      export PARAM_PREFIX="${local.param_prefix}"
      
      echo "✅ Environment configured for Parameter Store operations"
      echo "App namespace: ${local.app_name}"
      echo "Parameter prefix: ${local.param_prefix}"
    EOT
    
    # Parameter validation commands
    validate_parameters = <<-EOT
      # Validate all parameters are accessible
      echo "=== Validating Parameter Store Configuration ==="
      aws ssm describe-parameters \
        --parameter-filters "Key=Name,Option=BeginsWith,Values=${local.param_prefix}" \
        --query 'Parameters[].[Name,Type,Description]' \
        --output table
      
      echo "=== Testing Parameter Retrieval ==="
      aws ssm get-parameters-by-path \
        --path "${local.param_prefix}" \
        --recursive \
        --with-decryption \
        --output table
    EOT
    
    # Configuration management script
    create_config_script = <<-EOT
      # Create configuration management script in CloudShell
      cat > config-manager.sh << 'EOF'
      #!/bin/bash
      PARAM_PREFIX="${local.param_prefix}"
      ACTION="${1:-get}"
      
      case $ACTION in
          "get")
              echo "=== Configuration for $PARAM_PREFIX ==="
              aws ssm get-parameters-by-path \
                  --path "$PARAM_PREFIX" \
                  --recursive \
                  --with-decryption \
                  --query 'Parameters[].[Name,Value,Type]' \
                  --output table
              ;;
          "backup")
              echo "=== Backing up configuration for $PARAM_PREFIX ==="
              aws ssm get-parameters-by-path \
                  --path "$PARAM_PREFIX" \
                  --recursive \
                  --with-decryption \
                  --output json > "config-backup-$(date +%Y%m%d-%H%M%S).json"
              echo "Configuration backed up successfully"
              ;;
          "count")
              COUNT=$(aws ssm get-parameters-by-path \
                  --path "$PARAM_PREFIX" \
                  --recursive \
                  --query 'length(Parameters)' \
                  --output text)
              echo "Total parameters under $PARAM_PREFIX: $COUNT"
              ;;
          *)
              echo "Usage: $0 [get|backup|count]"
              exit 1
              ;;
      esac
      EOF
      
      chmod +x config-manager.sh
      echo "✅ Configuration management script created"
    EOT
  }
}

# ===============================================
# Resource Cleanup Commands  
# ===============================================

output "cleanup_commands" {
  description = "Commands to clean up Parameter Store resources"
  value = {
    # Delete all application parameters
    delete_all_parameters = <<-EOT
      # Get list of all parameters to delete
      PARAMS_TO_DELETE=$(aws ssm describe-parameters \
        --parameter-filters "Key=Name,Option=BeginsWith,Values=${local.param_prefix}" \
        --query 'Parameters[].Name' \
        --output text)
      
      # Delete parameters one by one
      for param in $PARAMS_TO_DELETE; do
        aws ssm delete-parameter --name "$param"
        echo "Deleted parameter: $param"
      done
      
      echo "✅ All parameters deleted"
    EOT
    
    # Verify parameter deletion
    verify_cleanup = "aws ssm describe-parameters --parameter-filters 'Key=Name,Option=BeginsWith,Values=${local.param_prefix}' --query 'length(Parameters)' --output text"
  }
}

# ===============================================
# Cost and Usage Information
# ===============================================

output "cost_information" {
  description = "Information about Parameter Store costs and usage"
  value = {
    parameter_count     = length(local.common_tags) > 0 ? 10 : 10  # Total parameter count
    standard_parameters = 7  # Number of standard parameters
    secure_parameters   = 3  # Number of secure parameters
    estimated_monthly_cost = "< $1 USD (first 10,000 API calls free per month)"
    cost_factors = [
      "Standard parameters: Free for first 10,000 API calls/month",
      "Advanced parameters: $0.05 per 10,000 API calls",
      "SecureString parameters: No additional cost beyond standard rates",
      "KMS key usage: $1/month for customer-managed keys"
    ]
  }
}

# ===============================================
# Security and Best Practices Information
# ===============================================

output "security_recommendations" {
  description = "Security recommendations for Parameter Store usage"
  value = {
    iam_best_practices = [
      "Use least privilege principle for Parameter Store access",
      "Implement path-based access controls using IAM policies", 
      "Regularly rotate secure parameters like API keys and passwords",
      "Enable AWS CloudTrail for audit logging of parameter access"
    ]
    
    parameter_best_practices = [
      "Use SecureString for sensitive data like passwords and API keys",
      "Organize parameters hierarchically using consistent naming conventions",
      "Tag parameters consistently for management and cost allocation",
      "Use parameter policies for advanced lifecycle management"
    ]
    
    monitoring_recommendations = [
      "Set up CloudWatch alarms for parameter access patterns",
      "Monitor failed parameter retrieval attempts",
      "Use AWS Config to track parameter configuration changes",
      "Implement parameter backup and recovery procedures"
    ]
  }
}

# ===============================================
# Integration Examples
# ===============================================

output "integration_examples" {
  description = "Example code snippets for using parameters in applications"
  value = {
    # Python boto3 example
    python_example = <<-EOT
      import boto3
      
      def get_app_config():
          ssm = boto3.client('ssm')
          
          # Get all parameters by path
          response = ssm.get_parameters_by_path(
              Path='${local.param_prefix}',
              Recursive=True,
              WithDecryption=True
          )
          
          config = {}
          for param in response['Parameters']:
              key = param['Name'].replace('${local.param_prefix}/', '').replace('/', '_').upper()
              config[key] = param['Value']
          
          return config
    EOT
    
    # Node.js AWS SDK example
    nodejs_example = <<-EOT
      const AWS = require('aws-sdk');
      const ssm = new AWS.SSM();
      
      async function getAppConfig() {
          const params = {
              Path: '${local.param_prefix}',
              Recursive: true,
              WithDecryption: true
          };
          
          const result = await ssm.getParametersByPath(params).promise();
          const config = {};
          
          result.Parameters.forEach(param => {
              const key = param.Name
                  .replace('${local.param_prefix}/', '')
                  .replace(/\//g, '_')
                  .toUpperCase();
              config[key] = param.Value;
          });
          
          return config;
      }
    EOT
  }
}