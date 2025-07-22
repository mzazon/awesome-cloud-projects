# Resource identifiers and ARNs
output "database_secret_arn" {
  description = "ARN of the database credentials secret"
  value       = aws_secretsmanager_secret.database_secret.arn
}

output "api_secret_arn" {
  description = "ARN of the API keys secret"
  value       = aws_secretsmanager_secret.api_secret.arn
}

output "kms_key_arn" {
  description = "ARN of the KMS key used for encryption"
  value       = var.enable_kms_encryption ? aws_kms_key.secrets_key[0].arn : null
}

output "kms_key_id" {
  description = "ID of the KMS key used for encryption"
  value       = var.enable_kms_encryption ? aws_kms_key.secrets_key[0].key_id : null
}

# ECS Resources
output "ecs_cluster_name" {
  description = "Name of the ECS cluster"
  value       = aws_ecs_cluster.main.name
}

output "ecs_cluster_arn" {
  description = "ARN of the ECS cluster"
  value       = aws_ecs_cluster.main.arn
}

output "ecs_task_definition_arn" {
  description = "ARN of the ECS task definition"
  value       = aws_ecs_task_definition.main.arn
}

output "ecs_task_role_arn" {
  description = "ARN of the ECS task role"
  value       = aws_iam_role.ecs_task_role.arn
}

output "ecs_execution_role_arn" {
  description = "ARN of the ECS execution role"
  value       = aws_iam_role.ecs_execution_role.arn
}

# EKS Resources
output "eks_cluster_name" {
  description = "Name of the EKS cluster"
  value       = aws_eks_cluster.main.name
}

output "eks_cluster_arn" {
  description = "ARN of the EKS cluster"
  value       = aws_eks_cluster.main.arn
}

output "eks_cluster_endpoint" {
  description = "Endpoint for the EKS cluster"
  value       = aws_eks_cluster.main.endpoint
}

output "eks_cluster_version" {
  description = "Version of the EKS cluster"
  value       = aws_eks_cluster.main.version
}

output "eks_cluster_security_group_id" {
  description = "Security group ID of the EKS cluster"
  value       = aws_eks_cluster.main.vpc_config[0].cluster_security_group_id
}

output "eks_cluster_certificate_authority_data" {
  description = "Certificate authority data for the EKS cluster"
  value       = aws_eks_cluster.main.certificate_authority[0].data
}

output "eks_node_group_arn" {
  description = "ARN of the EKS node group"
  value       = aws_eks_node_group.main.arn
}

output "eks_pod_role_arn" {
  description = "ARN of the EKS pod role for IRSA"
  value       = aws_iam_role.eks_pod_role.arn
}

output "eks_oidc_provider_arn" {
  description = "ARN of the OIDC provider for EKS"
  value       = aws_iam_openid_connect_provider.eks_oidc.arn
}

# Lambda Resources
output "lambda_function_name" {
  description = "Name of the Lambda rotation function"
  value       = var.enable_secret_rotation ? aws_lambda_function.rotation[0].function_name : null
}

output "lambda_function_arn" {
  description = "ARN of the Lambda rotation function"
  value       = var.enable_secret_rotation ? aws_lambda_function.rotation[0].arn : null
}

output "lambda_role_arn" {
  description = "ARN of the Lambda execution role"
  value       = var.enable_secret_rotation ? aws_iam_role.lambda_role[0].arn : null
}

# CloudWatch Resources
output "ecs_log_group_name" {
  description = "Name of the CloudWatch log group for ECS"
  value       = aws_cloudwatch_log_group.ecs_logs.name
}

output "ecs_log_group_arn" {
  description = "ARN of the CloudWatch log group for ECS"
  value       = aws_cloudwatch_log_group.ecs_logs.arn
}

output "secrets_audit_log_group_name" {
  description = "Name of the CloudWatch log group for Secrets Manager audit"
  value       = var.enable_monitoring ? aws_cloudwatch_log_group.secrets_audit[0].name : null
}

output "unauthorized_access_alarm_name" {
  description = "Name of the CloudWatch alarm for unauthorized access"
  value       = var.enable_monitoring ? aws_cloudwatch_metric_alarm.unauthorized_access[0].alarm_name : null
}

# Network Configuration
output "vpc_id" {
  description = "ID of the VPC used by the resources"
  value       = local.vpc_id
}

output "subnet_ids" {
  description = "List of subnet IDs used by the resources"
  value       = local.subnet_ids
}

# Configuration Values
output "aws_region" {
  description = "AWS region where resources are deployed"
  value       = data.aws_region.current.name
}

output "aws_account_id" {
  description = "AWS account ID where resources are deployed"
  value       = data.aws_caller_identity.current.account_id
}

# Kubernetes Configuration
output "kubectl_config_command" {
  description = "Command to configure kubectl for the EKS cluster"
  value       = "aws eks update-kubeconfig --name ${aws_eks_cluster.main.name} --region ${data.aws_region.current.name}"
}

# ECS Task Run Command
output "ecs_task_run_command" {
  description = "Command to run an ECS task"
  value       = "aws ecs run-task --cluster ${aws_ecs_cluster.main.name} --task-definition ${aws_ecs_task_definition.main.family} --launch-type FARGATE --network-configuration \"awsvpcConfiguration={subnets=[${join(",", local.subnet_ids)}],assignPublicIp=ENABLED}\""
}

# Secret Access Commands
output "database_secret_get_command" {
  description = "Command to retrieve database secret"
  value       = "aws secretsmanager get-secret-value --secret-id ${aws_secretsmanager_secret.database_secret.name}"
}

output "api_secret_get_command" {
  description = "Command to retrieve API secret"
  value       = "aws secretsmanager get-secret-value --secret-id ${aws_secretsmanager_secret.api_secret.name}"
}

# Kubernetes Manifests
output "kubernetes_service_account_manifest" {
  description = "Kubernetes service account manifest with IRSA annotation"
  value = {
    apiVersion = "v1"
    kind       = "ServiceAccount"
    metadata = {
      name      = "secrets-demo-sa"
      namespace = "default"
      annotations = {
        "eks.amazonaws.com/role-arn" = aws_iam_role.eks_pod_role.arn
      }
    }
  }
}

output "kubernetes_secret_provider_class_manifest" {
  description = "SecretProviderClass manifest for Secrets Store CSI driver"
  value = {
    apiVersion = "secrets-store.csi.x-k8s.io/v1"
    kind       = "SecretProviderClass"
    metadata = {
      name      = "demo-secrets-provider"
      namespace = "default"
    }
    spec = {
      provider = "aws"
      parameters = {
        objects = yamlencode([
          {
            objectName = aws_secretsmanager_secret.database_secret.name
            objectType = "secretsmanager"
            jmesPath = [
              {
                path        = "username"
                objectAlias = "db_username"
              },
              {
                path        = "password"
                objectAlias = "db_password"
              },
              {
                path        = "host"
                objectAlias = "db_host"
              }
            ]
          },
          {
            objectName = aws_secretsmanager_secret.api_secret.name
            objectType = "secretsmanager"
            jmesPath = [
              {
                path        = "github_token"
                objectAlias = "github_token"
              },
              {
                path        = "stripe_key"
                objectAlias = "stripe_key"
              }
            ]
          }
        ])
      }
    }
  }
}

# Resource Summary
output "resource_summary" {
  description = "Summary of all created resources"
  value = {
    secrets = {
      database_secret = {
        name = aws_secretsmanager_secret.database_secret.name
        arn  = aws_secretsmanager_secret.database_secret.arn
      }
      api_secret = {
        name = aws_secretsmanager_secret.api_secret.name
        arn  = aws_secretsmanager_secret.api_secret.arn
      }
    }
    ecs = {
      cluster_name = aws_ecs_cluster.main.name
      cluster_arn  = aws_ecs_cluster.main.arn
      task_definition = {
        family = aws_ecs_task_definition.main.family
        arn    = aws_ecs_task_definition.main.arn
      }
    }
    eks = {
      cluster_name = aws_eks_cluster.main.name
      cluster_arn  = aws_eks_cluster.main.arn
      endpoint     = aws_eks_cluster.main.endpoint
      version      = aws_eks_cluster.main.version
    }
    lambda = {
      function_name = var.enable_secret_rotation ? aws_lambda_function.rotation[0].function_name : null
      function_arn  = var.enable_secret_rotation ? aws_lambda_function.rotation[0].arn : null
    }
    kms = {
      key_id  = var.enable_kms_encryption ? aws_kms_key.secrets_key[0].key_id : null
      key_arn = var.enable_kms_encryption ? aws_kms_key.secrets_key[0].arn : null
    }
  }
}