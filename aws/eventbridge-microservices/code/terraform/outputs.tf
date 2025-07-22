# Outputs for Event-Driven Architecture with Amazon EventBridge

#------------------------------------------------------------------------------
# EventBridge Outputs
#------------------------------------------------------------------------------

output "custom_event_bus_name" {
  description = "Name of the custom EventBridge event bus"
  value       = aws_cloudwatch_event_bus.ecommerce_bus.name
}

output "custom_event_bus_arn" {
  description = "ARN of the custom EventBridge event bus"
  value       = aws_cloudwatch_event_bus.ecommerce_bus.arn
}

output "event_bus_source_names" {
  description = "List of event sources configured for the custom event bus"
  value = [
    "ecommerce.api",
    "ecommerce.order",
    "ecommerce.inventory"
  ]
}

#------------------------------------------------------------------------------
# EventBridge Rules Outputs
#------------------------------------------------------------------------------

output "eventbridge_rules" {
  description = "Information about all EventBridge rules"
  value = {
    order_processing = {
      name        = aws_cloudwatch_event_rule.order_processing_rule.name
      arn         = aws_cloudwatch_event_rule.order_processing_rule.arn
      description = aws_cloudwatch_event_rule.order_processing_rule.description
      state       = aws_cloudwatch_event_rule.order_processing_rule.state
    }
    inventory_check = {
      name        = aws_cloudwatch_event_rule.inventory_check_rule.name
      arn         = aws_cloudwatch_event_rule.inventory_check_rule.arn
      description = aws_cloudwatch_event_rule.inventory_check_rule.description
      state       = aws_cloudwatch_event_rule.inventory_check_rule.state
    }
    payment_processing = {
      name        = aws_cloudwatch_event_rule.payment_processing_rule.name
      arn         = aws_cloudwatch_event_rule.payment_processing_rule.arn
      description = aws_cloudwatch_event_rule.payment_processing_rule.description
      state       = aws_cloudwatch_event_rule.payment_processing_rule.state
    }
    monitoring = {
      name        = aws_cloudwatch_event_rule.monitoring_rule.name
      arn         = aws_cloudwatch_event_rule.monitoring_rule.arn
      description = aws_cloudwatch_event_rule.monitoring_rule.description
      state       = aws_cloudwatch_event_rule.monitoring_rule.state
    }
  }
}

#------------------------------------------------------------------------------
# Lambda Function Outputs
#------------------------------------------------------------------------------

output "lambda_functions" {
  description = "Information about all Lambda functions"
  value = {
    order_processor = {
      function_name = aws_lambda_function.order_processor.function_name
      arn          = aws_lambda_function.order_processor.arn
      invoke_arn   = aws_lambda_function.order_processor.invoke_arn
      runtime      = aws_lambda_function.order_processor.runtime
      handler      = aws_lambda_function.order_processor.handler
      timeout      = aws_lambda_function.order_processor.timeout
    }
    inventory_manager = {
      function_name = aws_lambda_function.inventory_manager.function_name
      arn          = aws_lambda_function.inventory_manager.arn
      invoke_arn   = aws_lambda_function.inventory_manager.invoke_arn
      runtime      = aws_lambda_function.inventory_manager.runtime
      handler      = aws_lambda_function.inventory_manager.handler
      timeout      = aws_lambda_function.inventory_manager.timeout
    }
    event_generator = {
      function_name = aws_lambda_function.event_generator.function_name
      arn          = aws_lambda_function.event_generator.arn
      invoke_arn   = aws_lambda_function.event_generator.invoke_arn
      runtime      = aws_lambda_function.event_generator.runtime
      handler      = aws_lambda_function.event_generator.handler
      timeout      = aws_lambda_function.event_generator.timeout
    }
  }
}

output "lambda_function_names" {
  description = "List of Lambda function names for easy reference"
  value = [
    aws_lambda_function.order_processor.function_name,
    aws_lambda_function.inventory_manager.function_name,
    aws_lambda_function.event_generator.function_name
  ]
}

#------------------------------------------------------------------------------
# IAM Outputs
#------------------------------------------------------------------------------

output "lambda_execution_role_arn" {
  description = "ARN of the Lambda execution role"
  value       = aws_iam_role.lambda_execution_role.arn
}

output "lambda_execution_role_name" {
  description = "Name of the Lambda execution role"
  value       = aws_iam_role.lambda_execution_role.name
}

#------------------------------------------------------------------------------
# SQS Outputs
#------------------------------------------------------------------------------

output "payment_queue_url" {
  description = "URL of the payment processing SQS queue"
  value       = aws_sqs_queue.payment_processing.url
}

output "payment_queue_arn" {
  description = "ARN of the payment processing SQS queue"
  value       = aws_sqs_queue.payment_processing.arn
}

output "payment_queue_name" {
  description = "Name of the payment processing SQS queue"
  value       = aws_sqs_queue.payment_processing.name
}

#------------------------------------------------------------------------------
# CloudWatch Logs Outputs
#------------------------------------------------------------------------------

output "cloudwatch_log_groups" {
  description = "Information about all CloudWatch log groups"
  value = {
    order_processor = {
      name              = aws_cloudwatch_log_group.order_processor_logs.name
      arn              = aws_cloudwatch_log_group.order_processor_logs.arn
      retention_days   = aws_cloudwatch_log_group.order_processor_logs.retention_in_days
    }
    inventory_manager = {
      name              = aws_cloudwatch_log_group.inventory_manager_logs.name
      arn              = aws_cloudwatch_log_group.inventory_manager_logs.arn
      retention_days   = aws_cloudwatch_log_group.inventory_manager_logs.retention_in_days
    }
    event_generator = {
      name              = aws_cloudwatch_log_group.event_generator_logs.name
      arn              = aws_cloudwatch_log_group.event_generator_logs.arn
      retention_days   = aws_cloudwatch_log_group.event_generator_logs.retention_in_days
    }
    eventbridge_monitoring = {
      name              = aws_cloudwatch_log_group.eventbridge_logs.name
      arn              = aws_cloudwatch_log_group.eventbridge_logs.arn
      retention_days   = aws_cloudwatch_log_group.eventbridge_logs.retention_in_days
    }
  }
}

#------------------------------------------------------------------------------
# Monitoring and Testing Outputs
#------------------------------------------------------------------------------

output "monitoring_endpoints" {
  description = "CloudWatch monitoring endpoints and dashboards"
  value = {
    eventbridge_metrics = "https://console.aws.amazon.com/cloudwatch/home?region=${data.aws_region.current.name}#metricsV2:graph=~();query=AWS%2FEvents"
    lambda_metrics     = "https://console.aws.amazon.com/cloudwatch/home?region=${data.aws_region.current.name}#metricsV2:graph=~();query=AWS%2FLambda"
    sqs_metrics       = "https://console.aws.amazon.com/cloudwatch/home?region=${data.aws_region.current.name}#metricsV2:graph=~();query=AWS%2FSQS"
    log_groups        = "https://console.aws.amazon.com/cloudwatch/home?region=${data.aws_region.current.name}#logsV2:log-groups"
  }
}

output "testing_commands" {
  description = "AWS CLI commands for testing the event-driven architecture"
  value = {
    generate_test_event = "aws lambda invoke --function-name ${aws_lambda_function.event_generator.function_name} --payload '{}' --cli-binary-format raw-in-base64-out response.json"
    check_order_logs   = "aws logs describe-log-streams --log-group-name ${aws_cloudwatch_log_group.order_processor_logs.name} --order-by LastEventTime --descending --max-items 1"
    check_inventory_logs = "aws logs describe-log-streams --log-group-name ${aws_cloudwatch_log_group.inventory_manager_logs.name} --order-by LastEventTime --descending --max-items 1"
    check_payment_queue = "aws sqs receive-message --queue-url ${aws_sqs_queue.payment_processing.url} --max-number-of-messages 5"
    list_event_buses   = "aws events list-event-buses"
    list_rules        = "aws events list-rules --event-bus-name ${aws_cloudwatch_event_bus.ecommerce_bus.name}"
  }
}

#------------------------------------------------------------------------------
# Architecture Information Outputs
#------------------------------------------------------------------------------

output "architecture_summary" {
  description = "Summary of the event-driven architecture components"
  value = {
    event_flow = [
      "1. Event Generator → Custom Event Bus → Order Processing Rule → Order Processor Lambda",
      "2. Order Processor Lambda → Custom Event Bus → Inventory Check Rule → Inventory Manager Lambda",
      "3. Inventory Manager Lambda → Custom Event Bus → Payment Processing Rule → SQS Queue",
      "4. All Events → Monitoring Rule → CloudWatch Logs"
    ]
    event_sources = [
      "ecommerce.api - API Gateway or application events",
      "ecommerce.order - Order processing service events",
      "ecommerce.inventory - Inventory management service events"
    ]
    event_types = [
      "Order Created - New order initiation",
      "Order Processed - Order validation completed",
      "Order Processing Failed - Order validation errors",
      "Inventory Reserved - Inventory successfully reserved",
      "Inventory Unavailable - Insufficient inventory"
    ]
    async_processing = [
      "SQS Queue provides delayed payment processing (30 seconds)",
      "EventBridge rules enable content-based routing",
      "CloudWatch Logs capture all events for monitoring"
    ]
  }
}

#------------------------------------------------------------------------------
# Resource Naming Outputs
#------------------------------------------------------------------------------

output "resource_naming_convention" {
  description = "Resource naming convention used for this deployment"
  value = {
    prefix           = local.name_prefix
    random_suffix    = random_string.suffix.result
    project_name     = var.project_name
    environment      = var.environment
    naming_pattern   = "${var.project_name}-{random-suffix}-{resource-type}"
  }
}

#------------------------------------------------------------------------------
# Security and Compliance Outputs
#------------------------------------------------------------------------------

output "security_configuration" {
  description = "Security configuration and compliance information"
  value = {
    iam_roles = {
      lambda_execution_role = aws_iam_role.lambda_execution_role.arn
    }
    encryption = {
      eventbridge_encrypted = var.enable_event_bus_kms_encryption
      kms_key_id           = var.event_bus_kms_key_id
    }
    vpc_configuration = {
      enabled         = var.enable_vpc_config
      subnet_ids      = var.vpc_subnet_ids
      security_groups = var.vpc_security_group_ids
    }
    tracing = {
      xray_enabled = var.enable_xray_tracing
    }
  }
}

#------------------------------------------------------------------------------
# Cost Optimization Outputs
#------------------------------------------------------------------------------

output "cost_optimization_info" {
  description = "Information for cost optimization and monitoring"
  value = {
    lambda_architecture    = var.lambda_architecture
    log_retention_days    = var.log_retention_days
    sqs_message_retention = var.sqs_message_retention
    reserved_concurrency  = var.lambda_reserved_concurrency
    provisioned_concurrency = var.lambda_provisioned_concurrency
    cost_allocation_tags_enabled = var.enable_cost_allocation_tags
  }
}

#------------------------------------------------------------------------------
# Development and Debugging Outputs
#------------------------------------------------------------------------------

output "development_info" {
  description = "Information useful for development and debugging"
  value = {
    aws_region     = data.aws_region.current.name
    aws_account_id = data.aws_caller_identity.current.account_id
    debug_logging  = var.enable_debug_logging
    lambda_runtime = var.lambda_runtime
    deployment_timestamp = timestamp()
  }
}

#------------------------------------------------------------------------------
# Event Pattern Examples
#------------------------------------------------------------------------------

output "event_pattern_examples" {
  description = "Example event patterns for understanding EventBridge routing"
  value = {
    order_created_event = {
      Source      = "ecommerce.api"
      DetailType  = "Order Created"
      Detail = {
        orderId     = "ord-1234567890-5678"
        customerId  = "cust-9876"
        totalAmount = 99.99
        items = [
          {
            productId = "prod-456"
            quantity  = 2
            price     = 49.99
          }
        ]
        timestamp = "2024-01-01T12:00:00Z"
      }
    }
    order_processed_event = {
      Source     = "ecommerce.order"
      DetailType = "Order Processed"
      Detail = {
        orderId     = "ord-1234567890-5678"
        customerId  = "cust-9876"
        totalAmount = 99.99
        status      = "processed"
        timestamp   = "2024-01-01T12:00:30Z"
      }
    }
    inventory_reserved_event = {
      Source     = "ecommerce.inventory"
      DetailType = "Inventory Reserved"
      Detail = {
        orderId       = "ord-1234567890-5678"
        status        = "reserved"
        reservationId = "res-ord-1234567890-5678-1704110430"
        timestamp     = "2024-01-01T12:01:00Z"
      }
    }
  }
}

#------------------------------------------------------------------------------
# Integration Endpoints
#------------------------------------------------------------------------------

output "integration_endpoints" {
  description = "Endpoints and ARNs for integrating with external systems"
  value = {
    eventbridge_endpoints = {
      put_events_api = "https://events.${data.aws_region.current.name}.amazonaws.com/"
      custom_bus_arn = aws_cloudwatch_event_bus.ecommerce_bus.arn
    }
    lambda_invoke_endpoints = {
      order_processor_arn   = aws_lambda_function.order_processor.arn
      inventory_manager_arn = aws_lambda_function.inventory_manager.arn
      event_generator_arn   = aws_lambda_function.event_generator.arn
    }
    sqs_endpoints = {
      payment_queue_url = aws_sqs_queue.payment_processing.url
      payment_queue_arn = aws_sqs_queue.payment_processing.arn
    }
  }
}