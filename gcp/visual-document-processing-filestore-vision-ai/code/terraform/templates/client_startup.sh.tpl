#!/bin/bash
# Startup script for Filestore client instance
# This script configures the instance to mount Cloud Filestore and sets up directories

set -e

# Configuration from Terraform
FILESTORE_IP="${filestore_ip}"
FILESTORE_SHARE="${filestore_share}"
MOUNT_POINT="/mnt/filestore"

# Logging function
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a /var/log/filestore-setup.log
}

log "Starting Filestore client setup"
log "Filestore IP: $FILESTORE_IP"
log "Filestore Share: $FILESTORE_SHARE"

# Update system packages
log "Updating system packages"
apt-get update -y

# Install NFS utilities
log "Installing NFS utilities"
apt-get install -y nfs-common

# Install additional useful tools
log "Installing additional tools"
apt-get install -y \
    curl \
    wget \
    unzip \
    git \
    htop \
    tree \
    jq \
    python3-pip

# Create mount point
log "Creating mount point: $MOUNT_POINT"
mkdir -p "$MOUNT_POINT"

# Add Filestore to /etc/fstab for persistent mounting
log "Adding Filestore to /etc/fstab"
FSTAB_ENTRY="$FILESTORE_IP:/$FILESTORE_SHARE $MOUNT_POINT nfs defaults,_netdev 0 0"

# Check if entry already exists
if ! grep -q "$FILESTORE_IP:/$FILESTORE_SHARE" /etc/fstab; then
    echo "$FSTAB_ENTRY" >> /etc/fstab
    log "Added Filestore entry to /etc/fstab"
else
    log "Filestore entry already exists in /etc/fstab"
fi

# Mount the Filestore
log "Mounting Filestore"
if mount -t nfs "$FILESTORE_IP:/$FILESTORE_SHARE" "$MOUNT_POINT"; then
    log "Successfully mounted Filestore at $MOUNT_POINT"
else
    log "ERROR: Failed to mount Filestore"
    exit 1
fi

# Create directory structure for different document types
log "Creating document directory structure"
mkdir -p "$MOUNT_POINT"/{invoices,receipts,contracts,forms,reports,incoming,processed}

# Set appropriate permissions
log "Setting directory permissions"
chmod 755 "$MOUNT_POINT"
chmod 755 "$MOUNT_POINT"/*

# Create sample documents for testing
log "Creating sample documents for testing"

# Sample invoice
cat > "$MOUNT_POINT/invoices/sample_invoice.txt" << 'EOF'
INVOICE #INV-2025-001

Date: 2025-01-15
Bill To: Acme Corporation
123 Business Street
Business City, BC 12345

Description                  Qty    Rate      Amount
------------------------------------------------
Cloud Infrastructure         1     $500.00   $500.00
Professional Services        10    $150.00   $1,500.00
Support Services             5     $100.00   $500.00

                           Subtotal: $2,500.00
                               Tax: $250.00
                             Total: $2,750.00

Payment Terms: Net 30 days
Thank you for your business!
EOF

# Sample receipt
cat > "$MOUNT_POINT/receipts/sample_receipt.txt" << 'EOF'
RECEIPT

TechMart Electronics
456 Shopping Blvd
Mall City, MC 67890
Phone: (555) 123-4567

Date: 01/15/2025
Time: 14:30:25
Transaction #: TXN789012

Item                        Price
--------------------------------
Wireless Keyboard           $45.99
USB Mouse                   $19.99
Monitor Stand               $29.99

Subtotal:                   $95.97
Sales Tax (8.5%):           $8.16
Total:                     $104.13

Payment Method: Credit Card
Card: **** **** **** 1234

Thank you for shopping!
EOF

# Sample contract
cat > "$MOUNT_POINT/contracts/sample_contract.txt" << 'EOF'
SERVICE AGREEMENT

This Agreement is entered into on January 15, 2025
between TechServices Inc. ("Service Provider")
and Acme Corporation ("Client").

1. SCOPE OF SERVICES
Service Provider agrees to provide cloud
infrastructure management and support services
as detailed in Exhibit A.

2. TERM
This Agreement shall commence on February 1, 2025
and continue for a period of twelve (12) months.

3. COMPENSATION
Client agrees to pay Service Provider a monthly
fee of $5,000.00 for the services provided.

4. CONFIDENTIALITY
Both parties agree to maintain confidentiality
of proprietary information shared during
the performance of this Agreement.

By signing below, parties agree to the terms.

_________________________    _________________________
Service Provider              Client
Date: _______________        Date: _______________
EOF

# Create README file with instructions
cat > "$MOUNT_POINT/README.md" << 'EOF'
# Document Processing Filestore

This Filestore instance is configured for automated document processing using Google Cloud Vision AI.

## Directory Structure

- `invoices/` - Invoice documents
- `receipts/` - Receipt documents  
- `contracts/` - Contract documents
- `forms/` - Form documents
- `reports/` - Report documents
- `incoming/` - New documents for processing
- `processed/` - Documents that have been processed

## Usage

1. Upload documents to the appropriate directory based on type
2. The monitoring function will detect new files and trigger processing
3. Results will be available in Cloud Storage and Pub/Sub topics

## Sample Documents

Sample documents have been created in each directory for testing purposes.

## Commands

To test the processing pipeline:

```bash
# Test document processing
gcloud pubsub topics publish TOPIC_NAME --message='{"filename":"test.pdf","filepath":"/mnt/filestore/invoices/test.pdf"}'

# View function logs
gcloud functions logs read FUNCTION_NAME --region=REGION

# List processed results
gsutil ls -r gs://RESULTS_BUCKET/processed/
```

## Support

For issues or questions, check the Cloud Functions logs and monitoring dashboards.
EOF

# Install Google Cloud SDK
log "Installing Google Cloud SDK"
curl https://sdk.cloud.google.com | bash
exec -l $SHELL

# Add gcloud to PATH for all users
echo 'export PATH=/root/google-cloud-sdk/bin:$PATH' >> /etc/bash.bashrc

# Create useful aliases
log "Creating useful aliases"
cat >> /home/$(logname)/.bashrc << 'EOF'

# Filestore aliases
alias ll='ls -la'
alias fs='cd /mnt/filestore'
alias fsl='ls -la /mnt/filestore'
alias fsspace='df -h /mnt/filestore'

# Google Cloud aliases
alias gcflist='gcloud functions list'
alias gcslist='gsutil ls'
alias gpublist='gcloud pubsub topics list'

# Document processing aliases
alias upload-test='echo "Upload a file to /mnt/filestore/incoming/ to test processing"'
alias check-logs='echo "Use: gcloud functions logs read FUNCTION_NAME --region=REGION"'
alias check-results='echo "Use: gsutil ls -r gs://RESULTS_BUCKET/processed/"'
EOF

# Create a simple file monitoring script
log "Creating file monitoring script"
cat > /usr/local/bin/watch-filestore << 'EOF'
#!/bin/bash
# Simple script to monitor Filestore for new files

MOUNT_POINT="/mnt/filestore"
WATCH_DIR="$MOUNT_POINT/incoming"

echo "Monitoring $WATCH_DIR for new files..."
echo "Press Ctrl+C to stop"

inotifywait -m -r -e create,moved_to "$WATCH_DIR" --format '%w%f %e' |
while read FILE EVENT; do
    echo "[$(date)] New file detected: $FILE ($EVENT)"
    # Here you could trigger additional processing if needed
done
EOF

chmod +x /usr/local/bin/watch-filestore

# Install inotify-tools for file monitoring
apt-get install -y inotify-tools

# Create a system service for file monitoring (optional)
cat > /etc/systemd/system/filestore-monitor.service << 'EOF'
[Unit]
Description=Filestore File Monitor
After=network.target

[Service]
Type=simple
User=root
ExecStart=/usr/local/bin/watch-filestore
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

# Enable and start the monitoring service
systemctl daemon-reload
systemctl enable filestore-monitor.service

# Display system information
log "System setup completed"
log "Filestore mounted at: $MOUNT_POINT"
log "Available space: $(df -h $MOUNT_POINT | tail -1 | awk '{print $4}')"
log "Directory structure:"
tree "$MOUNT_POINT" -L 2 || ls -la "$MOUNT_POINT"

# Create a welcome message
cat > /etc/motd << 'EOF'

=====================================
   Document Processing Client
=====================================

Filestore is mounted at: /mnt/filestore

Quick commands:
  fs        - Go to filestore directory
  fsl       - List filestore contents
  fsspace   - Check available space
  
File monitoring:
  watch-filestore - Monitor incoming directory

For help, see: /mnt/filestore/README.md

=====================================
EOF

log "Filestore client setup completed successfully"

# Test the mount and create a status file
echo "Filestore setup completed at $(date)" > "$MOUNT_POINT/setup-status.txt"
echo "Setup completed successfully" > /var/log/startup-script-completed

log "All setup tasks completed successfully"