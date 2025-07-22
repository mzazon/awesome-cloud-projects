# AWS Configuration
variable "aws_region" {
  description = "AWS region for resources"
  type        = string
  default     = "us-east-1"
}

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
  default     = "dev"
}

# Email Configuration
variable "sender_domain" {
  description = "Domain to verify for sending emails (e.g., yourdomain.com)"
  type        = string
  validation {
    condition     = can(regex("^[a-zA-Z0-9][a-zA-Z0-9-]{1,61}[a-zA-Z0-9]\\.[a-zA-Z]{2,}$", var.sender_domain))
    error_message = "The sender_domain must be a valid domain name."
  }
}

variable "sender_email" {
  description = "Email address to verify for sending emails (e.g., marketing@yourdomain.com)"
  type        = string
  validation {
    condition     = can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", var.sender_email))
    error_message = "The sender_email must be a valid email address."
  }
}

variable "notification_email" {
  description = "Email address to receive bounce and complaint notifications"
  type        = string
  validation {
    condition     = can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", var.notification_email))
    error_message = "The notification_email must be a valid email address."
  }
}

# S3 Configuration
variable "bucket_name_prefix" {
  description = "Prefix for S3 bucket name (will be combined with random suffix)"
  type        = string
  default     = "email-marketing"
}

variable "enable_bucket_versioning" {
  description = "Enable versioning for S3 bucket"
  type        = bool
  default     = true
}

variable "bucket_lifecycle_days" {
  description = "Number of days to retain objects in S3 bucket"
  type        = number
  default     = 90
}

# SES Configuration
variable "enable_dkim" {
  description = "Enable DKIM signing for the domain"
  type        = bool
  default     = true
}

variable "require_tls" {
  description = "Require TLS for email delivery"
  type        = bool
  default     = true
}

variable "reputation_tracking" {
  description = "Enable reputation tracking for the configuration set"
  type        = bool
  default     = true
}

variable "suppression_reasons" {
  description = "Reasons for suppressing emails (BOUNCE, COMPLAINT)"
  type        = list(string)
  default     = ["BOUNCE", "COMPLAINT"]
  validation {
    condition = alltrue([
      for reason in var.suppression_reasons : contains(["BOUNCE", "COMPLAINT"], reason)
    ])
    error_message = "Suppression reasons must be either 'BOUNCE' or 'COMPLAINT'."
  }
}

# CloudWatch Configuration
variable "enable_cloudwatch_dashboard" {
  description = "Create CloudWatch dashboard for email metrics"
  type        = bool
  default     = true
}

variable "bounce_rate_threshold" {
  description = "Bounce rate threshold for CloudWatch alarm (percentage)"
  type        = number
  default     = 5
  validation {
    condition     = var.bounce_rate_threshold >= 0 && var.bounce_rate_threshold <= 100
    error_message = "Bounce rate threshold must be between 0 and 100."
  }
}

variable "complaint_rate_threshold" {
  description = "Complaint rate threshold for CloudWatch alarm (percentage)"
  type        = number
  default     = 0.1
  validation {
    condition     = var.complaint_rate_threshold >= 0 && var.complaint_rate_threshold <= 100
    error_message = "Complaint rate threshold must be between 0 and 100."
  }
}

# Lambda Configuration
variable "enable_bounce_handler" {
  description = "Create Lambda function for automated bounce handling"
  type        = bool
  default     = true
}

variable "lambda_runtime" {
  description = "Lambda runtime for bounce handler function"
  type        = string
  default     = "python3.9"
}

variable "lambda_timeout" {
  description = "Lambda function timeout in seconds"
  type        = number
  default     = 30
}

# EventBridge Configuration
variable "enable_campaign_automation" {
  description = "Enable EventBridge for campaign automation"
  type        = bool
  default     = true
}

variable "campaign_schedule" {
  description = "Schedule expression for automated campaigns (e.g., 'rate(7 days)')"
  type        = string
  default     = "rate(7 days)"
}

# Email Templates
variable "welcome_template" {
  description = "Configuration for welcome email template"
  type = object({
    name    = string
    subject = string
    html    = string
    text    = string
  })
  default = {
    name    = "welcome-campaign"
    subject = "Welcome to Our Community, {{name}}!"
    html    = "<html><body><h2>Welcome {{name}}!</h2><p>Thank you for joining our community. We are excited to have you aboard!</p><p>As a welcome gift, use code <strong>WELCOME10</strong> for 10% off your first purchase.</p><p>Best regards,<br/>The Marketing Team</p><p><a href=\"{{unsubscribe_url}}\">Unsubscribe</a></p></body></html>"
    text    = "Welcome {{name}}! Thank you for joining our community. Use code WELCOME10 for 10% off your first purchase. Unsubscribe: {{unsubscribe_url}}"
  }
}

variable "promotion_template" {
  description = "Configuration for promotional email template"
  type = object({
    name    = string
    subject = string
    html    = string
    text    = string
  })
  default = {
    name    = "product-promotion"
    subject = "Exclusive Offer: {{discount}}% Off {{product_name}}"
    html    = "<html><body><h2>Special Offer for {{name}}!</h2><p>Get {{discount}}% off our popular {{product_name}}!</p><p>Limited time offer - expires {{expiry_date}}</p><p><a href=\"{{product_url}}\" style=\"background-color: #007bff; color: white; padding: 10px 20px; text-decoration: none; border-radius: 5px;\">Shop Now</a></p><p>Best regards,<br/>The Marketing Team</p><p><a href=\"{{unsubscribe_url}}\">Unsubscribe</a></p></body></html>"
    text    = "Special Offer for {{name}}! Get {{discount}}% off {{product_name}}. Expires {{expiry_date}}. Shop: {{product_url}} Unsubscribe: {{unsubscribe_url}}"
  }
}

# Tags
variable "additional_tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}