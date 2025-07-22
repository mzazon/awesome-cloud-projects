#!/bin/bash
# Bootstrap script for installing Deequ on EMR cluster
# This script is executed on all cluster nodes during bootstrap

set -e

echo "Starting Deequ installation..."

# Create log file for bootstrap actions
LOG_FILE="/tmp/deequ-bootstrap.log"
exec > >(tee -a $LOG_FILE)
exec 2>&1

echo "$(date): Starting Deequ bootstrap script"

# Download and install Deequ JAR
echo "$(date): Creating Spark jars directory"
sudo mkdir -p /usr/lib/spark/jars

echo "$(date): Downloading Deequ JAR version ${deequ_version}"
sudo wget -O /usr/lib/spark/jars/deequ-${deequ_version}.jar \
    https://repo1.maven.org/maven2/com/amazon/deequ/deequ/${deequ_version}/deequ-${deequ_version}.jar

# Verify download
if [ -f "/usr/lib/spark/jars/deequ-${deequ_version}.jar" ]; then
    echo "$(date): Deequ JAR downloaded successfully"
    ls -la /usr/lib/spark/jars/deequ-${deequ_version}.jar
else
    echo "$(date): ERROR: Failed to download Deequ JAR"
    exit 1
fi

# Install required Python packages
echo "$(date): Installing Python packages"
sudo pip3 install boto3 pyarrow pandas numpy --upgrade

# Create directories for custom scripts
echo "$(date): Creating custom script directories"
sudo mkdir -p /opt/deequ-scripts
sudo chmod 755 /opt/deequ-scripts

# Set up Spark configuration for Deequ
echo "$(date): Configuring Spark for Deequ"
sudo tee -a /etc/spark/conf/spark-defaults.conf << EOF

# Deequ specific configurations
spark.jars /usr/lib/spark/jars/deequ-${deequ_version}.jar
spark.sql.extensions io.delta.sql.DeltaSparkSessionExtension
spark.sql.catalog.spark_catalog org.apache.spark.sql.delta.catalog.DeltaCatalog
EOF

# Verify Python packages installation
echo "$(date): Verifying Python package installations"
python3 -c "import boto3, pandas, numpy; print('All Python packages installed successfully')" || {
    echo "$(date): ERROR: Python package installation failed"
    exit 1
}

echo "$(date): Deequ installation completed successfully"
echo "$(date): Bootstrap script finished"