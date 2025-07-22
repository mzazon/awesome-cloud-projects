# Variables for Azure Web Application Performance Optimization
# This file defines all configurable parameters for the infrastructure deployment

# Basic Configuration Variables
variable "location" {
  description = "The Azure region where resources will be deployed"
  type        = string
  default     = "East US"
  
  validation {
    condition = contains([
      "East US", "East US 2", "West US", "West US 2", "West US 3",
      "Central US", "North Central US", "South Central US", "West Central US",
      "Canada Central", "Canada East", "Brazil South", "UK South", "UK West",
      "North Europe", "West Europe", "France Central", "Germany West Central",
      "Switzerland North", "Norway East", "Sweden Central", "Poland Central",
      "Italy North", "Spain Central", "Denmark East", "Finland Central",
      "Austria East", "Belgium Central", "Czech Republic Central", "Greece Central",
      "Hungary Central", "Latvia Central", "Lithuania Central", "Luxembourg Central",
      "Portugal Central", "Romania Central", "Slovakia Central", "Slovenia Central",
      "Estonia Central", "Croatia Central", "Bulgaria Central", "Serbia Central",
      "Montenegro Central", "Albania Central", "North Macedonia Central",
      "Bosnia and Herzegovina Central", "Moldova Central", "Georgia Central",
      "Armenia Central", "Azerbaijan Central", "Kazakhstan Central", "Kyrgyzstan Central",
      "Tajikistan Central", "Turkmenistan Central", "Uzbekistan Central", "Afghanistan Central",
      "Pakistan Central", "India Central", "India West", "India South", "Sri Lanka Central",
      "Nepal Central", "Bhutan Central", "Bangladesh Central", "Myanmar Central",
      "Thailand Central", "Laos Central", "Vietnam Central", "Cambodia Central",
      "Malaysia Central", "Singapore Central", "Brunei Central", "Philippines Central",
      "Indonesia Central", "East Timor Central", "Papua New Guinea Central", "Solomon Islands Central",
      "Vanuatu Central", "New Caledonia Central", "Fiji Central", "Samoa Central",
      "Tonga Central", "Tuvalu Central", "Kiribati Central", "Marshall Islands Central",
      "Micronesia Central", "Palau Central", "Nauru Central", "Australia East",
      "Australia Southeast", "Australia Central", "Australia Central 2", "New Zealand North",
      "Japan East", "Japan West", "Korea Central", "Korea South", "Taiwan Central",
      "Hong Kong Central", "Macao Central", "Mongolia Central", "China North",
      "China East", "China South", "China West", "Russia Central", "Russia East",
      "Russia West", "Russia North", "Russia South", "Alaska Central", "Hawaii Central",
      "Greenland Central", "Iceland Central", "Faroe Islands Central", "Jan Mayen Central",
      "Svalbard Central", "Franz Josef Land Central", "Novaya Zemlya Central", "Wrangel Island Central",
      "Chukotka Central", "Kamchatka Central", "Sakhalin Central", "Kuril Islands Central",
      "South Africa North", "South Africa West", "UAE North", "UAE Central",
      "Qatar Central", "Bahrain Central", "Kuwait Central", "Oman Central",
      "Saudi Arabia Central", "Yemen Central", "Israel Central", "Jordan Central",
      "Lebanon Central", "Syria Central", "Turkey Central", "Cyprus Central",
      "Egypt Central", "Libya Central", "Tunisia Central", "Algeria Central",
      "Morocco Central", "Western Sahara Central", "Mauritania Central", "Mali Central",
      "Niger Central", "Chad Central", "Sudan Central", "South Sudan Central",
      "Ethiopia Central", "Eritrea Central", "Djibouti Central", "Somalia Central",
      "Kenya Central", "Uganda Central", "Tanzania Central", "Rwanda Central",
      "Burundi Central", "Democratic Republic of Congo Central", "Central African Republic Central",
      "Cameroon Central", "Equatorial Guinea Central", "Gabon Central", "Republic of Congo Central",
      "Angola Central", "Zambia Central", "Zimbabwe Central", "Botswana Central",
      "Namibia Central", "Lesotho Central", "Swaziland Central", "Mozambique Central",
      "Malawi Central", "Madagascar Central", "Mauritius Central", "Reunion Central",
      "Seychelles Central", "Comoros Central", "Mayotte Central", "Saint Helena Central",
      "Ascension Central", "Tristan da Cunha Central", "Falkland Islands Central", "South Georgia Central",
      "Bouvet Island Central", "Heard Island Central", "McDonald Islands Central", "Kerguelen Islands Central",
      "Crozet Islands Central", "Prince Edward Islands Central", "Gough Island Central", "Inaccessible Island Central",
      "Nightingale Island Central", "Tristan da Cunha Central", "Antarctica Central"
    ], var.location)
    error_message = "Location must be a valid Azure region."
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
  description = "Name of the project used for resource naming"
  type        = string
  default     = "webapp-perf"
  
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.project_name))
    error_message = "Project name must contain only lowercase letters, numbers, and hyphens."
  }
}

# App Service Configuration
variable "app_service_plan_sku" {
  description = "SKU for the App Service Plan"
  type        = string
  default     = "S1"
  
  validation {
    condition = contains([
      "B1", "B2", "B3",           # Basic tier
      "S1", "S2", "S3",           # Standard tier
      "P1", "P2", "P3",           # Premium tier
      "P1V2", "P2V2", "P3V2",     # Premium V2 tier
      "P1V3", "P2V3", "P3V3"      # Premium V3 tier
    ], var.app_service_plan_sku)
    error_message = "App Service Plan SKU must be a valid Azure App Service Plan tier."
  }
}

variable "app_service_always_on" {
  description = "Should the App Service always be on?"
  type        = bool
  default     = true
}

variable "app_service_runtime_stack" {
  description = "Runtime stack for the App Service"
  type        = string
  default     = "NODE|18-lts"
  
  validation {
    condition = contains([
      "NODE|14-lts", "NODE|16-lts", "NODE|18-lts", "NODE|20-lts",
      "PYTHON|3.8", "PYTHON|3.9", "PYTHON|3.10", "PYTHON|3.11",
      "DOTNETCORE|6.0", "DOTNETCORE|7.0", "DOTNETCORE|8.0",
      "JAVA|8", "JAVA|11", "JAVA|17", "JAVA|21",
      "PHP|8.0", "PHP|8.1", "PHP|8.2"
    ], var.app_service_runtime_stack)
    error_message = "Runtime stack must be a valid Azure App Service runtime."
  }
}

# Redis Cache Configuration
variable "redis_cache_sku" {
  description = "SKU for Redis Cache"
  type        = string
  default     = "Standard"
  
  validation {
    condition     = contains(["Basic", "Standard", "Premium"], var.redis_cache_sku)
    error_message = "Redis Cache SKU must be Basic, Standard, or Premium."
  }
}

variable "redis_cache_size" {
  description = "Size of Redis Cache"
  type        = string
  default     = "C1"
  
  validation {
    condition = contains([
      "C0", "C1", "C2", "C3", "C4", "C5", "C6",  # Basic/Standard sizes
      "P1", "P2", "P3", "P4", "P5"               # Premium sizes
    ], var.redis_cache_size)
    error_message = "Redis Cache size must be a valid Azure Redis Cache size."
  }
}

variable "redis_enable_non_ssl_port" {
  description = "Enable non-SSL port for Redis Cache"
  type        = bool
  default     = false
}

variable "redis_maxmemory_policy" {
  description = "Maxmemory policy for Redis Cache"
  type        = string
  default     = "allkeys-lru"
  
  validation {
    condition = contains([
      "allkeys-lru", "allkeys-lfu", "allkeys-random",
      "volatile-lru", "volatile-lfu", "volatile-random",
      "volatile-ttl", "noeviction"
    ], var.redis_maxmemory_policy)
    error_message = "Redis maxmemory policy must be a valid Redis eviction policy."
  }
}

# CDN Configuration
variable "cdn_profile_sku" {
  description = "SKU for CDN Profile"
  type        = string
  default     = "Standard_Microsoft"
  
  validation {
    condition = contains([
      "Standard_Akamai", "Standard_Microsoft", "Standard_Verizon",
      "Premium_Verizon", "Standard_ChinaCdn", "Standard_955BandWidth_ChinaCdn"
    ], var.cdn_profile_sku)
    error_message = "CDN Profile SKU must be a valid Azure CDN SKU."
  }
}

variable "cdn_enable_compression" {
  description = "Enable compression for CDN endpoint"
  type        = bool
  default     = true
}

variable "cdn_query_string_caching" {
  description = "Query string caching behavior for CDN"
  type        = string
  default     = "IgnoreQueryString"
  
  validation {
    condition = contains([
      "IgnoreQueryString", "BypassCaching", "UseQueryString"
    ], var.cdn_query_string_caching)
    error_message = "CDN query string caching must be a valid caching behavior."
  }
}

# Database Configuration
variable "postgresql_version" {
  description = "PostgreSQL version"
  type        = string
  default     = "13"
  
  validation {
    condition     = contains(["11", "12", "13", "14", "15"], var.postgresql_version)
    error_message = "PostgreSQL version must be a supported version."
  }
}

variable "postgresql_sku_name" {
  description = "SKU name for PostgreSQL Flexible Server"
  type        = string
  default     = "B_Standard_B1ms"
  
  validation {
    condition = can(regex("^[BDM]_", var.postgresql_sku_name))
    error_message = "PostgreSQL SKU name must start with B_, D_, or M_ for different tiers."
  }
}

variable "postgresql_storage_mb" {
  description = "Storage size in MB for PostgreSQL"
  type        = number
  default     = 32768
  
  validation {
    condition     = var.postgresql_storage_mb >= 32768 && var.postgresql_storage_mb <= 16777216
    error_message = "PostgreSQL storage must be between 32768 MB (32 GB) and 16777216 MB (16 TB)."
  }
}

variable "postgresql_admin_username" {
  description = "Administrator username for PostgreSQL"
  type        = string
  default     = "dbadmin"
  
  validation {
    condition     = can(regex("^[a-zA-Z][a-zA-Z0-9_]{2,62}$", var.postgresql_admin_username))
    error_message = "PostgreSQL admin username must be 3-63 characters, start with a letter, and contain only letters, numbers, and underscores."
  }
}

variable "postgresql_admin_password" {
  description = "Administrator password for PostgreSQL"
  type        = string
  default     = "P@ssw0rd123!"
  sensitive   = true
  
  validation {
    condition     = length(var.postgresql_admin_password) >= 8 && length(var.postgresql_admin_password) <= 128
    error_message = "PostgreSQL admin password must be between 8 and 128 characters."
  }
}

variable "database_name" {
  description = "Name of the database to create"
  type        = string
  default     = "ecommerce_db"
  
  validation {
    condition     = can(regex("^[a-zA-Z][a-zA-Z0-9_]{0,62}$", var.database_name))
    error_message = "Database name must be 1-63 characters, start with a letter, and contain only letters, numbers, and underscores."
  }
}

# Application Insights Configuration
variable "application_insights_type" {
  description = "Application type for Application Insights"
  type        = string
  default     = "web"
  
  validation {
    condition     = contains(["web", "other"], var.application_insights_type)
    error_message = "Application Insights type must be 'web' or 'other'."
  }
}

# Tagging Configuration
variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default = {
    Environment = "dev"
    Project     = "webapp-performance"
    Purpose     = "performance-demo"
    ManagedBy   = "terraform"
  }
}

# Resource Naming Configuration
variable "resource_name_prefix" {
  description = "Prefix for all resource names"
  type        = string
  default     = ""
  
  validation {
    condition     = can(regex("^[a-z0-9-]*$", var.resource_name_prefix))
    error_message = "Resource name prefix must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "resource_name_suffix" {
  description = "Suffix for all resource names"
  type        = string
  default     = ""
  
  validation {
    condition     = can(regex("^[a-z0-9-]*$", var.resource_name_suffix))
    error_message = "Resource name suffix must contain only lowercase letters, numbers, and hyphens."
  }
}

# Networking Configuration
variable "allowed_ip_addresses" {
  description = "List of IP addresses allowed to access the database"
  type        = list(string)
  default     = ["0.0.0.0"]
  
  validation {
    condition = alltrue([
      for ip in var.allowed_ip_addresses : can(regex("^\\d{1,3}\\.\\d{1,3}\\.\\d{1,3}\\.\\d{1,3}$", ip))
    ])
    error_message = "All IP addresses must be valid IPv4 addresses."
  }
}

# Log Analytics Configuration
variable "log_analytics_retention_days" {
  description = "Number of days to retain logs in Log Analytics"
  type        = number
  default     = 30
  
  validation {
    condition     = var.log_analytics_retention_days >= 30 && var.log_analytics_retention_days <= 730
    error_message = "Log Analytics retention must be between 30 and 730 days."
  }
}

# Monitoring Configuration
variable "enable_monitoring" {
  description = "Enable Application Insights monitoring"
  type        = bool
  default     = true
}

variable "enable_diagnostic_logs" {
  description = "Enable diagnostic logging for resources"
  type        = bool
  default     = true
}

# Security Configuration
variable "enable_https_only" {
  description = "Enable HTTPS only for App Service"
  type        = bool
  default     = true
}

variable "min_tls_version" {
  description = "Minimum TLS version for App Service"
  type        = string
  default     = "1.2"
  
  validation {
    condition     = contains(["1.0", "1.1", "1.2"], var.min_tls_version)
    error_message = "Minimum TLS version must be 1.0, 1.1, or 1.2."
  }
}