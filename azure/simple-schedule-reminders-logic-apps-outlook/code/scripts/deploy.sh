#!/bin/bash

# Deploy script for Simple Schedule Reminders with Logic Apps and Outlook
# This script creates Azure resources for automated email reminder workflows

set -euo pipefail  # Exit on error, undefined vars, pipe failures

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/deploy.log"
DEPLOYMENT_STATE_FILE="${SCRIPT_DIR}/.deployment_state"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${2:-}$(date '+%Y-%m-%d %H:%M:%S') - $1${NC}" | tee -a "$LOG_FILE"
}

log_info() {
    log "$1" "$BLUE"
}

log_success() {
    log "$1" "$GREEN"
}

log_warning() {
    log "$1" "$YELLOW"
}

log_error() {
    log "$1" "$RED"
}

# Cleanup function for error handling
cleanup_on_error() {
    local exit_code=$?
    log_error "Deployment failed with exit code $exit_code"
    log_info "Cleaning up resources created during failed deployment..."
    
    if [[ -f "$DEPLOYMENT_STATE_FILE" ]]; then
        source "$DEPLOYMENT_STATE_FILE"
        if [[ -n "${RESOURCE_GROUP:-}" ]]; then
            log_info "Removing resource group: $RESOURCE_GROUP"
            az group delete --name "$RESOURCE_GROUP" --yes --no-wait 2>/dev/null || true
        fi
    fi
    
    exit $exit_code
}

# Set trap for error cleanup
trap cleanup_on_error ERR

# Function to check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if Azure CLI is installed
    if ! command -v az &> /dev/null; then
        log_error "Azure CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Check if user is logged in to Azure
    if ! az account show &> /dev/null; then
        log_error "Not logged in to Azure. Please run 'az login' first."
        exit 1
    fi
    
    # Check if openssl is available for random generation
    if ! command -v openssl &> /dev/null; then
        log_error "openssl is not available. Please install it for random string generation."
        exit 1
    fi
    
    # Verify Logic Apps service is available in subscription
    local subscription_id
    subscription_id=$(az account show --query id --output tsv)
    if ! az provider show --namespace Microsoft.Logic --query "registrationState" --output tsv | grep -q "Registered"; then
        log_warning "Microsoft.Logic provider not registered. Registering now..."
        az provider register --namespace Microsoft.Logic
        log_info "Waiting for Microsoft.Logic provider registration..."
        while [[ $(az provider show --namespace Microsoft.Logic --query "registrationState" --output tsv) != "Registered" ]]; do
            sleep 10
            log_info "Still waiting for provider registration..."
        done
    fi
    
    log_success "Prerequisites check completed successfully"
}

# Function to set environment variables
setup_environment() {
    log_info "Setting up environment variables..."
    
    # Generate unique suffix for resource names
    RANDOM_SUFFIX=$(openssl rand -hex 3)
    
    # Set environment variables
    export RESOURCE_GROUP="rg-reminder-logic-app-${RANDOM_SUFFIX}"
    export LOCATION="${AZURE_LOCATION:-eastus}"
    export SUBSCRIPTION_ID=$(az account show --query id --output tsv)
    export LOGIC_APP_NAME="la-schedule-reminders-${RANDOM_SUFFIX}"
    
    # Save deployment state
    cat > "$DEPLOYMENT_STATE_FILE" << EOF
RESOURCE_GROUP="$RESOURCE_GROUP"
LOCATION="$LOCATION"
SUBSCRIPTION_ID="$SUBSCRIPTION_ID"
LOGIC_APP_NAME="$LOGIC_APP_NAME"
RANDOM_SUFFIX="$RANDOM_SUFFIX"
EOF
    
    log_info "Environment variables configured:"
    log_info "  Resource Group: $RESOURCE_GROUP"
    log_info "  Location: $LOCATION"
    log_info "  Logic App Name: $LOGIC_APP_NAME"
    log_info "  Subscription ID: $SUBSCRIPTION_ID"
}

# Function to create resource group
create_resource_group() {
    log_info "Creating resource group: $RESOURCE_GROUP"
    
    az group create \
        --name "$RESOURCE_GROUP" \
        --location "$LOCATION" \
        --tags purpose=recipe environment=demo deployment=automated \
        >> "$LOG_FILE" 2>&1
    
    log_success "Resource group created successfully"
}

# Function to create workflow definition
create_workflow_definition() {
    log_info "Creating workflow definition file..."
    
    # Get user's email address for the reminder recipient
    local user_email
    user_email=$(az ad signed-in-user show --query mail --output tsv 2>/dev/null || \
                az ad signed-in-user show --query userPrincipalName --output tsv)
    
    if [[ -z "$user_email" ]]; then
        log_warning "Could not automatically detect user email. Using placeholder."
        user_email="user@company.com"
    fi
    
    log_info "Using email address: $user_email"
    
    cat > "${SCRIPT_DIR}/workflow-definition.json" << EOF
{
  "\$schema": "https://schema.management.azure.com/providers/Microsoft.Logic/schemas/2016-06-01/workflowdefinition.json#",
  "contentVersion": "1.0.0.0",
  "parameters": {},
  "triggers": {
    "Recurrence": {
      "recurrence": {
        "frequency": "Week",
        "interval": 1,
        "schedule": {
          "hours": ["9"],
          "minutes": [0],
          "weekDays": ["Monday"]
        }
      },
      "type": "Recurrence"
    }
  },
  "actions": {
    "Send_an_email_(V2)": {
      "runAfter": {},
      "type": "ApiConnection",
      "inputs": {
        "body": {
          "Body": "<p>Hello Team,</p><p>This is your weekly reminder that we have our team meeting today at 2:00 PM.</p><p>Please prepare your weekly updates and join the meeting room.</p><p>Best regards,<br>Automated Reminder System</p>",
          "Subject": "Weekly Reminder - Team Meeting Today",
          "To": "$user_email"
        },
        "host": {
          "connection": {
            "name": "@parameters('\$connections')['office365']['connectionId']"
          }
        },
        "method": "post",
        "path": "/v2/Mail"
      }
    }
  },
  "outputs": {},
  "parameters": {
    "\$connections": {
      "defaultValue": {},
      "type": "Object"
    }
  }
}
EOF
    
    log_success "Workflow definition created with recipient: $user_email"
}

# Function to create Logic App
create_logic_app() {
    log_info "Creating Logic App: $LOGIC_APP_NAME"
    
    az logic workflow create \
        --resource-group "$RESOURCE_GROUP" \
        --name "$LOGIC_APP_NAME" \
        --location "$LOCATION" \
        --definition "${SCRIPT_DIR}/workflow-definition.json" \
        --state Enabled \
        >> "$LOG_FILE" 2>&1
    
    local logic_app_resource_id
    logic_app_resource_id=$(az logic workflow show \
        --resource-group "$RESOURCE_GROUP" \
        --name "$LOGIC_APP_NAME" \
        --query id --output tsv)
    
    echo "LOGIC_APP_RESOURCE_ID=\"$logic_app_resource_id\"" >> "$DEPLOYMENT_STATE_FILE"
    
    log_success "Logic App created successfully"
}

# Function to provide Office 365 connection setup instructions
setup_office365_connection() {
    log_info "Setting up Office 365 connection instructions..."
    
    local logic_app_resource_id
    logic_app_resource_id=$(az logic workflow show \
        --resource-group "$RESOURCE_GROUP" \
        --name "$LOGIC_APP_NAME" \
        --query id --output tsv)
    
    log_warning "MANUAL STEP REQUIRED: Office 365 Connection Setup"
    echo ""
    echo "To complete the Office 365 connection setup:"
    echo "1. Navigate to: https://portal.azure.com/#@/resource${logic_app_resource_id}"
    echo "2. Click 'API connections' in the left menu"
    echo "3. Click '+ Add' to create new connection"
    echo "4. Search for 'Office 365 Outlook' and select it"
    echo "5. Click 'Create' and sign in with your Office 365 account"
    echo "6. Name the connection 'office365' to match the workflow"
    echo ""
    
    # Wait for user confirmation
    read -p "Press Enter after completing the Office 365 connection setup..." -r
    
    # Check if connection was created
    local connection_count
    connection_count=$(az resource list \
        --resource-group "$RESOURCE_GROUP" \
        --resource-type Microsoft.Web/connections \
        --query "length([?contains(name, 'office365')])" \
        --output tsv)
    
    if [[ "$connection_count" -eq 0 ]]; then
        log_warning "Office 365 connection not detected. You can complete this step manually later."
        log_info "The Logic App has been created but will need the connection to send emails."
        return
    fi
    
    log_success "Office 365 connection detected"
    update_workflow_with_connection
}

# Function to update workflow with connection parameters
update_workflow_with_connection() {
    log_info "Updating workflow with connection parameters..."
    
    local connection_id
    connection_id=$(az resource list \
        --resource-group "$RESOURCE_GROUP" \
        --resource-type Microsoft.Web/connections \
        --query "[?contains(name, 'office365')].id" \
        --output tsv)
    
    if [[ -z "$connection_id" ]]; then
        log_warning "Connection ID not found. Skipping workflow update."
        return
    fi
    
    # Get user's email address
    local user_email
    user_email=$(az ad signed-in-user show --query mail --output tsv 2>/dev/null || \
                az ad signed-in-user show --query userPrincipalName --output tsv)
    
    if [[ -z "$user_email" ]]; then
        user_email="user@company.com"
    fi
    
    cat > "${SCRIPT_DIR}/updated-workflow.json" << EOF
{
  "\$schema": "https://schema.management.azure.com/providers/Microsoft.Logic/schemas/2016-06-01/workflowdefinition.json#",
  "contentVersion": "1.0.0.0",
  "parameters": {
    "\$connections": {
      "defaultValue": {
        "office365": {
          "connectionId": "$connection_id",
          "connectionName": "office365",
          "id": "/subscriptions/$SUBSCRIPTION_ID/providers/Microsoft.Web/locations/$LOCATION/managedApis/office365"
        }
      },
      "type": "Object"
    }
  },
  "triggers": {
    "Recurrence": {
      "recurrence": {
        "frequency": "Week",
        "interval": 1,
        "schedule": {
          "hours": ["9"],
          "minutes": [0],
          "weekDays": ["Monday"]
        }
      },
      "type": "Recurrence"
    }
  },
  "actions": {
    "Send_an_email_(V2)": {
      "runAfter": {},
      "type": "ApiConnection",
      "inputs": {
        "body": {
          "Body": "<p>Hello Team,</p><p>This is your weekly reminder that we have our team meeting today at 2:00 PM.</p><p>Please prepare your weekly updates and join the meeting room.</p><p>Best regards,<br>Automated Reminder System</p>",
          "Subject": "Weekly Reminder - Team Meeting Today",
          "To": "$user_email"
        },
        "host": {
          "connection": {
            "name": "@parameters('\$connections')['office365']['connectionId']"
          }
        },
        "method": "post",
        "path": "/v2/Mail"
      }
    }
  },
  "outputs": {}
}
EOF
    
    # Update the Logic App with connection information
    az logic workflow create \
        --resource-group "$RESOURCE_GROUP" \
        --name "$LOGIC_APP_NAME" \
        --location "$LOCATION" \
        --definition "${SCRIPT_DIR}/updated-workflow.json" \
        --state Enabled \
        >> "$LOG_FILE" 2>&1
    
    log_success "Logic App updated with Office 365 connection"
}

# Function to test the deployment
test_deployment() {
    log_info "Testing Logic App deployment..."
    
    # Check Logic App status
    local logic_app_state
    logic_app_state=$(az logic workflow show \
        --resource-group "$RESOURCE_GROUP" \
        --name "$LOGIC_APP_NAME" \
        --query "properties.state" \
        --output tsv)
    
    if [[ "$logic_app_state" != "Enabled" ]]; then
        log_error "Logic App is not in enabled state: $logic_app_state"
        return 1
    fi
    
    log_success "Logic App is in enabled state"
    
    # Optional: Trigger a test run
    read -p "Would you like to trigger a test email now? (y/N): " -r
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        log_info "Triggering test run..."
        
        az logic workflow trigger run \
            --resource-group "$RESOURCE_GROUP" \
            --workflow-name "$LOGIC_APP_NAME" \
            --trigger-name Recurrence \
            >> "$LOG_FILE" 2>&1
        
        log_success "Test run triggered. Check your email and the Azure portal for results."
    fi
}

# Function to display deployment summary
display_summary() {
    log_success "Deployment completed successfully!"
    echo ""
    echo "=== DEPLOYMENT SUMMARY ==="
    echo "Resource Group: $RESOURCE_GROUP"
    echo "Logic App Name: $LOGIC_APP_NAME"
    echo "Location: $LOCATION"
    echo "Subscription ID: $SUBSCRIPTION_ID"
    echo ""
    echo "Next Steps:"
    echo "1. Check your email for test reminder (if triggered)"
    echo "2. Monitor the Logic App in Azure portal:"
    
    local logic_app_resource_id
    logic_app_resource_id=$(az logic workflow show \
        --resource-group "$RESOURCE_GROUP" \
        --name "$LOGIC_APP_NAME" \
        --query id --output tsv)
    
    echo "   https://portal.azure.com/#@/resource${logic_app_resource_id}"
    echo "3. The Logic App will send weekly reminders every Monday at 9:00 AM"
    echo ""
    echo "To clean up resources, run: ./destroy.sh"
    echo ""
}

# Main deployment function
main() {
    log_info "Starting deployment of Simple Schedule Reminders with Logic Apps"
    log_info "Log file: $LOG_FILE"
    
    # Clear previous log
    > "$LOG_FILE"
    
    check_prerequisites
    setup_environment
    create_resource_group
    create_workflow_definition
    create_logic_app
    setup_office365_connection
    test_deployment
    display_summary
    
    log_success "Deployment script completed successfully"
}

# Run main function
main "$@"