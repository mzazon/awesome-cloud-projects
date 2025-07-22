# Data sources
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# Random suffix for unique resource naming
resource "random_id" "suffix" {
  byte_length = 3
}

locals {
  # Common resource naming
  resource_suffix = random_id.suffix.hex
  lambda_function_name = "${var.project_name}-provisioner-${local.resource_suffix}"
  iam_role_name = "${var.project_name}-lambda-role-${local.resource_suffix}"
  secret_name = "${var.project_name}-ad-credentials-${local.resource_suffix}"
  ssm_document_name = "${var.project_name}-dev-setup-${local.resource_suffix}"
  eventbridge_rule_name = "${var.project_name}-daily-provisioning-${local.resource_suffix}"

  # Common tags
  common_tags = merge(
    {
      Project = var.project_name
      Environment = var.environment
      Purpose = "DevEnvironmentAutomation"
    },
    var.additional_tags
  )
}

# ===========================
# Secrets Manager
# ===========================

# Store Active Directory credentials securely
resource "aws_secretsmanager_secret" "ad_credentials" {
  name        = local.secret_name
  description = "AD service account credentials for WorkSpaces automation"
  
  # Enable automatic rotation (optional)
  rotation_rules {
    automatically_after_days = 90
  }

  tags = merge(local.common_tags, {
    Name = "AD Credentials"
    Type = "ServiceAccount"
  })
}

# Store the actual credential values
resource "aws_secretsmanager_secret_version" "ad_credentials" {
  secret_id = aws_secretsmanager_secret.ad_credentials.id
  secret_string = jsonencode({
    username = var.ad_service_username
    password = var.ad_service_password
  })
}

# ===========================
# IAM Roles and Policies
# ===========================

# Trust policy for Lambda execution
data "aws_iam_policy_document" "lambda_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

# IAM role for Lambda function
resource "aws_iam_role" "lambda_execution_role" {
  name               = local.iam_role_name
  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role.json
  description        = "Service role for WorkSpaces automation Lambda function"

  tags = merge(local.common_tags, {
    Name = "WorkSpaces Automation Lambda Role"
  })
}

# Custom policy for Lambda function permissions
data "aws_iam_policy_document" "lambda_permissions" {
  # WorkSpaces permissions
  statement {
    sid = "WorkSpacesManagement"
    actions = [
      "workspaces:CreateWorkspaces",
      "workspaces:TerminateWorkspaces",
      "workspaces:DescribeWorkspaces",
      "workspaces:DescribeWorkspaceDirectories",
      "workspaces:DescribeWorkspaceBundles",
      "workspaces:ModifyWorkspaceProperties",
      "workspaces:RebootWorkspaces",
      "workspaces:StopWorkspaces",
      "workspaces:StartWorkspaces"
    ]
    resources = ["*"]
  }

  # Systems Manager permissions
  statement {
    sid = "SystemsManagerAutomation"
    actions = [
      "ssm:SendCommand",
      "ssm:GetCommandInvocation",
      "ssm:DescribeInstanceInformation",
      "ssm:GetDocument",
      "ssm:ListDocuments",
      "ssm:DescribeDocumentParameters",
      "ssm:ListCommandInvocations"
    ]
    resources = ["*"]
  }

  # Secrets Manager permissions
  statement {
    sid = "SecretsManagerAccess"
    actions = [
      "secretsmanager:GetSecretValue"
    ]
    resources = [aws_secretsmanager_secret.ad_credentials.arn]
  }

  # CloudWatch Logs permissions
  statement {
    sid = "CloudWatchLogs"
    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents"
    ]
    resources = [
      "arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:log-group:/aws/lambda/${local.lambda_function_name}:*"
    ]
  }

  # EC2 permissions for Lambda VPC configuration (if needed)
  statement {
    sid = "VPCAccess"
    actions = [
      "ec2:CreateNetworkInterface",
      "ec2:DescribeNetworkInterfaces",
      "ec2:DeleteNetworkInterface",
      "ec2:AttachNetworkInterface",
      "ec2:DetachNetworkInterface"
    ]
    resources = ["*"]
  }

  # Directory Service permissions (for AD integration)
  statement {
    sid = "DirectoryServiceAccess"
    actions = [
      "ds:DescribeDirectories",
      "ds:AuthorizeApplication",
      "ds:UnauthorizeApplication"
    ]
    resources = ["*"]
  }
}

# Create custom IAM policy
resource "aws_iam_policy" "lambda_permissions" {
  name        = "${var.project_name}-lambda-policy-${local.resource_suffix}"
  description = "Permissions for WorkSpaces automation Lambda function"
  policy      = data.aws_iam_policy_document.lambda_permissions.json

  tags = merge(local.common_tags, {
    Name = "WorkSpaces Lambda Policy"
  })
}

# Attach custom policy to Lambda role
resource "aws_iam_role_policy_attachment" "lambda_permissions" {
  role       = aws_iam_role.lambda_execution_role.name
  policy_arn = aws_iam_policy.lambda_permissions.arn
}

# Attach AWS managed policy for basic Lambda execution
resource "aws_iam_role_policy_attachment" "lambda_basic_execution" {
  role       = aws_iam_role.lambda_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# ===========================
# Systems Manager Document
# ===========================

# SSM document for development environment setup
resource "aws_ssm_document" "dev_environment_setup" {
  name            = local.ssm_document_name
  document_type   = "Command"
  document_format = "JSON"
  
  content = jsonencode({
    schemaVersion = "2.2"
    description   = "Configure development environment on WorkSpaces"
    
    parameters = {
      developmentTools = {
        type        = "String"
        description = "Comma-separated list of development tools to install"
        default     = var.development_tools
      }
      teamConfiguration = {
        type        = "String"
        description = "Team-specific configuration settings"
        default     = var.team_configuration
      }
    }
    
    mainSteps = [
      {
        action = "aws:runPowerShellScript"
        name   = "InstallChocolatey"
        inputs = {
          runCommand = [
            "Write-Output 'Installing Chocolatey package manager...'",
            "Set-ExecutionPolicy Bypass -Scope Process -Force",
            "[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072",
            "iex ((New-Object System.Net.WebClient).DownloadString('https://chocolatey.org/install.ps1'))",
            "Write-Output 'Chocolatey installation completed'"
          ]
        }
      },
      {
        action = "aws:runPowerShellScript"
        name   = "InstallDevelopmentTools"
        inputs = {
          runCommand = [
            "Write-Output 'Installing development tools...'",
            "$tools = '{{ developmentTools }}'.Split(',')",
            "foreach ($tool in $tools) {",
            "  $trimmedTool = $tool.Trim()",
            "  Write-Output \"Installing $trimmedTool...\"",
            "  switch ($trimmedTool) {",
            "    'git' { choco install git -y --no-progress }",
            "    'vscode' { choco install vscode -y --no-progress }",
            "    'nodejs' { choco install nodejs -y --no-progress }",
            "    'python' { choco install python -y --no-progress }",
            "    'docker' { choco install docker-desktop -y --no-progress }",
            "    'awscli' { choco install awscli -y --no-progress }",
            "    'terraform' { choco install terraform -y --no-progress }",
            "    'kubectl' { choco install kubernetes-cli -y --no-progress }",
            "    default { Write-Output \"Unknown tool: $trimmedTool\" }",
            "  }",
            "}",
            "Write-Output 'Development environment setup completed successfully'"
          ]
        }
      },
      {
        action = "aws:runPowerShellScript"
        name   = "ConfigureEnvironment"
        inputs = {
          runCommand = [
            "Write-Output 'Configuring development environment...'",
            "# Set Git global configuration",
            "git config --global init.defaultBranch main",
            "git config --global pull.rebase false",
            "git config --global core.autocrlf true",
            "# Create development directories",
            "New-Item -ItemType Directory -Force -Path C:\\Dev\\Projects",
            "New-Item -ItemType Directory -Force -Path C:\\Dev\\Tools",
            "New-Item -ItemType Directory -Force -Path C:\\Dev\\Scripts",
            "# Set environment variables",
            "[Environment]::SetEnvironmentVariable('DEV_HOME', 'C:\\Dev', 'Machine')",
            "# Configure VS Code settings if installed",
            "if (Get-Command code -ErrorAction SilentlyContinue) {",
            "  $settingsPath = \"$env:APPDATA\\Code\\User\\settings.json\"",
            "  $settingsDir = Split-Path $settingsPath -Parent",
            "  if (!(Test-Path $settingsDir)) { New-Item -ItemType Directory -Path $settingsDir -Force }",
            "  $settings = @{",
            "    'editor.fontSize' = 14",
            "    'editor.tabSize' = 2",
            "    'editor.insertSpaces' = $true",
            "    'files.autoSave' = 'afterDelay'",
            "    'terminal.integrated.defaultProfile.windows' = 'PowerShell'",
            "  }",
            "  $settings | ConvertTo-Json | Set-Content $settingsPath",
            "}",
            "Write-Output 'Environment configuration completed'"
          ]
        }
      }
    ]
  })

  tags = merge(local.common_tags, {
    Name = "Development Environment Setup"
    Type = "Configuration"
  })
}

# ===========================
# Lambda Function
# ===========================

# Create Lambda deployment package
data "archive_file" "lambda_deployment_package" {
  type        = "zip"
  output_path = "${path.module}/lambda-deployment-package.zip"
  
  source {
    content = templatefile("${path.module}/lambda_function.py.tpl", {
      secret_name = aws_secretsmanager_secret.ad_credentials.name
      ssm_document_name = aws_ssm_document.dev_environment_setup.name
    })
    filename = "lambda_function.py"
  }
}

# Lambda function for WorkSpaces automation
resource "aws_lambda_function" "workspaces_provisioner" {
  filename         = data.archive_file.lambda_deployment_package.output_path
  function_name    = local.lambda_function_name
  role            = aws_iam_role.lambda_execution_role.arn
  handler         = "lambda_function.lambda_handler"
  source_code_hash = data.archive_file.lambda_deployment_package.output_base64sha256
  runtime         = "python3.11"
  timeout         = var.lambda_timeout
  memory_size     = var.lambda_memory_size
  
  description = "Automated WorkSpaces provisioning for development teams"

  environment {
    variables = {
      SECRET_NAME = aws_secretsmanager_secret.ad_credentials.name
      SSM_DOCUMENT_NAME = aws_ssm_document.dev_environment_setup.name
      PROJECT_NAME = var.project_name
      ENVIRONMENT = var.environment
    }
  }

  # Enable X-Ray tracing for debugging
  tracing_config {
    mode = "Active"
  }

  # Dead letter queue for failed invocations
  dead_letter_config {
    target_arn = aws_sqs_queue.lambda_dlq.arn
  }

  tags = merge(local.common_tags, {
    Name = "WorkSpaces Provisioner"
    Runtime = "python3.11"
  })

  depends_on = [
    aws_iam_role_policy_attachment.lambda_permissions,
    aws_iam_role_policy_attachment.lambda_basic_execution,
    aws_cloudwatch_log_group.lambda_logs
  ]
}

# CloudWatch Log Group for Lambda
resource "aws_cloudwatch_log_group" "lambda_logs" {
  name              = "/aws/lambda/${local.lambda_function_name}"
  retention_in_days = 14

  tags = merge(local.common_tags, {
    Name = "WorkSpaces Lambda Logs"
  })
}

# Dead Letter Queue for failed Lambda invocations
resource "aws_sqs_queue" "lambda_dlq" {
  name = "${var.project_name}-lambda-dlq-${local.resource_suffix}"
  
  # Message retention period (14 days)
  message_retention_seconds = 1209600
  
  tags = merge(local.common_tags, {
    Name = "Lambda Dead Letter Queue"
    Type = "ErrorHandling"
  })
}

# ===========================
# EventBridge Automation
# ===========================

# EventBridge rule for scheduled automation
resource "aws_cloudwatch_event_rule" "workspaces_automation" {
  count = var.enable_automation_schedule ? 1 : 0
  
  name                = local.eventbridge_rule_name
  description         = "Daily WorkSpaces provisioning automation"
  schedule_expression = var.automation_schedule
  state              = "ENABLED"

  tags = merge(local.common_tags, {
    Name = "WorkSpaces Automation Schedule"
    Type = "Automation"
  })
}

# EventBridge target for Lambda function
resource "aws_cloudwatch_event_target" "lambda_target" {
  count = var.enable_automation_schedule ? 1 : 0
  
  rule      = aws_cloudwatch_event_rule.workspaces_automation[0].name
  target_id = "WorkSpacesProvisionerTarget"
  arn       = aws_lambda_function.workspaces_provisioner.arn

  # Input for Lambda function
  input = jsonencode({
    secret_name = aws_secretsmanager_secret.ad_credentials.name
    directory_id = var.directory_id
    bundle_id = var.workspaces_bundle_id
    target_users = var.target_users
    ssm_document = aws_ssm_document.dev_environment_setup.name
    running_mode = var.workspaces_running_mode
    auto_stop_timeout = var.auto_stop_timeout_minutes
    development_tools = var.development_tools
    team_configuration = var.team_configuration
  })
}

# Lambda permission for EventBridge to invoke function
resource "aws_lambda_permission" "allow_eventbridge" {
  count = var.enable_automation_schedule ? 1 : 0
  
  statement_id  = "AllowExecutionFromEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.workspaces_provisioner.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.workspaces_automation[0].arn
}

# ===========================
# CloudWatch Alarms
# ===========================

# Lambda function error alarm
resource "aws_cloudwatch_metric_alarm" "lambda_errors" {
  alarm_name          = "${local.lambda_function_name}-errors"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "Errors"
  namespace           = "AWS/Lambda"
  period              = "120"
  statistic           = "Sum"
  threshold           = "0"
  alarm_description   = "This metric monitors lambda errors"
  alarm_actions       = [aws_sns_topic.alerts.arn]

  dimensions = {
    FunctionName = aws_lambda_function.workspaces_provisioner.function_name
  }

  tags = merge(local.common_tags, {
    Name = "Lambda Error Alarm"
    Type = "Monitoring"
  })
}

# Lambda function duration alarm
resource "aws_cloudwatch_metric_alarm" "lambda_duration" {
  alarm_name          = "${local.lambda_function_name}-duration"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "Duration"
  namespace           = "AWS/Lambda"
  period              = "120"
  statistic           = "Average"
  threshold           = "240000" # 4 minutes (80% of timeout)
  alarm_description   = "This metric monitors lambda duration"
  alarm_actions       = [aws_sns_topic.alerts.arn]

  dimensions = {
    FunctionName = aws_lambda_function.workspaces_provisioner.function_name
  }

  tags = merge(local.common_tags, {
    Name = "Lambda Duration Alarm"
    Type = "Monitoring"
  })
}

# ===========================
# SNS for Notifications
# ===========================

# SNS topic for alerts and notifications
resource "aws_sns_topic" "alerts" {
  name = "${var.project_name}-alerts-${local.resource_suffix}"

  tags = merge(local.common_tags, {
    Name = "WorkSpaces Automation Alerts"
    Type = "Notifications"
  })
}

# SNS topic policy (optional - allows other services to publish)
resource "aws_sns_topic_policy" "alerts" {
  arn = aws_sns_topic.alerts.arn

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowCloudWatchAlarmsToPublish"
        Effect = "Allow"
        Principal = {
          Service = "cloudwatch.amazonaws.com"
        }
        Action   = "SNS:Publish"
        Resource = aws_sns_topic.alerts.arn
        Condition = {
          StringEquals = {
            "aws:SourceAccount" = data.aws_caller_identity.current.account_id
          }
        }
      }
    ]
  })
}