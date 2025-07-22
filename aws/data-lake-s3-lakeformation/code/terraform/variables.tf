# Core configuration variables
variable "aws_region" {
  description = "AWS region for all resources"
  type        = string
  default     = "us-east-1"
  
  validation {
    condition     = can(regex("^[a-z]{2}-[a-z]+-[0-9]+$", var.aws_region))
    error_message = "AWS region must be in the format: us-east-1, eu-west-1, etc."
  }
}

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
  default     = "dev"
  
  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be one of: dev, staging, prod."
  }
}

variable "project_name" {
  description = "Project name for resource naming and tagging"
  type        = string
  default     = "data-lake-lf"
  
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]*[a-z0-9]$", var.project_name))
    error_message = "Project name must start with a letter, contain only lowercase letters, numbers, and hyphens."
  }
}

# Data Lake Configuration
variable "data_lake_name" {
  description = "Name for the data lake (will be prefixed with random suffix)"
  type        = string
  default     = "datalake"
  
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]*[a-z0-9]$", var.data_lake_name))
    error_message = "Data lake name must start with a letter, contain only lowercase letters, numbers, and hyphens."
  }
}

variable "database_name" {
  description = "Glue database name for the data lake"
  type        = string
  default     = "sales_database"
  
  validation {
    condition     = can(regex("^[a-z][a-z0-9_]*[a-z0-9]$", var.database_name))
    error_message = "Database name must start with a letter, contain only lowercase letters, numbers, and underscores."
  }
}

# S3 Configuration
variable "enable_s3_versioning" {
  description = "Enable versioning on S3 buckets"
  type        = bool
  default     = true
}

variable "s3_encryption_algorithm" {
  description = "S3 encryption algorithm (AES256 or aws:kms)"
  type        = string
  default     = "AES256"
  
  validation {
    condition     = contains(["AES256", "aws:kms"], var.s3_encryption_algorithm)
    error_message = "S3 encryption algorithm must be either AES256 or aws:kms."
  }
}

variable "s3_kms_key_id" {
  description = "KMS key ID for S3 encryption (required if encryption_algorithm is aws:kms)"
  type        = string
  default     = null
}

# Lake Formation Configuration
variable "lake_formation_admins" {
  description = "List of ARNs for Lake Formation administrators"
  type        = list(string)
  default     = []
}

variable "enable_external_data_filtering" {
  description = "Enable external data filtering in Lake Formation"
  type        = bool
  default     = true
}

variable "trusted_resource_owners" {
  description = "List of trusted resource owners for Lake Formation"
  type        = list(string)
  default     = []
}

# LF-Tags Configuration
variable "lf_tags" {
  description = "Lake Formation tags configuration"
  type = map(object({
    tag_key    = string
    tag_values = list(string)
  }))
  default = {
    department = {
      tag_key    = "Department"
      tag_values = ["Sales", "Marketing", "Finance", "Engineering"]
    }
    classification = {
      tag_key    = "Classification"
      tag_values = ["Public", "Internal", "Confidential", "Restricted"]
    }
    data_zone = {
      tag_key    = "DataZone"
      tag_values = ["Raw", "Processed", "Curated"]
    }
    access_level = {
      tag_key    = "AccessLevel"
      tag_values = ["ReadOnly", "ReadWrite", "Admin"]
    }
  }
}

# IAM User Configuration
variable "create_iam_users" {
  description = "Create IAM users for data lake access"
  type        = bool
  default     = true
}

variable "iam_users" {
  description = "IAM users to create for data lake access"
  type = map(object({
    name        = string
    role_name   = string
    policies    = list(string)
  }))
  default = {
    lake_formation_admin = {
      name        = "lake-formation-admin"
      role_name   = "LakeFormationAdminRole"
      policies    = ["arn:aws:iam::aws:policy/LakeFormationDataAdmin"]
    }
    data_analyst = {
      name        = "data-analyst"
      role_name   = "DataAnalystRole"
      policies    = ["arn:aws:iam::aws:policy/AmazonAthenaFullAccess"]
    }
    data_engineer = {
      name        = "data-engineer"
      role_name   = "DataEngineerRole"
      policies    = ["arn:aws:iam::aws:policy/AWSGlueConsoleFullAccess"]
    }
  }
}

# CloudTrail Configuration
variable "enable_cloudtrail" {
  description = "Enable CloudTrail for audit logging"
  type        = bool
  default     = true
}

variable "cloudtrail_name" {
  description = "Name for the CloudTrail"
  type        = string
  default     = "lake-formation-audit-trail"
}

variable "cloudwatch_log_group_name" {
  description = "CloudWatch log group name for Lake Formation audit logs"
  type        = string
  default     = "/aws/lakeformation/audit"
}

variable "cloudwatch_log_retention_days" {
  description = "CloudWatch log retention period in days"
  type        = number
  default     = 14
  
  validation {
    condition = contains([
      1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1827, 3653
    ], var.cloudwatch_log_retention_days)
    error_message = "CloudWatch log retention days must be a valid CloudWatch retention period."
  }
}

# Glue Crawler Configuration
variable "enable_glue_crawlers" {
  description = "Enable Glue crawlers for data catalog"
  type        = bool
  default     = true
}

variable "crawler_schedule" {
  description = "Cron expression for Glue crawler schedule"
  type        = string
  default     = "cron(0 6 * * ? *)"  # Daily at 6 AM
}

# Sample Data Configuration
variable "upload_sample_data" {
  description = "Upload sample data to S3 buckets"
  type        = bool
  default     = true
}

variable "sample_data_files" {
  description = "Sample data files to upload"
  type = map(object({
    key     = string
    content = string
  }))
  default = {
    sales_data = {
      key = "sales/sales_data.csv"
      content = "customer_id,product_id,order_date,quantity,price,region,sales_rep\n1001,P001,2024-01-15,2,29.99,North,John Smith\n1002,P002,2024-01-16,1,49.99,South,Jane Doe\n1003,P001,2024-01-17,3,29.99,East,Bob Johnson\n1004,P003,2024-01-18,1,99.99,West,Alice Brown\n1005,P002,2024-01-19,2,49.99,North,John Smith\n1006,P001,2024-01-20,1,29.99,South,Jane Doe\n1007,P003,2024-01-21,2,99.99,East,Bob Johnson\n1008,P002,2024-01-22,1,49.99,West,Alice Brown"
    }
    customer_data = {
      key = "customers/customer_data.csv"
      content = "customer_id,first_name,last_name,email,phone,registration_date\n1001,Michael,Johnson,mjohnson@example.com,555-0101,2023-12-01\n1002,Sarah,Davis,sdavis@example.com,555-0102,2023-12-02\n1003,Robert,Wilson,rwilson@example.com,555-0103,2023-12-03\n1004,Jennifer,Brown,jbrown@example.com,555-0104,2023-12-04\n1005,William,Jones,wjones@example.com,555-0105,2023-12-05\n1006,Lisa,Garcia,lgarcia@example.com,555-0106,2023-12-06\n1007,David,Miller,dmiller@example.com,555-0107,2023-12-07\n1008,Susan,Anderson,sanderson@example.com,555-0108,2023-12-08"
    }
  }
}

# Data Cell Filters Configuration
variable "enable_data_cell_filters" {
  description = "Enable data cell filters for fine-grained access control"
  type        = bool
  default     = true
}

variable "data_cell_filters" {
  description = "Data cell filters configuration"
  type = map(object({
    name             = string
    table_name       = string
    column_names     = list(string)
    excluded_columns = list(string)
    row_filter       = string
  }))
  default = {
    customer_pii_filter = {
      name             = "customer_pii_filter"
      table_name       = "customer_customer_data"
      column_names     = []
      excluded_columns = ["email", "phone"]
      row_filter       = ""
    }
    sales_region_filter = {
      name         = "sales_region_filter"
      table_name   = "sales_sales_data"
      column_names = ["customer_id", "product_id", "order_date", "quantity", "price", "region"]
      excluded_columns = []
      row_filter   = "region IN ('North', 'South')"
    }
  }
}