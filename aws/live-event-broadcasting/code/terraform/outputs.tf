# ==========================================
# MediaConnect Outputs
# ==========================================

output "primary_flow_arn" {
  description = "ARN of the primary MediaConnect flow"
  value       = aws_media_connect_flow.primary_flow.arn
}

output "primary_flow_name" {
  description = "Name of the primary MediaConnect flow"
  value       = aws_media_connect_flow.primary_flow.name
}

output "primary_flow_ingest_ip" {
  description = "Ingest IP address for the primary MediaConnect flow"
  value       = aws_media_connect_flow.primary_flow.source[0].ingest_ip
}

output "primary_flow_ingest_port" {
  description = "Ingest port for the primary MediaConnect flow"
  value       = aws_media_connect_flow.primary_flow.source[0].ingest_port
}

output "primary_flow_ingest_endpoint" {
  description = "Complete ingest endpoint for the primary MediaConnect flow"
  value       = "${aws_media_connect_flow.primary_flow.source[0].ingest_ip}:${aws_media_connect_flow.primary_flow.source[0].ingest_port}"
}

output "backup_flow_arn" {
  description = "ARN of the backup MediaConnect flow"
  value       = aws_media_connect_flow.backup_flow.arn
}

output "backup_flow_name" {
  description = "Name of the backup MediaConnect flow"
  value       = aws_media_connect_flow.backup_flow.name
}

output "backup_flow_ingest_ip" {
  description = "Ingest IP address for the backup MediaConnect flow"
  value       = aws_media_connect_flow.backup_flow.source[0].ingest_ip
}

output "backup_flow_ingest_port" {
  description = "Ingest port for the backup MediaConnect flow"
  value       = aws_media_connect_flow.backup_flow.source[0].ingest_port
}

output "backup_flow_ingest_endpoint" {
  description = "Complete ingest endpoint for the backup MediaConnect flow"
  value       = "${aws_media_connect_flow.backup_flow.source[0].ingest_ip}:${aws_media_connect_flow.backup_flow.source[0].ingest_port}"
}

# ==========================================
# MediaLive Outputs
# ==========================================

output "medialive_channel_id" {
  description = "ID of the MediaLive channel"
  value       = aws_medialive_channel.live_channel.channel_id
}

output "medialive_channel_name" {
  description = "Name of the MediaLive channel"
  value       = aws_medialive_channel.live_channel.name
}

output "medialive_channel_arn" {
  description = "ARN of the MediaLive channel"
  value       = aws_medialive_channel.live_channel.arn
}

output "medialive_channel_state" {
  description = "Current state of the MediaLive channel"
  value       = aws_medialive_channel.live_channel.state
}

output "primary_input_id" {
  description = "ID of the primary MediaLive input"
  value       = aws_medialive_input.primary_input.id
}

output "backup_input_id" {
  description = "ID of the backup MediaLive input"
  value       = aws_medialive_input.backup_input.id
}

# ==========================================
# MediaPackage Outputs
# ==========================================

output "mediapackage_channel_id" {
  description = "ID of the MediaPackage channel"
  value       = aws_media_package_channel.live_channel.channel_id
}

output "mediapackage_channel_arn" {
  description = "ARN of the MediaPackage channel"
  value       = aws_media_package_channel.live_channel.arn
}

output "mediapackage_hls_endpoint_id" {
  description = "ID of the MediaPackage HLS endpoint"
  value       = aws_media_package_origin_endpoint.hls_endpoint.endpoint_id
}

output "mediapackage_hls_endpoint_url" {
  description = "URL of the MediaPackage HLS endpoint for playback"
  value       = aws_media_package_origin_endpoint.hls_endpoint.url
}

output "mediapackage_ingest_endpoints" {
  description = "MediaPackage ingest endpoints for MediaLive"
  value = {
    primary = {
      url      = aws_media_package_channel.live_channel.hls_ingest[0].ingest_endpoints[0].url
      username = aws_media_package_channel.live_channel.hls_ingest[0].ingest_endpoints[0].username
      # Note: Password is sensitive and not exposed
    }
    backup = {
      url      = aws_media_package_channel.live_channel.hls_ingest[0].ingest_endpoints[1].url
      username = aws_media_package_channel.live_channel.hls_ingest[0].ingest_endpoints[1].username
      # Note: Password is sensitive and not exposed
    }
  }
}

# ==========================================
# IAM Outputs
# ==========================================

output "medialive_role_arn" {
  description = "ARN of the MediaLive IAM role"
  value       = aws_iam_role.medialive_role.arn
}

output "medialive_role_name" {
  description = "Name of the MediaLive IAM role"
  value       = aws_iam_role.medialive_role.name
}

# ==========================================
# CloudWatch Outputs
# ==========================================

output "cloudwatch_alarms" {
  description = "Names of the CloudWatch alarms created for monitoring"
  value = {
    primary_flow_errors = aws_cloudwatch_metric_alarm.primary_flow_source_errors.alarm_name
    backup_flow_errors  = aws_cloudwatch_metric_alarm.backup_flow_source_errors.alarm_name
    medialive_input_errors = aws_cloudwatch_metric_alarm.medialive_input_errors.alarm_name
  }
}

output "cloudwatch_log_groups" {
  description = "Names of the CloudWatch log groups created"
  value = {
    primary_flow_logs = aws_cloudwatch_log_group.primary_flow_logs.name
    backup_flow_logs  = aws_cloudwatch_log_group.backup_flow_logs.name
  }
}

# ==========================================
# Encoder Configuration Outputs
# ==========================================

output "encoder_configuration" {
  description = "Configuration summary for video encoders"
  value = {
    primary_encoder = {
      target_ip   = aws_media_connect_flow.primary_flow.source[0].ingest_ip
      target_port = aws_media_connect_flow.primary_flow.source[0].ingest_port
      protocol    = "RTP"
      description = "Send primary video feed to this endpoint"
    }
    backup_encoder = {
      target_ip   = aws_media_connect_flow.backup_flow.source[0].ingest_ip
      target_port = aws_media_connect_flow.backup_flow.source[0].ingest_port
      protocol    = "RTP"
      description = "Send backup video feed to this endpoint"
    }
  }
}

# ==========================================
# System Status Outputs
# ==========================================

output "broadcasting_pipeline_status" {
  description = "Status summary of the broadcasting pipeline"
  value = {
    primary_flow_state    = aws_media_connect_flow.primary_flow.status
    backup_flow_state     = aws_media_connect_flow.backup_flow.status
    medialive_channel_state = aws_medialive_channel.live_channel.state
    mediapackage_channel_state = aws_media_package_channel.live_channel.id
    hls_playback_ready    = aws_media_package_origin_endpoint.hls_endpoint.url != "" ? true : false
  }
}

# ==========================================
# Quick Start Information
# ==========================================

output "quick_start_guide" {
  description = "Quick start information for using the broadcasting pipeline"
  value = {
    step_1_encoder_setup = "Configure your encoders to send RTP streams to the provided ingest endpoints"
    step_2_start_flows = "Start MediaConnect flows: aws mediaconnect start-flow --flow-arn <flow-arn>"
    step_3_start_channel = "Start MediaLive channel: aws medialive start-channel --channel-id ${aws_medialive_channel.live_channel.channel_id}"
    step_4_test_playback = "Test HLS playback URL: ${aws_media_package_origin_endpoint.hls_endpoint.url}"
    step_5_monitoring = "Monitor CloudWatch alarms and metrics for pipeline health"
  }
}

# ==========================================
# Resource Summary
# ==========================================

output "resource_summary" {
  description = "Summary of all resources created"
  value = {
    mediaconnect_flows = [
      aws_media_connect_flow.primary_flow.name,
      aws_media_connect_flow.backup_flow.name
    ]
    medialive_channel = aws_medialive_channel.live_channel.name
    medialive_inputs = [
      aws_medialive_input.primary_input.name,
      aws_medialive_input.backup_input.name
    ]
    mediapackage_channel = aws_media_package_channel.live_channel.channel_id
    mediapackage_endpoint = aws_media_package_origin_endpoint.hls_endpoint.endpoint_id
    iam_role = aws_iam_role.medialive_role.name
    cloudwatch_alarms = length([
      aws_cloudwatch_metric_alarm.primary_flow_source_errors.alarm_name,
      aws_cloudwatch_metric_alarm.backup_flow_source_errors.alarm_name,
      aws_cloudwatch_metric_alarm.medialive_input_errors.alarm_name
    ])
    cloudwatch_log_groups = length([
      aws_cloudwatch_log_group.primary_flow_logs.name,
      aws_cloudwatch_log_group.backup_flow_logs.name
    ])
  }
}

# ==========================================
# Cost Tracking Outputs
# ==========================================

output "cost_tracking_tags" {
  description = "Tags applied to resources for cost tracking"
  value = {
    project     = local.common_tags.Project
    environment = local.common_tags.Environment
    recipe      = local.common_tags.Recipe
    created_by  = local.common_tags.CreatedBy
  }
}

# ==========================================
# Security Information
# ==========================================

output "security_considerations" {
  description = "Security settings and recommendations"
  value = {
    flow_encryption_enabled = var.enable_flow_source_encryption
    ingest_whitelist_cidrs = var.mediaconnect_ingest_whitelist_cidrs
    iam_role_principle_of_least_privilege = "MediaLive role has minimal required permissions"
    recommended_actions = [
      "Review and restrict ingest CIDR blocks to known encoder IPs",
      "Enable CloudTrail logging for API calls",
      "Consider enabling AWS Config for compliance monitoring",
      "Implement CloudWatch alerts for security events"
    ]
  }
}