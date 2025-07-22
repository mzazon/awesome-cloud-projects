# Hybrid Identity Management with AWS Directory Service
# This Terraform configuration creates a complete hybrid identity management solution
# using AWS Managed Microsoft AD, WorkSpaces, and RDS SQL Server integration

# Data sources for availability zones and current account
data "aws_availability_zones" "available" {
  state = "available"
}

data "aws_caller_identity" "current" {}

data "aws_partition" "current" {}

# Random suffix for unique resource naming
resource "random_id" "suffix" {
  byte_length = 3
}

locals {
  # Generate unique names for resources
  name_prefix = "${var.project_name}-${var.environment}-${random_id.suffix.hex}"
  
  # Common tags
  common_tags = merge(var.default_tags, {
    Environment = var.environment
    Project     = var.project_name
  })
  
  # Directory configuration
  directory_name_full = "${var.project_name}-${var.directory_name}"
  
  # Generate secure password if not provided
  directory_password = var.directory_password != "" ? var.directory_password : random_password.directory_password.result
}

# Generate secure password for directory if not provided
resource "random_password" "directory_password" {
  length  = 16
  special = true
  upper   = true
  lower   = true
  numeric = true
}

# Generate trust password if trust is enabled but password not provided
resource "random_password" "trust_password" {
  count   = var.enable_on_premises_trust && var.trust_password == "" ? 1 : 0
  length  = 16
  special = true
  upper   = true
  lower   = true
  numeric = true
}

#================================================================================
# VPC AND NETWORKING RESOURCES
#================================================================================

# VPC for the hybrid identity infrastructure
resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-vpc"
  })
}

# Internet Gateway for public connectivity
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-igw"
  })
}

# Public subnets for NAT gateways and public resources
resource "aws_subnet" "public" {
  count = length(var.public_subnet_cidrs)

  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.public_subnet_cidrs[count.index]
  availability_zone       = data.aws_availability_zones.available.names[count.index]
  map_public_ip_on_launch = true

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-public-subnet-${count.index + 1}"
    Type = "Public"
  })
}

# Private subnets for directory services, RDS, and WorkSpaces
resource "aws_subnet" "private" {
  count = length(var.private_subnet_cidrs)

  vpc_id            = aws_vpc.main.id
  cidr_block        = var.private_subnet_cidrs[count.index]
  availability_zone = data.aws_availability_zones.available.names[count.index]

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-private-subnet-${count.index + 1}"
    Type = "Private"
  })
}

# Elastic IPs for NAT gateways
resource "aws_eip" "nat" {
  count = length(aws_subnet.public)

  domain = "vpc"
  
  depends_on = [aws_internet_gateway.main]

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-nat-eip-${count.index + 1}"
  })
}

# NAT gateways for private subnet internet access
resource "aws_nat_gateway" "main" {
  count = length(aws_subnet.public)

  allocation_id = aws_eip.nat[count.index].id
  subnet_id     = aws_subnet.public[count.index].id

  depends_on = [aws_internet_gateway.main]

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-nat-gw-${count.index + 1}"
  })
}

# Route table for public subnets
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-public-rt"
  })
}

# Route table associations for public subnets
resource "aws_route_table_association" "public" {
  count = length(aws_subnet.public)

  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# Route tables for private subnets
resource "aws_route_table" "private" {
  count = length(aws_subnet.private)

  vpc_id = aws_vpc.main.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.main[count.index].id
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-private-rt-${count.index + 1}"
  })
}

# Route table associations for private subnets
resource "aws_route_table_association" "private" {
  count = length(aws_subnet.private)

  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private[count.index].id
}

#================================================================================
# SECURITY GROUPS
#================================================================================

# Security group for AWS Directory Service
resource "aws_security_group" "directory_service" {
  name_prefix = "${local.name_prefix}-directory-"
  description = "Security group for AWS Directory Service"
  vpc_id      = aws_vpc.main.id

  # Allow all traffic from within VPC for directory services
  ingress {
    description = "All traffic from VPC"
    from_port   = 0
    to_port     = 65535
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  ingress {
    description = "All UDP traffic from VPC"
    from_port   = 0
    to_port     = 65535
    protocol    = "udp"
    cidr_blocks = [var.vpc_cidr]
  }

  # Allow LDAP traffic (389)
  ingress {
    description = "LDAP"
    from_port   = 389
    to_port     = 389
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  # Allow LDAPS traffic (636)
  ingress {
    description = "LDAPS"
    from_port   = 636
    to_port     = 636
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  # Allow Kerberos traffic (88)
  ingress {
    description = "Kerberos TCP"
    from_port   = 88
    to_port     = 88
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  ingress {
    description = "Kerberos UDP"
    from_port   = 88
    to_port     = 88
    protocol    = "udp"
    cidr_blocks = [var.vpc_cidr]
  }

  # Allow DNS traffic (53)
  ingress {
    description = "DNS TCP"
    from_port   = 53
    to_port     = 53
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  ingress {
    description = "DNS UDP"
    from_port   = 53
    to_port     = 53
    protocol    = "udp"
    cidr_blocks = [var.vpc_cidr]
  }

  egress {
    description = "All outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-directory-sg"
  })

  lifecycle {
    create_before_destroy = true
  }
}

# Security group for WorkSpaces
resource "aws_security_group" "workspaces" {
  count = var.enable_workspaces ? 1 : 0

  name_prefix = "${local.name_prefix}-workspaces-"
  description = "Security group for Amazon WorkSpaces"
  vpc_id      = aws_vpc.main.id

  # Allow WorkSpaces traffic
  ingress {
    description = "WorkSpaces PCoIP TCP"
    from_port   = 4172
    to_port     = 4172
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "WorkSpaces PCoIP UDP"
    from_port   = 4172
    to_port     = 4172
    protocol    = "udp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "WorkSpaces WorkSpaces Streaming Protocol (WSP)"
    from_port   = 4195
    to_port     = 4195
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Allow HTTPS for WorkSpaces web access
  ingress {
    description = "HTTPS"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Allow communication with directory service
  egress {
    description     = "Directory Service communication"
    from_port       = 0
    to_port         = 65535
    protocol        = "tcp"
    security_groups = [aws_security_group.directory_service.id]
  }

  egress {
    description = "All outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-workspaces-sg"
  })

  lifecycle {
    create_before_destroy = true
  }
}

# Security group for RDS
resource "aws_security_group" "rds" {
  count = var.enable_rds ? 1 : 0

  name_prefix = "${local.name_prefix}-rds-"
  description = "Security group for RDS SQL Server"
  vpc_id      = aws_vpc.main.id

  # Allow SQL Server traffic from WorkSpaces and directory service
  ingress {
    description     = "SQL Server from WorkSpaces"
    from_port       = 1433
    to_port         = 1433
    protocol        = "tcp"
    security_groups = var.enable_workspaces ? [aws_security_group.workspaces[0].id] : []
    cidr_blocks     = [var.vpc_cidr]
  }

  egress {
    description = "All outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-rds-sg"
  })

  lifecycle {
    create_before_destroy = true
  }
}

# Security group for management instance (EC2)
resource "aws_security_group" "management" {
  name_prefix = "${local.name_prefix}-mgmt-"
  description = "Security group for domain management instance"
  vpc_id      = aws_vpc.main.id

  # Allow RDP access from anywhere (restrict as needed)
  ingress {
    description = "RDP"
    from_port   = 3389
    to_port     = 3389
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"] # Restrict this to your IP range in production
  }

  # Allow WinRM for remote management
  ingress {
    description = "WinRM HTTP"
    from_port   = 5985
    to_port     = 5985
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  ingress {
    description = "WinRM HTTPS"
    from_port   = 5986
    to_port     = 5986
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  egress {
    description = "All outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-management-sg"
  })

  lifecycle {
    create_before_destroy = true
  }
}

#================================================================================
# AWS DIRECTORY SERVICE
#================================================================================

# AWS Managed Microsoft AD Directory
resource "aws_directory_service_directory" "main" {
  name       = local.directory_name_full
  password   = local.directory_password
  edition    = var.directory_edition
  type       = "MicrosoftAD"
  short_name = upper(split(".", var.directory_name)[0])

  description = var.directory_description

  vpc_settings {
    vpc_id     = aws_vpc.main.id
    subnet_ids = [aws_subnet.private[0].id, aws_subnet.private[1].id]
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-directory"
  })
}

# Enable LDAPS for the directory
resource "aws_directory_service_log_subscription" "main" {
  directory_id   = aws_directory_service_directory.main.id
  log_group_name = aws_cloudwatch_log_group.directory_service.name
}

# CloudWatch log group for directory service
resource "aws_cloudwatch_log_group" "directory_service" {
  name              = "/aws/directoryservice/${local.name_prefix}"
  retention_in_days = 30

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-directory-logs"
  })
}

# Trust relationship with on-premises AD (if enabled)
resource "aws_directory_service_trust" "on_premises" {
  count = var.enable_on_premises_trust ? 1 : 0

  directory_id = aws_directory_service_directory.main.id
  
  remote_domain_name = var.on_premises_domain_name
  trust_direction    = var.trust_direction
  trust_password     = var.trust_password != "" ? var.trust_password : random_password.trust_password[0].result
  trust_type         = "Forest"
  
  conditional_forwarder_ip_addrs = var.on_premises_dns_ips

  depends_on = [aws_directory_service_directory.main]
}

#================================================================================
# IAM ROLES AND POLICIES
#================================================================================

# IAM role for RDS Directory Service integration
resource "aws_iam_role" "rds_directory_service" {
  count = var.enable_rds ? 1 : 0

  name = "${local.name_prefix}-rds-directory-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "rds.amazonaws.com"
        }
      }
    ]
  })

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-rds-directory-role"
  })
}

# Attach AWS managed policy for RDS Directory Service access
resource "aws_iam_role_policy_attachment" "rds_directory_service" {
  count = var.enable_rds ? 1 : 0

  role       = aws_iam_role.rds_directory_service[0].name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/service-role/AmazonRDSDirectoryServiceAccess"
}

# Enhanced monitoring role for RDS (if enabled)
resource "aws_iam_role" "rds_monitoring" {
  count = var.enable_rds && var.enable_enhanced_monitoring ? 1 : 0

  name = "${local.name_prefix}-rds-monitoring-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "monitoring.rds.amazonaws.com"
        }
      }
    ]
  })

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-rds-monitoring-role"
  })
}

resource "aws_iam_role_policy_attachment" "rds_monitoring" {
  count = var.enable_rds && var.enable_enhanced_monitoring ? 1 : 0

  role       = aws_iam_role.rds_monitoring[0].name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/service-role/AmazonRDSEnhancedMonitoringRole"
}

# Instance profile for domain management EC2 instance
resource "aws_iam_role" "domain_admin" {
  name = "${local.name_prefix}-domain-admin-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-domain-admin-role"
  })
}

# Policy for domain admin instance to manage directory
resource "aws_iam_role_policy" "domain_admin" {
  name = "${local.name_prefix}-domain-admin-policy"
  role = aws_iam_role.domain_admin.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ds:DescribeDirectories",
          "ds:ListAuthorizedApplications",
          "ds:CreateSnapshot",
          "ds:DescribeSnapshots",
          "ds:RestoreFromSnapshot",
          "ec2:DescribeInstances",
          "ec2:DescribeImages",
          "ssm:GetParameter",
          "ssm:PutParameter",
          "ssm:GetParameters",
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "*"
      }
    ]
  })
}

# Instance profile for domain admin role
resource "aws_iam_instance_profile" "domain_admin" {
  name = "${local.name_prefix}-domain-admin-profile"
  role = aws_iam_role.domain_admin.name
}

#================================================================================
# AMAZON WORKSPACES
#================================================================================

# WorkSpaces directory registration
resource "aws_workspaces_directory" "main" {
  count = var.enable_workspaces ? 1 : 0

  directory_id = aws_directory_service_directory.main.id
  
  subnet_ids = [aws_subnet.private[0].id, aws_subnet.private[1].id]

  # WorkDocs integration
  workspace_creation_properties {
    enable_work_docs                            = var.enable_workdocs
    enable_internet_access                      = true
    default_ou                                  = "OU=Computers,OU=${upper(split(".", var.directory_name)[0])},DC=${join(",DC=", split(".", var.directory_name))}"
    custom_security_group_id                    = aws_security_group.workspaces[0].id
    user_enabled_as_local_administrator         = false
    enable_maintenance_mode                     = true
  }

  # Self-service permissions
  self_service_permissions {
    change_compute_type  = var.enable_self_service_permissions
    increase_volume_size = var.enable_self_service_permissions
    rebuild_workspace    = var.enable_self_service_permissions
    restart_workspace    = var.enable_self_service_permissions
    switch_running_mode  = var.enable_self_service_permissions
  }

  workspace_access_properties {
    device_type_android    = "ALLOW"
    device_type_chromeos   = "ALLOW"
    device_type_ios        = "ALLOW"
    device_type_linux      = "DENY"
    device_type_osx        = "ALLOW"
    device_type_web        = "ALLOW"
    device_type_windows    = "ALLOW"
    device_type_zeroclient = "DENY"
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-workspaces-directory"
  })

  depends_on = [aws_directory_service_directory.main]
}

# Create WorkSpaces for test users
resource "aws_workspaces_workspace" "test_users" {
  for_each = var.create_test_users && var.enable_workspaces ? { for user in var.test_users : user.username => user } : {}

  directory_id = aws_workspaces_directory.main[0].id
  bundle_id    = var.workspaces_bundle_id
  user_name    = each.value.username

  # Workspace properties
  workspace_properties {
    compute_type_name                         = "STANDARD"
    user_volume_size_gib                      = 50
    root_volume_size_gib                      = 80
    running_mode                              = "AUTO_STOP"
    running_mode_auto_stop_timeout_in_minutes = 60
  }

  volume_encryption_key = "alias/aws/workspaces"

  tags = merge(local.common_tags, {
    Name     = "${local.name_prefix}-workspace-${each.key}"
    Username = each.key
  })

  depends_on = [aws_workspaces_directory.main]
}

#================================================================================
# AMAZON RDS
#================================================================================

# DB subnet group for RDS
resource "aws_db_subnet_group" "main" {
  count = var.enable_rds ? 1 : 0

  name       = "${local.name_prefix}-db-subnet-group"
  subnet_ids = [aws_subnet.private[0].id, aws_subnet.private[1].id]

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-db-subnet-group"
  })
}

# Parameter group for SQL Server
resource "aws_db_parameter_group" "sqlserver" {
  count = var.enable_rds ? 1 : 0

  family = "sqlserver-se-15.0"
  name   = "${local.name_prefix}-sqlserver-params"

  parameter {
    name  = "contained database authentication"
    value = "1"
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-sqlserver-params"
  })
}

# Option group for SQL Server
resource "aws_db_option_group" "sqlserver" {
  count = var.enable_rds ? 1 : 0

  name                     = "${local.name_prefix}-sqlserver-options"
  option_group_description = "Option group for SQL Server with Directory Service integration"
  engine_name              = "sqlserver-se"
  major_engine_version     = "15.00"

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-sqlserver-options"
  })
}

# RDS SQL Server instance with Directory Service integration
resource "aws_db_instance" "main" {
  count = var.enable_rds ? 1 : 0

  identifier = "${local.name_prefix}-sqlserver"

  # Engine configuration
  engine                = "sqlserver-se"
  engine_version        = var.rds_engine_version
  instance_class        = var.rds_instance_class
  allocated_storage     = var.rds_allocated_storage
  storage_type          = var.rds_storage_type
  storage_encrypted     = var.enable_storage_encryption
  deletion_protection   = var.enable_deletion_protection

  # Database configuration
  db_name  = null # SQL Server doesn't support initial database creation via RDS
  username = "admin"
  password = random_password.rds_password[0].result

  # Network configuration
  vpc_security_group_ids = [aws_security_group.rds[0].id]
  db_subnet_group_name   = aws_db_subnet_group.main[0].name
  publicly_accessible    = false

  # Directory Service integration
  domain               = aws_directory_service_directory.main.id
  domain_iam_role_name = aws_iam_role.rds_directory_service[0].name

  # Parameter and option groups
  parameter_group_name = aws_db_parameter_group.sqlserver[0].name
  option_group_name    = aws_db_option_group.sqlserver[0].name

  # Backup configuration
  backup_retention_period = var.rds_backup_retention_period
  backup_window          = var.rds_backup_window
  maintenance_window     = var.rds_maintenance_window
  
  # Monitoring
  monitoring_interval                   = var.enable_enhanced_monitoring ? var.monitoring_interval : 0
  monitoring_role_arn                  = var.enable_enhanced_monitoring ? aws_iam_role.rds_monitoring[0].arn : null
  enabled_cloudwatch_logs_exports      = ["error"]
  performance_insights_enabled         = true
  performance_insights_retention_period = 7

  # Final snapshot configuration
  final_snapshot_identifier = "${local.name_prefix}-sqlserver-final-snapshot-${formatdate("YYYY-MM-DD-hhmm", timestamp())}"
  
  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-sqlserver"
  })

  depends_on = [
    aws_directory_service_directory.main,
    aws_iam_role_policy_attachment.rds_directory_service
  ]
}

# Generate password for RDS instance
resource "random_password" "rds_password" {
  count = var.enable_rds ? 1 : 0

  length  = 16
  special = true
  upper   = true
  lower   = true
  numeric = true

  # Exclude characters that might cause issues with SQL Server
  override_special = "!#$%&*()-_=+[]{}<>:?"
}

#================================================================================
# DOMAIN MANAGEMENT EC2 INSTANCE
#================================================================================

# Get latest Windows Server AMI
data "aws_ami" "windows" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["Windows_Server-2022-English-Full-Base-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# Key pair for EC2 instance access (create manually or import existing)
resource "aws_key_pair" "domain_admin" {
  key_name   = "${local.name_prefix}-domain-admin-key"
  public_key = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQC7... # Replace with your actual public key"

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-domain-admin-key"
  })

  lifecycle {
    ignore_changes = [public_key]
  }
}

# Domain management EC2 instance
resource "aws_instance" "domain_admin" {
  ami                    = data.aws_ami.windows.id
  instance_type          = "t3.medium"
  key_name              = aws_key_pair.domain_admin.key_name
  vpc_security_group_ids = [aws_security_group.management.id]
  subnet_id             = aws_subnet.private[0].id
  iam_instance_profile  = aws_iam_instance_profile.domain_admin.name

  # User data script to join domain and install management tools
  user_data = base64encode(templatefile("${path.module}/user_data.ps1", {
    domain_name     = aws_directory_service_directory.main.name
    domain_username = "Admin"
    domain_password = local.directory_password
    dns_addresses   = jsonencode(aws_directory_service_directory.main.dns_ip_addresses)
  }))

  root_block_device {
    volume_type           = "gp3"
    volume_size           = 100
    encrypted             = true
    delete_on_termination = true

    tags = merge(local.common_tags, {
      Name = "${local.name_prefix}-domain-admin-root"
    })
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-domain-admin"
  })

  depends_on = [aws_directory_service_directory.main]
}

# User data script for domain admin instance
resource "local_file" "user_data_script" {
  filename = "${path.module}/user_data.ps1"
  content  = <<-EOT
<powershell>
# Configure DNS to point to Directory Service
$dnsAddresses = '${jsonencode(aws_directory_service_directory.main.dns_ip_addresses)}' | ConvertFrom-Json
$adapter = Get-NetAdapter | Where-Object {$_.Status -eq "Up"}
Set-DnsClientServerAddress -InterfaceAlias $adapter.Name -ServerAddresses $dnsAddresses

# Install Active Directory management tools
Install-WindowsFeature -Name RSAT-AD-Tools -IncludeManagementTools

# Configure PowerShell execution policy
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Force

# Create domain join script
$joinScript = @"
`$domain = "${aws_directory_service_directory.main.name}"
`$username = "Admin"
`$password = "${local.directory_password}" | ConvertTo-SecureString -AsPlainText -Force
`$credential = New-Object System.Management.Automation.PSCredential(`$username, `$password)

try {
    Add-Computer -DomainName `$domain -Credential `$credential -Restart
    Write-Host "Successfully joined domain: `$domain"
} catch {
    Write-Host "Failed to join domain: `$_"
    Start-Sleep 300
    Restart-Computer -Force
}
"@

$joinScript | Out-File -FilePath "C:\join-domain.ps1" -Encoding UTF8

# Execute domain join script
PowerShell.exe -ExecutionPolicy Bypass -File "C:\join-domain.ps1"
</powershell>
EOT
}

#================================================================================
# CLOUDTRAIL FOR AUDITING (OPTIONAL)
#================================================================================

# S3 bucket for CloudTrail logs
resource "aws_s3_bucket" "cloudtrail" {
  count = var.enable_cloudtrail ? 1 : 0

  bucket = "${local.name_prefix}-cloudtrail-${random_id.suffix.hex}"

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-cloudtrail-bucket"
  })
}

# S3 bucket versioning
resource "aws_s3_bucket_versioning" "cloudtrail" {
  count = var.enable_cloudtrail ? 1 : 0

  bucket = aws_s3_bucket.cloudtrail[0].id
  versioning_configuration {
    status = "Enabled"
  }
}

# S3 bucket server-side encryption
resource "aws_s3_bucket_server_side_encryption_configuration" "cloudtrail" {
  count = var.enable_cloudtrail ? 1 : 0

  bucket = aws_s3_bucket.cloudtrail[0].id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# S3 bucket policy for CloudTrail
resource "aws_s3_bucket_policy" "cloudtrail" {
  count = var.enable_cloudtrail ? 1 : 0

  bucket = aws_s3_bucket.cloudtrail[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AWSCloudTrailAclCheck"
        Effect = "Allow"
        Principal = {
          Service = "cloudtrail.amazonaws.com"
        }
        Action   = "s3:GetBucketAcl"
        Resource = aws_s3_bucket.cloudtrail[0].arn
      },
      {
        Sid    = "AWSCloudTrailWrite"
        Effect = "Allow"
        Principal = {
          Service = "cloudtrail.amazonaws.com"
        }
        Action   = "s3:PutObject"
        Resource = "${aws_s3_bucket.cloudtrail[0].arn}/*"
        Condition = {
          StringEquals = {
            "s3:x-amz-acl" = "bucket-owner-full-control"
          }
        }
      }
    ]
  })
}

# CloudTrail for directory service auditing
resource "aws_cloudtrail" "main" {
  count = var.enable_cloudtrail ? 1 : 0

  name           = "${local.name_prefix}-cloudtrail"
  s3_bucket_name = aws_s3_bucket.cloudtrail[0].bucket

  event_selector {
    read_write_type                 = "All"
    include_management_events       = true
    exclude_management_event_sources = []

    data_resource {
      type   = "AWS::DirectoryService::Directory"
      values = ["${aws_directory_service_directory.main.arn}/*"]
    }
  }

  depends_on = [aws_s3_bucket_policy.cloudtrail]

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-cloudtrail"
  })
}