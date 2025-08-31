{
  "widgets": [
    {
      "type": "metric",
      "x": 0,
      "y": 0,
      "width": 12,
      "height": 6,
      "properties": {
        "metrics": [
          [ "VPCLattice/CostAnalytics", "TotalCost" ],
          [ ".", "TotalRequests" ]
        ],
        "period": 86400,
        "stat": "Sum",
        "region": "${aws_region}",
        "title": "VPC Lattice Cost and Traffic Overview",
        "yAxis": {
          "left": {
            "min": 0
          }
        },
        "view": "timeSeries",
        "stacked": false
      }
    },
    {
      "type": "metric",
      "x": 12,
      "y": 0,
      "width": 12,
      "height": 6,
      "properties": {
        "metrics": [
          [ "VPCLattice/CostAnalytics", "CostPerRequest" ]
        ],
        "period": 86400,
        "stat": "Average",
        "region": "${aws_region}",
        "title": "Cost Per Request Efficiency",
        "yAxis": {
          "left": {
            "min": 0
          }
        },
        "view": "timeSeries"
      }
    }%{ if enable_demo_lattice },
    {
      "type": "metric",
      "x": 0,
      "y": 6,
      "width": 24,
      "height": 6,
      "properties": {
        "metrics": [
          [ "AWS/VpcLattice", "TotalRequestCount", "ServiceNetwork", "${service_network_id}" ],
          [ ".", "ActiveConnectionCount", ".", "." ],
          [ ".", "TotalConnectionCount", ".", "." ]
        ],
        "period": 300,
        "stat": "Sum",
        "region": "${aws_region}",
        "title": "VPC Lattice Service Network Traffic Metrics",
        "view": "timeSeries"
      }
    }%{ endif },
    {
      "type": "log",
      "x": 0,
      "y": %{ if enable_demo_lattice }12%{ else }6%{ endif },
      "width": 24,
      "height": 6,
      "properties": {
        "query": "SOURCE '/aws/lambda/lattice-cost-processor'\n| fields @timestamp, @message\n| filter @message like /Cost analytics/\n| sort @timestamp desc\n| limit 100",
        "region": "${aws_region}",
        "title": "Cost Analytics Lambda Logs",
        "view": "table"
      }
    },
    {
      "type": "metric",
      "x": 0,
      "y": %{ if enable_demo_lattice }18%{ else }12%{ endif },
      "width": 12,
      "height": 6,
      "properties": {
        "metrics": [
          [ "AWS/Lambda", "Duration", "FunctionName", "lattice-cost-processor" ],
          [ ".", "Errors", ".", "." ],
          [ ".", "Invocations", ".", "." ]
        ],
        "period": 300,
        "stat": "Average",
        "region": "${aws_region}",
        "title": "Lambda Function Performance",
        "view": "timeSeries"
      }
    },
    {
      "type": "metric",
      "x": 12,
      "y": %{ if enable_demo_lattice }18%{ else }12%{ endif },
      "width": 12,
      "height": 6,
      "properties": {
        "metrics": [
          [ "AWS/S3", "BucketSizeBytes", "BucketName", "lattice-analytics", "StorageType", "StandardStorage" ],
          [ ".", "NumberOfObjects", ".", ".", ".", "AllStorageTypes" ]
        ],
        "period": 86400,
        "stat": "Average",
        "region": "${aws_region}",
        "title": "Analytics Data Storage Metrics",
        "view": "timeSeries"
      }
    }
  ]
}