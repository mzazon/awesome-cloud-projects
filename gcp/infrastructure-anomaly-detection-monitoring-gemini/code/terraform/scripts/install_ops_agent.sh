#!/bin/bash

# Infrastructure Anomaly Detection with Cloud Monitoring and Gemini
# Script to install Google Cloud Ops Agent for enhanced monitoring

set -e

echo "🔧 Installing Google Cloud Ops Agent..."

# Download and install the Ops Agent
curl -sSO https://dl.google.com/cloudagents/add-google-cloud-ops-agent-repo.sh
sudo bash add-google-cloud-ops-agent-repo.sh --also-install

# Clean up download
rm -f add-google-cloud-ops-agent-repo.sh

# Verify installation
if systemctl is-active --quiet google-cloud-ops-agent; then
    echo "✅ Google Cloud Ops Agent installed and running successfully"
    systemctl status google-cloud-ops-agent --no-pager
else
    echo "❌ Google Cloud Ops Agent installation failed"
    exit 1
fi

# Configure additional monitoring (optional)
echo "📊 Configuring additional monitoring capabilities..."

# Create custom application metrics directory
sudo mkdir -p /opt/google-cloud-ops-agent/etc/google-cloud-ops-agent/config.d

# Enable additional system monitoring
cat << 'EOF' | sudo tee /etc/google-cloud-ops-agent/config.yaml
logging:
  receivers:
    syslog:
      type: files
      include_paths:
        - /var/log/syslog
        - /var/log/messages
      exclude_paths:
        - /var/log/secure
  processors:
    batch:
      timeout: 1s
      send_batch_size: 50
  exporters:
    google:
      type: google_cloud_logging
  service:
    pipelines:
      default_pipeline:
        receivers: [syslog]
        processors: [batch]
        exporters: [google]

metrics:
  receivers:
    hostmetrics:
      type: hostmetrics
      collection_interval: 60s
      scrapers:
        cpu:
          metrics:
            system.cpu.utilization:
              enabled: true
            system.cpu.time:
              enabled: true
        memory:
          metrics:
            system.memory.usage:
              enabled: true
            system.memory.utilization:
              enabled: true
        disk:
          metrics:
            system.disk.io:
              enabled: true
            system.disk.operations:
              enabled: true
            system.disk.io_time:
              enabled: true
        network:
          metrics:
            system.network.io:
              enabled: true
            system.network.connections:
              enabled: true
        processes:
          metrics:
            system.processes.count:
              enabled: true
            system.processes.created:
              enabled: true
  processors:
    batch:
      timeout: 1s
      send_batch_size: 50
  exporters:
    google:
      type: google_cloud_monitoring
      metric_labels:
        environment: "anomaly-detection-test"
        instance_type: "monitoring-test"
  service:
    pipelines:
      default_pipeline:
        receivers: [hostmetrics]
        processors: [batch]
        exporters: [google]
EOF

# Restart the Ops Agent to apply new configuration
sudo systemctl restart google-cloud-ops-agent

echo "✅ Google Cloud Ops Agent configuration completed"
echo "📈 Enhanced monitoring is now active for this instance"