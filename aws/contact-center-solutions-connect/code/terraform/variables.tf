# Variable definitions for Amazon Connect contact center infrastructure
# These variables allow customization of the contact center deployment

variable "environment" {
  description = "Environment name for resource naming and tagging"
  type        = string
  default     = "production"
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.environment))
    error_message = "Environment must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "connect_instance_alias" {
  description = "Unique alias for the Amazon Connect instance"
  type        = string
  default     = ""
  validation {
    condition     = can(regex("^[a-zA-Z0-9-]+$", var.connect_instance_alias)) || var.connect_instance_alias == ""
    error_message = "Connect instance alias must contain only alphanumeric characters and hyphens."
  }
}

variable "s3_bucket_prefix" {
  description = "Prefix for S3 bucket name (account ID will be appended)"
  type        = string
  default     = "connect-recordings"
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.s3_bucket_prefix))
    error_message = "S3 bucket prefix must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "enable_inbound_calls" {
  description = "Enable inbound calling for the Connect instance"
  type        = bool
  default     = true
}

variable "enable_outbound_calls" {
  description = "Enable outbound calling for the Connect instance"
  type        = bool
  default     = true
}

variable "enable_contact_lens" {
  description = "Enable Contact Lens for Amazon Connect (AI-powered analytics)"
  type        = bool
  default     = true
}

variable "enable_contact_flow_logs" {
  description = "Enable contact flow logging to CloudWatch"
  type        = bool
  default     = true
}

variable "admin_user_config" {
  description = "Configuration for the administrative user"
  type = object({
    username   = string
    first_name = string
    last_name  = string
    password   = string
  })
  default = {
    username   = "connect-admin"
    first_name = "Connect"
    last_name  = "Administrator"
    password   = "TempPass123!"
  }
  validation {
    condition     = length(var.admin_user_config.password) >= 8
    error_message = "Password must be at least 8 characters long."
  }
}

variable "agent_user_config" {
  description = "Configuration for the agent user"
  type = object({
    username   = string
    first_name = string
    last_name  = string
    password   = string
  })
  default = {
    username   = "service-agent-01"
    first_name = "Service"
    last_name  = "Agent"
    password   = "AgentPass123!"
  }
  validation {
    condition     = length(var.agent_user_config.password) >= 8
    error_message = "Password must be at least 8 characters long."
  }
}

variable "queue_config" {
  description = "Configuration for the customer service queue"
  type = object({
    name         = string
    description  = string
    max_contacts = number
  })
  default = {
    name         = "CustomerService"
    description  = "Main customer service queue for general inquiries"
    max_contacts = 50
  }
  validation {
    condition     = var.queue_config.max_contacts > 0 && var.queue_config.max_contacts <= 1000
    error_message = "Queue max_contacts must be between 1 and 1000."
  }
}

variable "contact_flow_config" {
  description = "Configuration for the contact flow"
  type = object({
    name        = string
    description = string
    type        = string
  })
  default = {
    name        = "CustomerServiceFlow"
    description = "Main customer service contact flow with recording"
    type        = "CONTACT_FLOW"
  }
}

variable "phone_config" {
  description = "Configuration for phone number claiming"
  type = object({
    enabled           = bool
    country_code      = string
    phone_number_type = string
    description       = string
  })
  default = {
    enabled           = true
    country_code      = "US"
    phone_number_type = "TOLL_FREE"
    description       = "Main customer service line"
  }
}

variable "routing_profile_config" {
  description = "Configuration for agent routing profile"
  type = object({
    name                       = string
    description                = string
    voice_concurrency          = number
    after_contact_work_timeout = number
    auto_accept                = bool
  })
  default = {
    name                       = "CustomerServiceAgents"
    description                = "Routing profile for customer service representatives"
    voice_concurrency          = 1
    after_contact_work_timeout = 180
    auto_accept                = true
  }
}

variable "cloudwatch_dashboard_config" {
  description = "Configuration for CloudWatch dashboard"
  type = object({
    enabled = bool
    name    = string
  })
  default = {
    enabled = true
    name    = "ConnectContactCenter"
  }
}

variable "s3_lifecycle_config" {
  description = "S3 lifecycle configuration for call recordings"
  type = object({
    enabled                       = bool
    transition_to_ia_days         = number
    transition_to_glacier_days    = number
    expiration_days               = number
  })
  default = {
    enabled                       = true
    transition_to_ia_days         = 30
    transition_to_glacier_days    = 90
    expiration_days               = 2555  # 7 years for compliance
  }
}

variable "additional_tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}