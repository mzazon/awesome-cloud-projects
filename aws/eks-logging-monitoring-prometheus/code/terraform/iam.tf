# IAM roles and policies for EKS cluster logging and monitoring

# EKS Cluster Service Role
resource "aws_iam_role" "cluster_service_role" {
  name = "${local.cluster_name_unique}-cluster-service-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "eks.amazonaws.com"
        }
      }
    ]
  })

  tags = local.common_tags
}

# Attach required policies to cluster service role
resource "aws_iam_role_policy_attachment" "cluster_service_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
  role       = aws_iam_role.cluster_service_role.name
}

# EKS Node Group Role
resource "aws_iam_role" "node_group_role" {
  name = "${local.cluster_name_unique}-node-group-role"

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

  tags = local.common_tags
}

# Attach required policies to node group role
resource "aws_iam_role_policy_attachment" "node_group_worker_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
  role       = aws_iam_role.node_group_role.name
}

resource "aws_iam_role_policy_attachment" "node_group_cni_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
  role       = aws_iam_role.node_group_role.name
}

resource "aws_iam_role_policy_attachment" "node_group_registry_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
  role       = aws_iam_role.node_group_role.name
}

# CloudWatch Agent Role for IRSA
resource "aws_iam_role" "cloudwatch_agent_role" {
  count = var.enable_irsa ? 1 : 0
  
  name = "${local.cluster_name_unique}-cloudwatch-agent-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Federated = aws_iam_openid_connect_provider.eks[0].arn
        }
        Action = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringEquals = {
            "${replace(aws_iam_openid_connect_provider.eks[0].url, "https://", "")}:sub" = "system:serviceaccount:amazon-cloudwatch:cloudwatch-agent"
          }
        }
      }
    ]
  })

  tags = local.common_tags
}

# Attach CloudWatch Agent policy
resource "aws_iam_role_policy_attachment" "cloudwatch_agent_policy" {
  count = var.enable_irsa ? 1 : 0
  
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
  role       = aws_iam_role.cloudwatch_agent_role[0].name
}

# Custom policy for CloudWatch Logs and Container Insights
resource "aws_iam_policy" "cloudwatch_logs_policy" {
  count = var.enable_irsa ? 1 : 0
  
  name        = "${local.cluster_name_unique}-cloudwatch-logs-policy"
  description = "Policy for CloudWatch Logs and Container Insights"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "logs:DescribeLogGroups",
          "logs:DescribeLogStreams",
          "cloudwatch:PutMetricData",
          "ec2:DescribeInstances",
          "ec2:DescribeVolumes",
          "ec2:DescribeTags",
          "eks:DescribeCluster"
        ]
        Resource = "*"
      }
    ]
  })

  tags = local.common_tags
}

# Attach custom CloudWatch Logs policy
resource "aws_iam_role_policy_attachment" "cloudwatch_logs_policy_attachment" {
  count = var.enable_irsa ? 1 : 0
  
  policy_arn = aws_iam_policy.cloudwatch_logs_policy[0].arn
  role       = aws_iam_role.cloudwatch_agent_role[0].name
}

# Prometheus Scraper Role (for managed scraper)
resource "aws_iam_role" "prometheus_scraper_role" {
  count = var.enable_prometheus ? 1 : 0
  
  name = "${local.cluster_name_unique}-prometheus-scraper-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "aps.amazonaws.com"
        }
      }
    ]
  })

  tags = local.common_tags
}

# Attach Prometheus scraper policy
resource "aws_iam_role_policy_attachment" "prometheus_scraper_policy" {
  count = var.enable_prometheus ? 1 : 0
  
  policy_arn = "arn:aws:iam::aws:policy/AmazonPrometheusRemoteWriteAccess"
  role       = aws_iam_role.prometheus_scraper_role[0].name
}

# Additional permissions for EKS cluster access
resource "aws_iam_policy" "prometheus_eks_access" {
  count = var.enable_prometheus ? 1 : 0
  
  name        = "${local.cluster_name_unique}-prometheus-eks-access"
  description = "Policy for Prometheus scraper to access EKS cluster"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "eks:DescribeCluster",
          "eks:ListClusters",
          "eks:DescribeNodegroup",
          "eks:ListNodegroups",
          "ec2:DescribeInstances",
          "ec2:DescribeSecurityGroups",
          "ec2:DescribeSubnets",
          "ec2:DescribeVpcs"
        ]
        Resource = "*"
      }
    ]
  })

  tags = local.common_tags
}

# Attach EKS access policy to Prometheus scraper role
resource "aws_iam_role_policy_attachment" "prometheus_eks_access_attachment" {
  count = var.enable_prometheus ? 1 : 0
  
  policy_arn = aws_iam_policy.prometheus_eks_access[0].arn
  role       = aws_iam_role.prometheus_scraper_role[0].name
}

# SNS Topic for CloudWatch Alarms
resource "aws_sns_topic" "cloudwatch_alarms" {
  count = var.enable_cloudwatch_alarms && var.enable_sns_alerts ? 1 : 0
  
  name = "${local.cluster_name_unique}-cloudwatch-alarms"

  tags = local.common_tags
}

# SNS Topic Subscription (if endpoint is provided)
resource "aws_sns_topic_subscription" "cloudwatch_alarms_email" {
  count = var.enable_cloudwatch_alarms && var.enable_sns_alerts && var.sns_endpoint != "" ? 1 : 0
  
  topic_arn = aws_sns_topic.cloudwatch_alarms[0].arn
  protocol  = "email"
  endpoint  = var.sns_endpoint
}