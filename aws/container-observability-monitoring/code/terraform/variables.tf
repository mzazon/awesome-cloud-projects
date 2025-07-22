# General Configuration
variable "environment" {
  description = "Environment name"
  type        = string
  default     = "observability"
}

variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-west-2"
}

variable "project_name" {
  description = "Project name used for resource naming"
  type        = string
  default     = "container-observability"
}

# Random suffix for unique resource names
variable "random_suffix" {
  description = "Random suffix for unique resource names"
  type        = string
  default     = ""
}

# EKS Configuration
variable "eks_cluster_name" {
  description = "Name of the EKS cluster"
  type        = string
  default     = ""
}

variable "eks_cluster_version" {
  description = "Kubernetes version for EKS cluster"
  type        = string
  default     = "1.28"
}

variable "eks_node_instance_type" {
  description = "EC2 instance type for EKS worker nodes"
  type        = string
  default     = "t3.large"
}

variable "eks_node_group_min_size" {
  description = "Minimum number of worker nodes"
  type        = number
  default     = 3
}

variable "eks_node_group_max_size" {
  description = "Maximum number of worker nodes"
  type        = number
  default     = 6
}

variable "eks_node_group_desired_size" {
  description = "Desired number of worker nodes"
  type        = number
  default     = 3
}

variable "eks_node_disk_size" {
  description = "Disk size for EKS worker nodes (GB)"
  type        = number
  default     = 50
}

# ECS Configuration
variable "ecs_cluster_name" {
  description = "Name of the ECS cluster"
  type        = string
  default     = ""
}

variable "ecs_task_cpu" {
  description = "CPU units for ECS tasks"
  type        = number
  default     = 512
}

variable "ecs_task_memory" {
  description = "Memory for ECS tasks (MB)"
  type        = number
  default     = 1024
}

variable "ecs_service_desired_count" {
  description = "Desired number of ECS tasks"
  type        = number
  default     = 2
}

# Monitoring Configuration
variable "monitoring_namespace" {
  description = "Kubernetes namespace for monitoring stack"
  type        = string
  default     = "monitoring"
}

variable "prometheus_storage_size" {
  description = "Storage size for Prometheus (GB)"
  type        = string
  default     = "50Gi"
}

variable "grafana_storage_size" {
  description = "Storage size for Grafana (GB)"
  type        = string
  default     = "10Gi"
}

variable "grafana_admin_password" {
  description = "Admin password for Grafana"
  type        = string
  default     = "observability123!"
  sensitive   = true
}

variable "log_retention_days" {
  description = "CloudWatch log retention in days"
  type        = number
  default     = 30
}

# OpenSearch Configuration
variable "opensearch_instance_type" {
  description = "Instance type for OpenSearch cluster"
  type        = string
  default     = "t3.small.search"
}

variable "opensearch_instance_count" {
  description = "Number of instances in OpenSearch cluster"
  type        = number
  default     = 3
}

variable "opensearch_volume_size" {
  description = "EBS volume size for OpenSearch nodes (GB)"
  type        = number
  default     = 20
}

# Alerting Configuration
variable "alert_email" {
  description = "Email address for CloudWatch alerts"
  type        = string
  default     = "admin@example.com"
}

variable "cpu_threshold" {
  description = "CPU utilization threshold for alerts (%)"
  type        = number
  default     = 80
}

variable "memory_threshold" {
  description = "Memory utilization threshold for alerts (%)"
  type        = number
  default     = 80
}

variable "anomaly_threshold" {
  description = "Anomaly detection threshold (standard deviations)"
  type        = number
  default     = 2
}

# Performance Optimization Configuration
variable "performance_analysis_schedule" {
  description = "CloudWatch Events schedule for performance analysis"
  type        = string
  default     = "rate(1 hour)"
}

variable "optimization_lambda_timeout" {
  description = "Timeout for performance optimization Lambda (seconds)"
  type        = number
  default     = 60
}

# Network Configuration
variable "vpc_cidr" {
  description = "CIDR block for VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "private_subnet_cidrs" {
  description = "CIDR blocks for private subnets"
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks for public subnets"
  type        = list(string)
  default     = ["10.0.101.0/24", "10.0.102.0/24", "10.0.103.0/24"]
}

# Container Insights Configuration
variable "enable_container_insights" {
  description = "Enable Container Insights for EKS and ECS"
  type        = bool
  default     = true
}

variable "enhanced_monitoring" {
  description = "Enable enhanced monitoring for Container Insights"
  type        = bool
  default     = true
}

# X-Ray Configuration
variable "enable_xray_tracing" {
  description = "Enable AWS X-Ray tracing"
  type        = bool
  default     = true
}

# ADOT Configuration
variable "enable_adot_collector" {
  description = "Enable AWS Distro for OpenTelemetry collector"
  type        = bool
  default     = true
}

variable "adot_collection_interval" {
  description = "Collection interval for ADOT collector (seconds)"
  type        = number
  default     = 60
}

# Tags
variable "additional_tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}

# Feature Flags
variable "enable_opensearch" {
  description = "Enable OpenSearch for log analytics"
  type        = bool
  default     = true
}

variable "enable_grafana_lb" {
  description = "Enable LoadBalancer for Grafana service"
  type        = bool
  default     = true
}

variable "enable_prometheus_persistence" {
  description = "Enable persistent storage for Prometheus"
  type        = bool
  default     = true
}

variable "enable_automated_optimization" {
  description = "Enable automated performance optimization"
  type        = bool
  default     = true
}