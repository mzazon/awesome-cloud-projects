# Core project configuration
variable "project_name" {
  description = "Name of the project (will be used as prefix for resources)"
  type        = string
  default     = "data-viz-pipeline"
  
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]*[a-z0-9]$", var.project_name))
    error_message = "Project name must start with a letter, contain only lowercase letters, numbers, and hyphens, and end with a letter or number."
  }
}

variable "environment" {
  description = "Environment name (e.g., dev, staging, prod)"
  type        = string
  default     = "dev"
  
  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be one of: dev, staging, prod."
  }
}

variable "aws_region" {
  description = "AWS region for resource deployment"
  type        = string
  default     = "us-east-1"
  
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.aws_region))
    error_message = "AWS region must be a valid region name."
  }
}

# S3 Configuration
variable "enable_s3_versioning" {
  description = "Enable versioning on S3 buckets"
  type        = bool
  default     = true
}

variable "s3_lifecycle_enabled" {
  description = "Enable S3 lifecycle management"
  type        = bool
  default     = true
}

variable "s3_lifecycle_transition_days" {
  description = "Number of days before transitioning objects to IA storage class"
  type        = number
  default     = 30
}

variable "s3_lifecycle_expiration_days" {
  description = "Number of days before expiring old versions of objects"
  type        = number
  default     = 365
}

# Glue Configuration
variable "glue_crawler_schedule" {
  description = "Schedule expression for Glue crawler (cron format)"
  type        = string
  default     = "cron(0 2 * * ? *)" # Daily at 2 AM UTC
  
  validation {
    condition     = can(regex("^cron\\(.*\\)$", var.glue_crawler_schedule))
    error_message = "Glue crawler schedule must be in cron format."
  }
}

variable "glue_job_timeout" {
  description = "Timeout for Glue ETL jobs in minutes"
  type        = number
  default     = 60
  
  validation {
    condition     = var.glue_job_timeout >= 1 && var.glue_job_timeout <= 2880
    error_message = "Glue job timeout must be between 1 and 2880 minutes."
  }
}

variable "glue_job_max_retries" {
  description = "Maximum number of retries for Glue ETL jobs"
  type        = number
  default     = 1
  
  validation {
    condition     = var.glue_job_max_retries >= 0 && var.glue_job_max_retries <= 10
    error_message = "Glue job max retries must be between 0 and 10."
  }
}

variable "glue_version" {
  description = "Glue version for ETL jobs"
  type        = string
  default     = "4.0"
  
  validation {
    condition     = contains(["3.0", "4.0"], var.glue_version)
    error_message = "Glue version must be either 3.0 or 4.0."
  }
}

# Athena Configuration
variable "athena_query_result_encryption" {
  description = "Enable encryption for Athena query results"
  type        = bool
  default     = true
}

variable "athena_workgroup_force_configuration" {
  description = "Force workgroup configuration for all queries"
  type        = bool
  default     = true
}

variable "athena_bytes_scanned_cutoff" {
  description = "Bytes scanned cutoff per query in bytes"
  type        = number
  default     = 10737418240 # 10 GB
}

# Lambda Configuration
variable "lambda_runtime" {
  description = "Runtime for Lambda functions"
  type        = string
  default     = "nodejs18.x"
  
  validation {
    condition     = contains(["nodejs16.x", "nodejs18.x", "nodejs20.x"], var.lambda_runtime)
    error_message = "Lambda runtime must be a supported Node.js version."
  }
}

variable "lambda_timeout" {
  description = "Timeout for Lambda functions in seconds"
  type        = number
  default     = 300
  
  validation {
    condition     = var.lambda_timeout >= 1 && var.lambda_timeout <= 900
    error_message = "Lambda timeout must be between 1 and 900 seconds."
  }
}

variable "lambda_memory_size" {
  description = "Memory allocation for Lambda functions in MB"
  type        = number
  default     = 256
  
  validation {
    condition     = var.lambda_memory_size >= 128 && var.lambda_memory_size <= 10240
    error_message = "Lambda memory size must be between 128 and 10240 MB."
  }
}

# Sample Data Configuration
variable "upload_sample_data" {
  description = "Whether to upload sample data files to S3"
  type        = bool
  default     = true
}

variable "sample_data_files" {
  description = "Map of sample data files to create"
  type = map(object({
    content = string
    key     = string
  }))
  default = {
    "sales_q1" = {
      content = "order_id,customer_id,product_category,product_name,quantity,unit_price,order_date,region,sales_rep\n1001,C001,Electronics,Laptop,1,1200.00,2024-01-15,North,John Smith\n1002,C002,Clothing,T-Shirt,3,25.00,2024-01-16,South,Jane Doe\n1003,C003,Electronics,Smartphone,2,800.00,2024-01-17,East,Bob Johnson\n1004,C001,Books,Programming Guide,1,45.00,2024-01-18,North,John Smith\n1005,C004,Electronics,Tablet,1,500.00,2024-01-19,West,Alice Brown"
      key     = "sales-data/sales_2024_q1.csv"
    }
    "customers" = {
      content = "customer_id,customer_name,email,registration_date,customer_tier,city,state\nC001,Michael Johnson,mjohnson@email.com,2023-06-15,Gold,New York,NY\nC002,Sarah Williams,swilliams@email.com,2023-08-22,Silver,Atlanta,GA\nC003,David Brown,dbrown@email.com,2023-09-10,Gold,Boston,MA\nC004,Lisa Davis,ldavis@email.com,2023-11-05,Bronze,Los Angeles,CA\nC005,Robert Wilson,rwilson@email.com,2023-12-01,Silver,Miami,FL"
      key     = "sales-data/customers.csv"
    }
  }
}

# Security Configuration
variable "enable_kms_encryption" {
  description = "Enable KMS encryption for supported resources"
  type        = bool
  default     = true
}

variable "enable_cloudtrail_logging" {
  description = "Enable CloudTrail logging for API calls"
  type        = bool
  default     = false
}

# Cost Optimization
variable "enable_intelligent_tiering" {
  description = "Enable S3 Intelligent Tiering for cost optimization"
  type        = bool
  default     = true
}

# Monitoring and Alerting
variable "enable_cloudwatch_alarms" {
  description = "Enable CloudWatch alarms for monitoring"
  type        = bool
  default     = true
}

variable "notification_email" {
  description = "Email address for notifications (optional)"
  type        = string
  default     = ""
  
  validation {
    condition     = var.notification_email == "" || can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", var.notification_email))
    error_message = "Notification email must be a valid email address or empty string."
  }
}