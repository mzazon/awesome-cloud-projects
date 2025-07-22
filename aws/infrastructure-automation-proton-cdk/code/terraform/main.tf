# Data sources for current AWS account and region
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# Random string for unique resource naming
resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
}

# Local variables for consistent naming
locals {
  account_id = data.aws_caller_identity.current.account_id
  region     = data.aws_region.current.name
  
  # Unique resource names with suffix
  project_name_unique          = "${var.project_name}-${random_string.suffix.result}"
  bucket_name                  = "${var.template_bucket_name}-${local.account_id}-${random_string.suffix.result}"
  proton_role_name            = "${var.proton_service_role_name}-${random_string.suffix.result}"
  environment_template_name   = "${var.environment_template_name}-${random_string.suffix.result}"
  service_template_name       = "${var.service_template_name}-${random_string.suffix.result}"
  
  # Common tags
  common_tags = merge(
    {
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "terraform"
      Recipe      = "infrastructure-automation-with-aws-proton-and-cdk"
    },
    var.additional_tags
  )
}

#
# S3 Bucket for storing Proton templates
#
resource "aws_s3_bucket" "proton_templates" {
  bucket = local.bucket_name
  
  tags = merge(local.common_tags, {
    Name        = local.bucket_name
    Description = "S3 bucket for storing AWS Proton templates"
  })
}

resource "aws_s3_bucket_versioning" "proton_templates" {
  bucket = aws_s3_bucket.proton_templates.id
  versioning_configuration {
    status = var.template_bucket_versioning ? "Enabled" : "Suspended"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "proton_templates" {
  bucket = aws_s3_bucket.proton_templates.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "proton_templates" {
  bucket = aws_s3_bucket.proton_templates.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

#
# IAM Role for AWS Proton
#
data "aws_iam_policy_document" "proton_trust_policy" {
  statement {
    effect = "Allow"
    
    principals {
      type        = "Service"
      identifiers = ["proton.amazonaws.com"]
    }
    
    actions = ["sts:AssumeRole"]
  }
}

resource "aws_iam_role" "proton_service_role" {
  count = var.create_proton_service_role ? 1 : 0
  
  name               = local.proton_role_name
  assume_role_policy = data.aws_iam_policy_document.proton_trust_policy.json
  
  tags = merge(local.common_tags, {
    Name        = local.proton_role_name
    Description = "Service role for AWS Proton to manage infrastructure"
  })
}

resource "aws_iam_role_policy_attachment" "proton_managed_policies" {
  count = var.create_proton_service_role ? length(var.proton_managed_policies) : 0
  
  role       = aws_iam_role.proton_service_role[0].name
  policy_arn = var.proton_managed_policies[count.index]
}

# Additional IAM policy for S3 access to template bucket
data "aws_iam_policy_document" "proton_s3_access" {
  statement {
    effect = "Allow"
    
    actions = [
      "s3:GetObject",
      "s3:GetObjectVersion",
      "s3:ListBucket"
    ]
    
    resources = [
      aws_s3_bucket.proton_templates.arn,
      "${aws_s3_bucket.proton_templates.arn}/*"
    ]
  }
}

resource "aws_iam_role_policy" "proton_s3_access" {
  count = var.create_proton_service_role ? 1 : 0
  
  name   = "${local.proton_role_name}-s3-access"
  role   = aws_iam_role.proton_service_role[0].id
  policy = data.aws_iam_policy_document.proton_s3_access.json
}

#
# Environment Template Files
#
# Create environment template schema
resource "local_file" "environment_schema" {
  filename = "${path.module}/templates/environment-schema.yaml"
  content = yamlencode({
    schema = {
      format = "openapi: \"3.0.0\""
      environment_input_type = "EnvironmentInput"
      types = {
        EnvironmentInput = {
          type = "object"
          description = "Input properties for the environment"
          properties = {
            vpc_cidr = {
              type = "string"
              description = "CIDR block for the VPC"
              default = var.vpc_cidr
              pattern = "^([0-9]{1,3}\\.){3}[0-9]{1,3}(\\/([0-9]|[1-2][0-9]|3[0-2]))?$"
            }
            environment_name = {
              type = "string"
              description = "Name of the environment"
              minLength = 1
              maxLength = 100
            }
          }
          required = ["environment_name"]
        }
      }
    }
  })
}

# Create environment template infrastructure
resource "local_file" "environment_infrastructure" {
  filename = "${path.module}/templates/environment-infrastructure.yaml"
  content = <<-EOF
AWSTemplateFormatVersion: '2010-09-09'
Description: 'Proton Environment Template - Shared Infrastructure'

Parameters:
  vpc_cidr:
    Type: String
    Description: CIDR block for the VPC
    Default: "${var.vpc_cidr}"
    AllowedPattern: ^([0-9]{1,3}\.){3}[0-9]{1,3}(\/([0-9]|[1-2][0-9]|3[0-2]))?$
    ConstraintDescription: Must be a valid IPv4 CIDR block
  environment_name:
    Type: String
    Description: Name of the environment
    MinLength: 1
    MaxLength: 100

Resources:
  # VPC for the environment
  VPC:
    Type: AWS::EC2::VPC
    Properties:
      CidrBlock: !Ref vpc_cidr
      EnableDnsHostnames: ${var.enable_dns_hostnames}
      EnableDnsSupport: ${var.enable_dns_support}
      Tags:
        - Key: Name
          Value: !Sub '$${environment_name}-vpc'
        - Key: Environment
          Value: !Ref environment_name

  # Internet Gateway
  InternetGateway:
    Type: AWS::EC2::InternetGateway
    Properties:
      Tags:
        - Key: Name
          Value: !Sub '$${environment_name}-igw'

  # Attach Internet Gateway to VPC
  InternetGatewayAttachment:
    Type: AWS::EC2::VPCGatewayAttachment
    Properties:
      InternetGatewayId: !Ref InternetGateway
      VpcId: !Ref VPC

  # Public Subnets
  PublicSubnet1:
    Type: AWS::EC2::Subnet
    Properties:
      VpcId: !Ref VPC
      AvailabilityZone: !Select [0, !GetAZs '']
      CidrBlock: !Select [0, !Cidr [!Ref vpc_cidr, 4, 8]]
      MapPublicIpOnLaunch: true
      Tags:
        - Key: Name
          Value: !Sub '$${environment_name}-public-subnet-1'
        - Key: Type
          Value: Public

  PublicSubnet2:
    Type: AWS::EC2::Subnet
    Properties:
      VpcId: !Ref VPC
      AvailabilityZone: !Select [1, !GetAZs '']
      CidrBlock: !Select [1, !Cidr [!Ref vpc_cidr, 4, 8]]
      MapPublicIpOnLaunch: true
      Tags:
        - Key: Name
          Value: !Sub '$${environment_name}-public-subnet-2'
        - Key: Type
          Value: Public

  # Private Subnets
  PrivateSubnet1:
    Type: AWS::EC2::Subnet
    Properties:
      VpcId: !Ref VPC
      AvailabilityZone: !Select [0, !GetAZs '']
      CidrBlock: !Select [2, !Cidr [!Ref vpc_cidr, 4, 8]]
      Tags:
        - Key: Name
          Value: !Sub '$${environment_name}-private-subnet-1'
        - Key: Type
          Value: Private

  PrivateSubnet2:
    Type: AWS::EC2::Subnet
    Properties:
      VpcId: !Ref VPC
      AvailabilityZone: !Select [1, !GetAZs '']
      CidrBlock: !Select [3, !Cidr [!Ref vpc_cidr, 4, 8]]
      Tags:
        - Key: Name
          Value: !Sub '$${environment_name}-private-subnet-2'
        - Key: Type
          Value: Private

  # Route Tables
  PublicRouteTable:
    Type: AWS::EC2::RouteTable
    Properties:
      VpcId: !Ref VPC
      Tags:
        - Key: Name
          Value: !Sub '$${environment_name}-public-rt'

  PublicRoute:
    Type: AWS::EC2::Route
    DependsOn: InternetGatewayAttachment
    Properties:
      RouteTableId: !Ref PublicRouteTable
      DestinationCidrBlock: 0.0.0.0/0
      GatewayId: !Ref InternetGateway

  PublicSubnet1RouteTableAssociation:
    Type: AWS::EC2::SubnetRouteTableAssociation
    Properties:
      RouteTableId: !Ref PublicRouteTable
      SubnetId: !Ref PublicSubnet1

  PublicSubnet2RouteTableAssociation:
    Type: AWS::EC2::SubnetRouteTableAssociation
    Properties:
      RouteTableId: !Ref PublicRouteTable
      SubnetId: !Ref PublicSubnet2

  # ECS Cluster
  ECSCluster:
    Type: AWS::ECS::Cluster
    Properties:
      ClusterName: !Sub '$${environment_name}-cluster'
      ClusterSettings:
        - Name: containerInsights
          Value: ${var.enable_container_insights ? "enabled" : "disabled"}
      Tags:
        - Key: Name
          Value: !Sub '$${environment_name}-cluster'
        - Key: Environment
          Value: !Ref environment_name

Outputs:
  VPCId:
    Description: ID of the VPC
    Value: !Ref VPC
    Export:
      Name: !Sub '$${environment_name}-vpc-id'
  
  PublicSubnetIds:
    Description: IDs of the public subnets
    Value: !Join [',', [!Ref PublicSubnet1, !Ref PublicSubnet2]]
    Export:
      Name: !Sub '$${environment_name}-public-subnet-ids'
  
  PrivateSubnetIds:
    Description: IDs of the private subnets
    Value: !Join [',', [!Ref PrivateSubnet1, !Ref PrivateSubnet2]]
    Export:
      Name: !Sub '$${environment_name}-private-subnet-ids'
  
  ClusterName:
    Description: Name of the ECS cluster
    Value: !Ref ECSCluster
    Export:
      Name: !Sub '$${environment_name}-cluster-name'
  
  ClusterArn:
    Description: ARN of the ECS cluster
    Value: !GetAtt ECSCluster.Arn
    Export:
      Name: !Sub '$${environment_name}-cluster-arn'
EOF
}

# Create environment template manifest
resource "local_file" "environment_manifest" {
  filename = "${path.module}/templates/environment-manifest.yaml"
  content = yamlencode({
    infrastructure = {
      templates = [
        {
          file   = "infrastructure.yaml"
          engine = "cloudformation"
        }
      ]
    }
  })
}

# Create template bundle
data "archive_file" "environment_template" {
  type        = "zip"
  output_path = "${path.module}/templates/environment-template.tar.gz"
  
  source {
    content  = local_file.environment_schema.content
    filename = "schema.yaml"
  }
  
  source {
    content  = local_file.environment_infrastructure.content
    filename = "infrastructure.yaml"
  }
  
  source {
    content  = local_file.environment_manifest.content
    filename = "manifest.yaml"
  }
  
  depends_on = [
    local_file.environment_schema,
    local_file.environment_infrastructure,
    local_file.environment_manifest
  ]
}

# Upload template bundle to S3
resource "aws_s3_object" "environment_template" {
  bucket = aws_s3_bucket.proton_templates.id
  key    = "environment-template.tar.gz"
  source = data.archive_file.environment_template.output_path
  etag   = filemd5(data.archive_file.environment_template.output_path)
  
  tags = merge(local.common_tags, {
    Name        = "environment-template.tar.gz"
    Description = "AWS Proton environment template bundle"
  })
}

#
# AWS Proton Environment Template
#
resource "aws_proton_environment_template" "web_app_env" {
  name         = local.environment_template_name
  display_name = var.template_display_name
  description  = var.template_description
  
  tags = merge(local.common_tags, {
    Name        = local.environment_template_name
    Description = "Environment template for web applications"
  })
}

resource "aws_proton_environment_template_version" "web_app_env_v1" {
  template_name = aws_proton_environment_template.web_app_env.name
  description   = "Initial version of web application environment template"
  
  source {
    s3 {
      bucket = aws_s3_bucket.proton_templates.id
      key    = aws_s3_object.environment_template.key
    }
  }
  
  depends_on = [
    aws_s3_object.environment_template
  ]
}

# Wait for template version to be registered before publishing
resource "time_sleep" "wait_for_template_registration" {
  depends_on = [aws_proton_environment_template_version.web_app_env_v1]
  
  create_duration = "30s"
}

# Publish the environment template version
resource "aws_proton_environment_template_version" "web_app_env_v1_published" {
  count = var.auto_publish_template ? 1 : 0
  
  template_name   = aws_proton_environment_template.web_app_env.name
  major_version   = aws_proton_environment_template_version.web_app_env_v1.major_version
  minor_version   = aws_proton_environment_template_version.web_app_env_v1.minor_version
  description     = aws_proton_environment_template_version.web_app_env_v1.description
  status          = "PUBLISHED"
  
  source {
    s3 {
      bucket = aws_s3_bucket.proton_templates.id
      key    = aws_s3_object.environment_template.key
    }
  }
  
  depends_on = [
    time_sleep.wait_for_template_registration
  ]
}

#
# Service Template Files (Basic web application service)
#
resource "local_file" "service_schema" {
  filename = "${path.module}/templates/service-schema.yaml"
  content = yamlencode({
    schema = {
      format = "openapi: \"3.0.0\""
      service_input_type = "ServiceInput"
      types = {
        ServiceInput = {
          type = "object"
          description = "Input properties for the service"
          properties = {
            service_name = {
              type = "string"
              description = "Name of the service"
              minLength = 1
              maxLength = 100
            }
            desired_count = {
              type = "integer"
              description = "Desired number of running tasks"
              default = 2
              minimum = 1
              maximum = 10
            }
            cpu = {
              type = "string"
              description = "CPU units for the task"
              default = "256"
              enum = ["256", "512", "1024", "2048", "4096"]
            }
            memory = {
              type = "string"
              description = "Memory for the task"
              default = "512"
              enum = ["512", "1024", "2048", "4096", "8192"]
            }
            container_image = {
              type = "string"
              description = "Container image URI"
              default = "nginx:latest"
            }
            container_port = {
              type = "integer"
              description = "Port the container listens on"
              default = 80
              minimum = 1
              maximum = 65535
            }
          }
          required = ["service_name"]
        }
      }
    }
  })
}

resource "local_file" "service_infrastructure" {
  filename = "${path.module}/templates/service-infrastructure.yaml"
  content = <<-EOF
AWSTemplateFormatVersion: '2010-09-09'
Description: 'Proton Service Template - ECS Fargate Service'

Parameters:
  service_name:
    Type: String
    Description: Name of the service
    MinLength: 1
    MaxLength: 100
  desired_count:
    Type: Number
    Description: Desired number of running tasks
    Default: 2
    MinValue: 1
    MaxValue: 10
  cpu:
    Type: String
    Description: CPU units for the task
    Default: "256"
    AllowedValues: ["256", "512", "1024", "2048", "4096"]
  memory:
    Type: String
    Description: Memory for the task
    Default: "512"
    AllowedValues: ["512", "1024", "2048", "4096", "8192"]
  container_image:
    Type: String
    Description: Container image URI
    Default: "nginx:latest"
  container_port:
    Type: Number
    Description: Port the container listens on
    Default: 80
    MinValue: 1
    MaxValue: 65535

Resources:
  # Task Definition
  TaskDefinition:
    Type: AWS::ECS::TaskDefinition
    Properties:
      Family: !Sub '$${service_name}-task'
      NetworkMode: awsvpc
      RequiresCompatibilities:
        - FARGATE
      Cpu: !Ref cpu
      Memory: !Ref memory
      ExecutionRoleArn: !Ref TaskExecutionRole
      ContainerDefinitions:
        - Name: !Sub '$${service_name}-container'
          Image: !Ref container_image
          PortMappings:
            - ContainerPort: !Ref container_port
              Protocol: tcp
          LogConfiguration:
            LogDriver: awslogs
            Options:
              awslogs-group: !Ref LogGroup
              awslogs-region: !Ref AWS::Region
              awslogs-stream-prefix: ecs

  # Task Execution Role
  TaskExecutionRole:
    Type: AWS::IAM::Role
    Properties:
      AssumeRolePolicyDocument:
        Version: '2012-10-17'
        Statement:
          - Effect: Allow
            Principal:
              Service: ecs-tasks.amazonaws.com
            Action: sts:AssumeRole
      ManagedPolicyArns:
        - arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy

  # CloudWatch Log Group
  LogGroup:
    Type: AWS::Logs::LogGroup
    Properties:
      LogGroupName: !Sub '/ecs/$${service_name}'
      RetentionInDays: 14

  # Security Group
  ServiceSecurityGroup:
    Type: AWS::EC2::SecurityGroup
    Properties:
      GroupDescription: Security group for the ECS service
      VpcId: !Ref VPCId
      SecurityGroupIngress:
        - IpProtocol: tcp
          FromPort: !Ref container_port
          ToPort: !Ref container_port
          SourceSecurityGroupId: !Ref LoadBalancerSecurityGroup
      Tags:
        - Key: Name
          Value: !Sub '$${service_name}-sg'

  # Load Balancer Security Group
  LoadBalancerSecurityGroup:
    Type: AWS::EC2::SecurityGroup
    Properties:
      GroupDescription: Security group for the Application Load Balancer
      VpcId: !Ref VPCId
      SecurityGroupIngress:
        - IpProtocol: tcp
          FromPort: 80
          ToPort: 80
          CidrIp: 0.0.0.0/0
      Tags:
        - Key: Name
          Value: !Sub '$${service_name}-alb-sg'

  # Application Load Balancer
  LoadBalancer:
    Type: AWS::ElasticLoadBalancingV2::LoadBalancer
    Properties:
      Name: !Sub '$${service_name}-alb'
      Scheme: internet-facing
      Type: application
      SecurityGroups:
        - !Ref LoadBalancerSecurityGroup
      Subnets: !Split [',', !Ref PublicSubnetIds]
      Tags:
        - Key: Name
          Value: !Sub '$${service_name}-alb'

  # Target Group
  TargetGroup:
    Type: AWS::ElasticLoadBalancingV2::TargetGroup
    Properties:
      Name: !Sub '$${service_name}-tg'
      Port: !Ref container_port
      Protocol: HTTP
      VpcId: !Ref VPCId
      TargetType: ip
      HealthCheckPath: /
      HealthCheckIntervalSeconds: 30
      HealthCheckTimeoutSeconds: 5
      HealthyThresholdCount: 2
      UnhealthyThresholdCount: 3

  # Listener
  Listener:
    Type: AWS::ElasticLoadBalancingV2::Listener
    Properties:
      DefaultActions:
        - Type: forward
          TargetGroupArn: !Ref TargetGroup
      LoadBalancerArn: !Ref LoadBalancer
      Port: 80
      Protocol: HTTP

  # ECS Service
  Service:
    Type: AWS::ECS::Service
    DependsOn: Listener
    Properties:
      ServiceName: !Ref service_name
      Cluster: !Ref ClusterName
      TaskDefinition: !Ref TaskDefinition
      DesiredCount: !Ref desired_count
      LaunchType: FARGATE
      NetworkConfiguration:
        AwsvpcConfiguration:
          SecurityGroups:
            - !Ref ServiceSecurityGroup
          Subnets: !Split [',', !Ref PrivateSubnetIds]
          AssignPublicIp: DISABLED
      LoadBalancers:
        - ContainerName: !Sub '$${service_name}-container'
          ContainerPort: !Ref container_port
          TargetGroupArn: !Ref TargetGroup

Outputs:
  ServiceName:
    Description: Name of the ECS service
    Value: !Ref Service
  
  ServiceArn:
    Description: ARN of the ECS service
    Value: !Ref Service
  
  LoadBalancerDNS:
    Description: DNS name of the load balancer
    Value: !GetAtt LoadBalancer.DNSName
  
  LoadBalancerArn:
    Description: ARN of the load balancer
    Value: !Ref LoadBalancer
  
  TargetGroupArn:
    Description: ARN of the target group
    Value: !Ref TargetGroup
EOF
}

resource "local_file" "service_manifest" {
  filename = "${path.module}/templates/service-manifest.yaml"
  content = yamlencode({
    infrastructure = {
      templates = [
        {
          file   = "infrastructure.yaml"
          engine = "cloudformation"
        }
      ]
    }
  })
}

# Create service template bundle
data "archive_file" "service_template" {
  type        = "zip"
  output_path = "${path.module}/templates/service-template.tar.gz"
  
  source {
    content  = local_file.service_schema.content
    filename = "schema.yaml"
  }
  
  source {
    content  = local_file.service_infrastructure.content
    filename = "infrastructure.yaml"
  }
  
  source {
    content  = local_file.service_manifest.content
    filename = "manifest.yaml"
  }
  
  depends_on = [
    local_file.service_schema,
    local_file.service_infrastructure,
    local_file.service_manifest
  ]
}

# Upload service template bundle to S3
resource "aws_s3_object" "service_template" {
  bucket = aws_s3_bucket.proton_templates.id
  key    = "service-template.tar.gz"
  source = data.archive_file.service_template.output_path
  etag   = filemd5(data.archive_file.service_template.output_path)
  
  tags = merge(local.common_tags, {
    Name        = "service-template.tar.gz"
    Description = "AWS Proton service template bundle"
  })
}

#
# AWS Proton Service Template
#
resource "aws_proton_service_template" "web_app_svc" {
  name         = local.service_template_name
  display_name = "Web Application Service"
  description  = "Service template for containerized web applications"
  
  tags = merge(local.common_tags, {
    Name        = local.service_template_name
    Description = "Service template for web applications"
  })
}

resource "aws_proton_service_template_version" "web_app_svc_v1" {
  template_name = aws_proton_service_template.web_app_svc.name
  description   = "Initial version of web application service template"
  
  compatible_environment_templates {
    template_name    = aws_proton_environment_template.web_app_env.name
    major_version    = aws_proton_environment_template_version.web_app_env_v1.major_version
  }
  
  source {
    s3 {
      bucket = aws_s3_bucket.proton_templates.id
      key    = aws_s3_object.service_template.key
    }
  }
  
  depends_on = [
    aws_s3_object.service_template,
    aws_proton_environment_template_version.web_app_env_v1
  ]
}

# Wait for service template version to be registered before publishing
resource "time_sleep" "wait_for_service_template_registration" {
  depends_on = [aws_proton_service_template_version.web_app_svc_v1]
  
  create_duration = "30s"
}

# Publish the service template version
resource "aws_proton_service_template_version" "web_app_svc_v1_published" {
  count = var.auto_publish_template ? 1 : 0
  
  template_name   = aws_proton_service_template.web_app_svc.name
  major_version   = aws_proton_service_template_version.web_app_svc_v1.major_version
  minor_version   = aws_proton_service_template_version.web_app_svc_v1.minor_version
  description     = aws_proton_service_template_version.web_app_svc_v1.description
  status          = "PUBLISHED"
  
  compatible_environment_templates {
    template_name    = aws_proton_environment_template.web_app_env.name
    major_version    = aws_proton_environment_template_version.web_app_env_v1.major_version
  }
  
  source {
    s3 {
      bucket = aws_s3_bucket.proton_templates.id
      key    = aws_s3_object.service_template.key
    }
  }
  
  depends_on = [
    time_sleep.wait_for_service_template_registration
  ]
}