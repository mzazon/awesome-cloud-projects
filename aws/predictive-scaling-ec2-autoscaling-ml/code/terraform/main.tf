# Data sources for existing resources
data "aws_availability_zones" "available" {
  state = "available"
}

data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }

  filter {
    name   = "state"
    values = ["available"]
  }
}

data "aws_caller_identity" "current" {}

# Random suffix for unique resource names
resource "random_string" "suffix" {
  length  = 8
  special = false
  upper   = false
}

# VPC Configuration
resource "aws_vpc" "main" {
  count = var.create_vpc ? 1 : 0

  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = merge(
    {
      Name = "${var.name_prefix}-vpc-${random_string.suffix.result}"
    },
    var.additional_tags
  )
}

resource "aws_internet_gateway" "main" {
  count = var.create_vpc ? 1 : 0

  vpc_id = aws_vpc.main[0].id

  tags = merge(
    {
      Name = "${var.name_prefix}-igw-${random_string.suffix.result}"
    },
    var.additional_tags
  )
}

resource "aws_subnet" "public" {
  count = var.create_vpc ? length(var.public_subnet_cidrs) : 0

  vpc_id                  = aws_vpc.main[0].id
  cidr_block              = var.public_subnet_cidrs[count.index]
  availability_zone       = data.aws_availability_zones.available.names[count.index]
  map_public_ip_on_launch = true

  tags = merge(
    {
      Name = "${var.name_prefix}-public-subnet-${count.index + 1}-${random_string.suffix.result}"
      Type = "Public"
    },
    var.additional_tags
  )
}

resource "aws_route_table" "public" {
  count = var.create_vpc ? 1 : 0

  vpc_id = aws_vpc.main[0].id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main[0].id
  }

  tags = merge(
    {
      Name = "${var.name_prefix}-public-rt-${random_string.suffix.result}"
    },
    var.additional_tags
  )
}

resource "aws_route_table_association" "public" {
  count = var.create_vpc ? length(aws_subnet.public) : 0

  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public[0].id
}

# Security Group for EC2 instances
resource "aws_security_group" "ec2" {
  name_prefix = "${var.name_prefix}-ec2-"
  vpc_id      = var.create_vpc ? aws_vpc.main[0].id : var.existing_vpc_id
  description = "Security group for EC2 instances in Auto Scaling Group"

  ingress {
    description = "HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTPS"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(
    {
      Name = "${var.name_prefix}-ec2-sg-${random_string.suffix.result}"
    },
    var.additional_tags
  )

  lifecycle {
    create_before_destroy = true
  }
}

# IAM Role for EC2 instances
resource "aws_iam_role" "ec2_role" {
  name_prefix = "${var.name_prefix}-ec2-role-"

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

  tags = merge(
    {
      Name = "${var.name_prefix}-ec2-role-${random_string.suffix.result}"
    },
    var.additional_tags
  )
}

# Attach CloudWatch Agent policy to EC2 role
resource "aws_iam_role_policy_attachment" "cloudwatch_agent" {
  role       = aws_iam_role.ec2_role.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
}

# Attach Systems Manager policy for session manager access
resource "aws_iam_role_policy_attachment" "ssm_managed_instance" {
  role       = aws_iam_role.ec2_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# IAM instance profile
resource "aws_iam_instance_profile" "ec2_profile" {
  name_prefix = "${var.name_prefix}-ec2-profile-"
  role        = aws_iam_role.ec2_role.name

  tags = merge(
    {
      Name = "${var.name_prefix}-ec2-profile-${random_string.suffix.result}"
    },
    var.additional_tags
  )
}

# User data script for EC2 instances
locals {
  user_data = base64encode(templatefile("${path.module}/user_data.sh", {
    region = var.aws_region
  }))
}

# Create user data script file
resource "local_file" "user_data_script" {
  filename = "${path.module}/user_data.sh"
  content  = <<-EOF
#!/bin/bash
yum update -y
yum install -y httpd stress

# Start and enable Apache
systemctl start httpd
systemctl enable httpd

# Create simple web page
cat > /var/www/html/index.html << 'HTML'
<!DOCTYPE html>
<html>
<head>
    <title>Predictive Scaling Demo</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 40px; }
        .container { max-width: 800px; margin: 0 auto; }
        .info-box { background: #f0f0f0; padding: 20px; border-radius: 5px; margin: 20px 0; }
    </style>
</head>
<body>
    <div class="container">
        <h1>🚀 Predictive Scaling Demo</h1>
        <div class="info-box">
            <h3>Instance Information</h3>
            <p><strong>Instance ID:</strong> <span id="instance-id">Loading...</span></p>
            <p><strong>Availability Zone:</strong> <span id="az">Loading...</span></p>
            <p><strong>Instance Type:</strong> <span id="instance-type">Loading...</span></p>
            <p><strong>Current Time:</strong> <span id="current-time"></span></p>
        </div>
        <div class="info-box">
            <h3>Predictive Scaling Status</h3>
            <p>This instance is part of an Auto Scaling Group using AWS's predictive scaling capabilities.</p>
            <p>The system uses machine learning to forecast future capacity needs based on historical patterns.</p>
        </div>
    </div>

    <script>
        // Update current time
        function updateTime() {
            document.getElementById('current-time').textContent = new Date().toLocaleString();
        }
        updateTime();
        setInterval(updateTime, 1000);

        // Fetch instance metadata
        fetch('http://169.254.169.254/latest/meta-data/instance-id')
            .then(response => response.text())
            .then(data => document.getElementById('instance-id').textContent = data)
            .catch(() => document.getElementById('instance-id').textContent = 'Unable to fetch');

        fetch('http://169.254.169.254/latest/meta-data/placement/availability-zone')
            .then(response => response.text())
            .then(data => document.getElementById('az').textContent = data)
            .catch(() => document.getElementById('az').textContent = 'Unable to fetch');

        fetch('http://169.254.169.254/latest/meta-data/instance-type')
            .then(response => response.text())
            .then(data => document.getElementById('instance-type').textContent = data)
            .catch(() => document.getElementById('instance-type').textContent = 'Unable to fetch');
    </script>
</body>
</html>
HTML

# Install and configure CloudWatch agent
yum install -y amazon-cloudwatch-agent

# Create CloudWatch agent configuration
cat > /opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json << 'CW_CONFIG'
{
    "metrics": {
        "namespace": "CWAgent",
        "metrics_collected": {
            "cpu": {
                "measurement": [
                    "cpu_usage_idle",
                    "cpu_usage_iowait",
                    "cpu_usage_user",
                    "cpu_usage_system"
                ],
                "metrics_collection_interval": 60,
                "resources": [
                    "*"
                ],
                "totalcpu": false
            },
            "disk": {
                "measurement": [
                    "used_percent"
                ],
                "metrics_collection_interval": 60,
                "resources": [
                    "*"
                ]
            },
            "diskio": {
                "measurement": [
                    "io_time",
                    "read_bytes",
                    "write_bytes",
                    "reads",
                    "writes"
                ],
                "metrics_collection_interval": 60,
                "resources": [
                    "*"
                ]
            },
            "mem": {
                "measurement": [
                    "mem_used_percent"
                ],
                "metrics_collection_interval": 60
            }
        }
    }
}
CW_CONFIG

# Start CloudWatch agent
/opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl \
    -a fetch-config \
    -m ec2 \
    -c file:/opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json \
    -s

# Create scheduled CPU load for predictive scaling demonstration
# This creates predictable load patterns that help train the ML algorithms
cat > /etc/cron.d/predictive-load << 'CRON_CONFIG'
# Create CPU load during business hours (9 AM - 6 PM UTC) on weekdays
# This simulates a typical business application load pattern
0 9 * * 1-5 root timeout 8h stress --cpu 2 --quiet &
0 18 * * 1-5 root pkill stress

# Create moderate load during weekends (10 AM - 4 PM UTC)
0 10 * * 6,0 root timeout 6h stress --cpu 1 --quiet &
0 16 * * 6,0 root pkill stress

# Brief spike every 4 hours to create additional pattern variation
0 */4 * * * root timeout 30m stress --cpu 3 --quiet &
CRON_CONFIG

# Ensure stress tool is available
which stress || yum install -y stress

# Log successful completion
echo "$(date): User data script completed successfully" >> /var/log/user-data.log
EOF
}

# Launch Template for Auto Scaling Group
resource "aws_launch_template" "main" {
  name_prefix   = "${var.name_prefix}-lt-"
  image_id      = data.aws_ami.amazon_linux.id
  instance_type = var.instance_type

  vpc_security_group_ids = [aws_security_group.ec2.id]

  iam_instance_profile {
    name = aws_iam_instance_profile.ec2_profile.name
  }

  monitoring {
    enabled = var.enable_detailed_monitoring
  }

  user_data = local.user_data

  tag_specifications {
    resource_type = "instance"
    tags = merge(
      {
        Name = "${var.name_prefix}-instance"
      },
      var.additional_tags
    )
  }

  tag_specifications {
    resource_type = "volume"
    tags = merge(
      {
        Name = "${var.name_prefix}-volume"
      },
      var.additional_tags
    )
  }

  tags = merge(
    {
      Name = "${var.name_prefix}-launch-template-${random_string.suffix.result}"
    },
    var.additional_tags
  )

  lifecycle {
    create_before_destroy = true
  }
}

# Auto Scaling Group
resource "aws_autoscaling_group" "main" {
  name                = "${var.name_prefix}-asg-${random_string.suffix.result}"
  vpc_zone_identifier = var.create_vpc ? aws_subnet.public[*].id : var.existing_subnet_ids
  min_size            = var.min_size
  max_size            = var.max_size
  desired_capacity    = var.desired_capacity
  health_check_type   = "EC2"
  health_check_grace_period = 300
  default_instance_warmup   = var.instance_warmup_time

  launch_template {
    id      = aws_launch_template.main.id
    version = "$Latest"
  }

  # Enable instance scale-in protection during predictive scaling
  protect_from_scale_in = false

  tag {
    key                 = "Name"
    value               = "${var.name_prefix}-asg-${random_string.suffix.result}"
    propagate_at_launch = false
  }

  dynamic "tag" {
    for_each = var.additional_tags
    content {
      key                 = tag.key
      value               = tag.value
      propagate_at_launch = false
    }
  }

  lifecycle {
    create_before_destroy = true
    ignore_changes       = [desired_capacity]
  }
}

# Target Tracking Scaling Policy
resource "aws_autoscaling_policy" "target_tracking" {
  name                   = "${var.name_prefix}-target-tracking-policy"
  scaling_adjustment     = 0
  adjustment_type        = "PercentChangeInCapacity"
  cooldown               = 300
  autoscaling_group_name = aws_autoscaling_group.main.name
  policy_type            = "TargetTrackingScaling"

  target_tracking_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ASGAverageCPUUtilization"
    }
    target_value     = var.target_cpu_utilization
    disable_scale_in = false
  }
}

# Predictive Scaling Policy
resource "aws_autoscaling_policy" "predictive_scaling" {
  name                   = "${var.name_prefix}-predictive-scaling-policy"
  autoscaling_group_name = aws_autoscaling_group.main.name
  policy_type            = "PredictiveScaling"

  predictive_scaling_configuration {
    metric_specification {
      target_value = var.target_cpu_utilization
      predefined_scaling_metric_specification {
        predefined_metric_type = "ASGAverageCPUUtilization"
        resource_label         = aws_autoscaling_group.main.arn
      }
      predefined_load_metric_specification {
        predefined_metric_type = "ASGTotalCPUUtilization"
        resource_label         = aws_autoscaling_group.main.arn
      }
    }
    mode                         = var.predictive_scaling_mode
    scheduling_buffer_time       = var.predictive_scaling_buffer_time
    max_capacity_breach_behavior = "IncreaseMaxCapacity"
    max_capacity_buffer          = var.predictive_scaling_max_capacity_buffer
  }
}

# CloudWatch Dashboard (optional)
resource "aws_cloudwatch_dashboard" "main" {
  count = var.create_dashboard ? 1 : 0

  dashboard_name = "${var.name_prefix}-dashboard-${random_string.suffix.result}"

  dashboard_body = jsonencode({
    widgets = [
      {
        type   = "metric"
        x      = 0
        y      = 0
        width  = 12
        height = 6

        properties = {
          metrics = [
            ["AWS/EC2", "CPUUtilization", "AutoScalingGroupName", aws_autoscaling_group.main.name, { "stat" = "Average" }],
            ["AWS/AutoScaling", "GroupInServiceInstances", "AutoScalingGroupName", aws_autoscaling_group.main.name],
            ["AWS/AutoScaling", "GroupDesiredCapacity", "AutoScalingGroupName", aws_autoscaling_group.main.name],
            ["AWS/AutoScaling", "GroupMaxSize", "AutoScalingGroupName", aws_autoscaling_group.main.name],
            ["AWS/AutoScaling", "GroupMinSize", "AutoScalingGroupName", aws_autoscaling_group.main.name]
          ]
          period = 300
          stat   = "Average"
          region = var.aws_region
          title  = "Auto Scaling Group Metrics"
          view   = "timeSeries"
          yAxis = {
            left = {
              min = 0
              max = var.max_size + 2
            }
          }
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 0
        width  = 12
        height = 6

        properties = {
          metrics = [
            ["AWS/AutoScaling", "GroupPendingInstances", "AutoScalingGroupName", aws_autoscaling_group.main.name],
            [".", "GroupTerminatingInstances", ".", "."],
            [".", "GroupStandbyInstances", ".", "."]
          ]
          period = 300
          stat   = "Sum"
          region = var.aws_region
          title  = "Auto Scaling Group Instance States"
          view   = "timeSeries"
        }
      },
      {
        type   = "log"
        x      = 0
        y      = 6
        width  = 24
        height = 6

        properties = {
          query   = "SOURCE '/aws/autoscaling/scaling-activities' | fields @timestamp, @message | filter @message like /${aws_autoscaling_group.main.name}/ | sort @timestamp desc | limit 100"
          region  = var.aws_region
          title   = "Auto Scaling Activities"
          view    = "table"
        }
      }
    ]
  })
}

# CloudWatch Alarms for monitoring
resource "aws_cloudwatch_metric_alarm" "high_cpu" {
  alarm_name          = "${var.name_prefix}-high-cpu-${random_string.suffix.result}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = "300"
  statistic           = "Average"
  threshold           = "80"
  alarm_description   = "This metric monitors ec2 cpu utilization"
  alarm_actions       = []

  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.main.name
  }

  tags = merge(
    {
      Name = "${var.name_prefix}-high-cpu-alarm-${random_string.suffix.result}"
    },
    var.additional_tags
  )
}

resource "aws_cloudwatch_metric_alarm" "low_cpu" {
  alarm_name          = "${var.name_prefix}-low-cpu-${random_string.suffix.result}"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = "300"
  statistic           = "Average"
  threshold           = "10"
  alarm_description   = "This metric monitors ec2 cpu utilization for scale down"
  alarm_actions       = []

  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.main.name
  }

  tags = merge(
    {
      Name = "${var.name_prefix}-low-cpu-alarm-${random_string.suffix.result}"
    },
    var.additional_tags
  )
}