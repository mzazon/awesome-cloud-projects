# =============================================================================
# Outputs for Edge-to-Cloud Video Analytics Infrastructure
# =============================================================================

# Project Information
output "project_id" {
  description = "The Google Cloud project ID where resources were created"
  value       = var.project_id
}

output "region" {
  description = "The Google Cloud region where resources were deployed"
  value       = var.region
}

output "deployment_id" {
  description = "Unique deployment identifier for this infrastructure"
  value       = random_id.suffix.hex
}

# Storage Information
output "video_content_bucket" {
  description = "Cloud Storage bucket for video content and CDN origin"
  value = {
    name         = google_storage_bucket.video_content.name
    url          = google_storage_bucket.video_content.url
    self_link    = google_storage_bucket.video_content.self_link
    location     = google_storage_bucket.video_content.location
    storage_class = google_storage_bucket.video_content.storage_class
  }
}

output "analytics_results_bucket" {
  description = "Cloud Storage bucket for analytics results and insights"
  value = {
    name         = google_storage_bucket.analytics_results.name
    url          = google_storage_bucket.analytics_results.url
    self_link    = google_storage_bucket.analytics_results.self_link
    location     = google_storage_bucket.analytics_results.location
    storage_class = google_storage_bucket.analytics_results.storage_class
  }
}

output "function_source_bucket" {
  description = "Cloud Storage bucket for function source code"
  value = {
    name      = google_storage_bucket.function_source.name
    url       = google_storage_bucket.function_source.url
    self_link = google_storage_bucket.function_source.self_link
  }
}

# Cloud Functions Information
output "cloud_functions" {
  description = "Information about deployed Cloud Functions"
  value = {
    video_processor = {
      name         = google_cloudfunctions2_function.video_processor.name
      url          = google_cloudfunctions2_function.video_processor.url
      state        = google_cloudfunctions2_function.video_processor.state
      update_time  = google_cloudfunctions2_function.video_processor.update_time
      service_config = {
        uri = google_cloudfunctions2_function.video_processor.service_config[0].uri
      }
    }
    
    advanced_analytics = {
      name         = google_cloudfunctions2_function.advanced_analytics.name
      url          = google_cloudfunctions2_function.advanced_analytics.url
      state        = google_cloudfunctions2_function.advanced_analytics.state
      update_time  = google_cloudfunctions2_function.advanced_analytics.update_time
      service_config = {
        uri = google_cloudfunctions2_function.advanced_analytics.service_config[0].uri
      }
    }
    
    results_processor = {
      name         = google_cloudfunctions2_function.results_processor.name
      url          = google_cloudfunctions2_function.results_processor.url
      state        = google_cloudfunctions2_function.results_processor.state
      update_time  = google_cloudfunctions2_function.results_processor.update_time
      service_config = {
        uri = google_cloudfunctions2_function.results_processor.service_config[0].uri
      }
    }
  }
  sensitive = false
}

# Service Accounts
output "service_accounts" {
  description = "Service accounts created for the video analytics platform"
  value = {
    function_service_account = {
      email        = google_service_account.function_sa.email
      unique_id    = google_service_account.function_sa.unique_id
      display_name = google_service_account.function_sa.display_name
    }
    
    vertex_ai_service_account = {
      email        = google_service_account.vertex_ai_sa.email
      unique_id    = google_service_account.vertex_ai_sa.unique_id
      display_name = google_service_account.vertex_ai_sa.display_name
    }
  }
}

# Vertex AI Resources
output "vertex_ai_dataset" {
  description = "Vertex AI dataset for video analytics"
  value = {
    name         = google_vertex_ai_dataset.video_dataset.name
    display_name = google_vertex_ai_dataset.video_dataset.display_name
    region       = google_vertex_ai_dataset.video_dataset.region
    create_time  = google_vertex_ai_dataset.video_dataset.create_time
    update_time  = google_vertex_ai_dataset.video_dataset.update_time
  }
}

# Media CDN Configuration
output "media_cdn" {
  description = "Media CDN configuration and endpoints"
  value = {
    backend_bucket = {
      name        = google_compute_backend_bucket.video_backend.name
      bucket_name = google_compute_backend_bucket.video_backend.bucket_name
      self_link   = google_compute_backend_bucket.video_backend.self_link
      enable_cdn  = google_compute_backend_bucket.video_backend.enable_cdn
    }
    
    url_map = {
      name      = google_compute_url_map.video_cdn.name
      self_link = google_compute_url_map.video_cdn.self_link
    }
    
    global_ip = {
      address   = google_compute_global_address.video_cdn_ip.address
      name      = google_compute_global_address.video_cdn_ip.name
      self_link = google_compute_global_address.video_cdn_ip.self_link
    }
    
    ssl_certificate = {
      name      = google_compute_managed_ssl_certificate.video_cdn_cert.name
      domains   = google_compute_managed_ssl_certificate.video_cdn_cert.managed[0].domains
      status    = google_compute_managed_ssl_certificate.video_cdn_cert.managed[0].status
    }
    
    https_proxy = {
      name      = google_compute_target_https_proxy.video_cdn_proxy.name
      self_link = google_compute_target_https_proxy.video_cdn_proxy.self_link
    }
    
    forwarding_rules = {
      https = {
        name       = google_compute_global_forwarding_rule.video_cdn_https.name
        ip_address = google_compute_global_forwarding_rule.video_cdn_https.ip_address
        port_range = google_compute_global_forwarding_rule.video_cdn_https.port_range
      }
      http = {
        name       = google_compute_global_forwarding_rule.video_cdn_http.name
        ip_address = google_compute_global_forwarding_rule.video_cdn_http.ip_address
        port_range = google_compute_global_forwarding_rule.video_cdn_http.port_range
      }
    }
  }
}

# Monitoring Configuration
output "monitoring" {
  description = "Cloud Monitoring configuration"
  value = var.enable_monitoring ? {
    notification_channels = var.notification_email != "" ? [{
      id           = google_monitoring_notification_channel.email[0].id
      display_name = google_monitoring_notification_channel.email[0].display_name
      type         = google_monitoring_notification_channel.email[0].type
    }] : []
    
    alert_policies = {
      function_failures = {
        id           = google_monitoring_alert_policy.function_failures[0].id
        display_name = google_monitoring_alert_policy.function_failures[0].display_name
        enabled      = google_monitoring_alert_policy.function_failures[0].enabled
      }
      
      storage_usage = {
        id           = google_monitoring_alert_policy.storage_usage[0].id
        display_name = google_monitoring_alert_policy.storage_usage[0].display_name
        enabled      = google_monitoring_alert_policy.storage_usage[0].enabled
      }
    }
  } : null
}

# API Services
output "enabled_apis" {
  description = "List of enabled Google Cloud APIs"
  value = [
    for api in google_project_service.required_apis : api.service
  ]
}

# Usage Instructions
output "usage_instructions" {
  description = "Instructions for using the video analytics platform"
  value = {
    video_upload = {
      description = "Upload videos to this bucket to trigger automatic processing"
      bucket_name = google_storage_bucket.video_content.name
      upload_command = "gsutil cp your-video.mp4 gs://${google_storage_bucket.video_content.name}/videos/"
    }
    
    results_access = {
      description = "Access analytics results from this bucket"
      bucket_name = google_storage_bucket.analytics_results.name
      list_command = "gsutil ls gs://${google_storage_bucket.analytics_results.name}/"
    }
    
    cdn_access = {
      description = "Access video content through the CDN"
      https_url = "https://${google_compute_global_address.video_cdn_ip.address}"
      domain_url = var.cdn_domain_name != "video-cdn.example.com" ? "https://${var.cdn_domain_name}" : null
      note = "Configure DNS to point ${var.cdn_domain_name} to ${google_compute_global_address.video_cdn_ip.address}"
    }
    
    monitoring = var.enable_monitoring ? {
      description = "Monitor function execution and system health"
      console_url = "https://console.cloud.google.com/monitoring/dashboards"
    } : null
  }
}

# Cost Estimation
output "cost_estimation" {
  description = "Estimated monthly costs for different usage patterns"
  value = {
    note = "Cost estimates are approximate and depend on actual usage"
    
    low_usage = {
      description = "10 videos/month, 1GB storage, minimal CDN usage"
      estimated_monthly_cost_usd = "15-25"
    }
    
    medium_usage = {
      description = "100 videos/month, 10GB storage, moderate CDN usage"
      estimated_monthly_cost_usd = "50-100"
    }
    
    high_usage = {
      description = "1000 videos/month, 100GB storage, high CDN usage"
      estimated_monthly_cost_usd = "200-500"
    }
    
    cost_factors = [
      "Cloud Storage usage and operations",
      "Cloud Functions execution time and invocations",
      "Vertex AI Video Intelligence API calls",
      "Media CDN bandwidth and requests",
      "Cloud Monitoring and logging"
    ]
  }
}

# Security Information
output "security_configuration" {
  description = "Security configuration summary"
  value = {
    bucket_security = {
      public_access_prevention = var.enable_public_access_prevention
      uniform_bucket_access   = var.enable_uniform_bucket_access
      encryption              = var.kms_key_id != "" ? "Customer-managed" : "Google-managed"
    }
    
    function_security = {
      service_account_email = google_service_account.function_sa.email
      ingress_settings     = "ALLOW_INTERNAL_ONLY"
      vpc_connector        = null
    }
    
    cdn_security = {
      https_enabled    = true
      ssl_certificate  = "Google-managed"
      http_redirect    = true
    }
  }
}

# Network Configuration
output "network_configuration" {
  description = "Network configuration details"
  value = {
    cdn_ip_address = google_compute_global_address.video_cdn_ip.address
    cdn_domain     = var.cdn_domain_name
    
    dns_configuration = {
      required_records = [
        {
          type  = "A"
          name  = var.cdn_domain_name
          value = google_compute_global_address.video_cdn_ip.address
        }
      ]
    }
    
    firewall_rules = "Default Google Cloud security policies applied"
  }
}

# Resource Summary
output "resource_summary" {
  description = "Summary of created resources"
  value = {
    storage_buckets    = 3
    cloud_functions    = 3
    service_accounts   = 2
    vertex_ai_datasets = 1
    cdn_components     = 7
    monitoring_alerts  = var.enable_monitoring ? 2 : 0
    
    total_estimated_resources = 18 + (var.enable_monitoring ? 3 : 0)
  }
}

# Validation and Health Checks
output "validation_commands" {
  description = "Commands to validate the deployment"
  value = {
    check_buckets = "gsutil ls gs://${google_storage_bucket.video_content.name} && gsutil ls gs://${google_storage_bucket.analytics_results.name}"
    
    check_functions = "gcloud functions list --filter='name:*${random_id.suffix.hex}*' --format='table(name,status,httpsTrigger.url)'"
    
    check_vertex_ai = "gcloud ai datasets list --region=${var.vertex_ai_region} --filter='displayName:*${random_id.suffix.hex}*'"
    
    check_cdn = "curl -I https://${google_compute_global_address.video_cdn_ip.address}"
    
    test_upload = "echo 'Test video upload:' && gsutil cp test-video.mp4 gs://${google_storage_bucket.video_content.name}/test/"
  }
}

# Troubleshooting Information
output "troubleshooting" {
  description = "Common troubleshooting steps and useful commands"
  value = {
    function_logs = "gcloud functions logs read FUNCTION_NAME --limit=50"
    
    storage_permissions = "gsutil iam get gs://${google_storage_bucket.video_content.name}"
    
    cdn_cache_status = "Check cache status by examining response headers: curl -I https://${google_compute_global_address.video_cdn_ip.address}/path/to/video"
    
    vertex_ai_jobs = "gcloud ai operations list --region=${var.vertex_ai_region}"
    
    monitoring_metrics = "View metrics at: https://console.cloud.google.com/monitoring/metrics-explorer"
    
    common_issues = [
      "Ensure proper IAM permissions for service accounts",
      "Verify API enablement for all required services",
      "Check quota limits for Vertex AI and Cloud Functions",
      "Confirm DNS configuration for custom CDN domain",
      "Validate function source code deployment"
    ]
  }
}