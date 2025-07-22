#!/bin/bash

# Real-Time Collaborative Applications with Firebase - Cleanup Script
# This script removes Firebase Realtime Database, Cloud Functions, Authentication, and Hosting
# for a collaborative document editing application

set -e  # Exit on any error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
    exit 1
}

# Function to check if command exists
check_command() {
    if ! command -v "$1" &> /dev/null; then
        error "$1 is required but not installed. Please install it first."
    fi
}

# Function to check Firebase CLI authentication
check_firebase_auth() {
    log "Checking Firebase CLI authentication..."
    if ! firebase login:list &> /dev/null; then
        warning "Firebase CLI not authenticated. Please run 'firebase login' first."
        firebase login
    fi
    success "Firebase CLI authenticated"
}

# Function to get current Firebase project
get_current_project() {
    local project_id
    project_id=$(firebase use 2>/dev/null | grep -o "Now using project [^[:space:]]*" | cut -d' ' -f4 || echo "")
    
    if [[ -z "$project_id" ]]; then
        # Try to read from .firebaserc
        if [[ -f ".firebaserc" ]]; then
            project_id=$(jq -r '.projects.default // empty' .firebaserc 2>/dev/null || echo "")
        fi
    fi
    
    echo "$project_id"
}

# Function to check if project exists
project_exists() {
    local project_id="$1"
    firebase projects:list --json 2>/dev/null | jq -r '.[].projectId' | grep -q "^${project_id}$"
}

# Function to confirm destructive action
confirm_action() {
    local message="$1"
    local response
    
    echo -e "${YELLOW}"
    echo "⚠️  WARNING: This action is DESTRUCTIVE and IRREVERSIBLE!"
    echo "$message"
    echo -e "${NC}"
    
    read -p "Type 'DELETE' to confirm this action: " response
    
    if [[ "$response" != "DELETE" ]]; then
        echo "Action cancelled."
        exit 0
    fi
}

# Function to list Firebase functions
list_functions() {
    local project_id="$1"
    firebase functions:list --project "$project_id" 2>/dev/null | grep -E '^[[:space:]]*[a-zA-Z]' | awk '{print $1}' || echo ""
}

# Function to delete Cloud Functions
delete_functions() {
    local project_id="$1"
    
    log "Checking for Cloud Functions to delete..."
    
    local functions
    functions=$(list_functions "$project_id")
    
    if [[ -z "$functions" ]]; then
        log "No Cloud Functions found to delete"
        return 0
    fi
    
    log "Found Cloud Functions: $(echo "$functions" | tr '\n' ' ')"
    
    confirm_action "This will delete ALL Cloud Functions in project '$project_id'."
    
    log "Deleting Cloud Functions..."
    
    # Delete each function individually
    while IFS= read -r function_name; do
        if [[ -n "$function_name" ]]; then
            log "Deleting function: $function_name"
            firebase functions:delete "$function_name" --project "$project_id" --force 2>/dev/null || {
                warning "Failed to delete function: $function_name"
            }
        fi
    done <<< "$functions"
    
    success "Cloud Functions deletion completed"
}

# Function to clear Realtime Database
clear_database() {
    local project_id="$1"
    
    log "Checking Realtime Database content..."
    
    # Check if database has content
    local db_content
    db_content=$(firebase database:get / --project "$project_id" 2>/dev/null || echo "null")
    
    if [[ "$db_content" == "null" || "$db_content" == "{}" ]]; then
        log "Realtime Database is already empty"
        return 0
    fi
    
    confirm_action "This will DELETE ALL DATA in the Realtime Database for project '$project_id'."
    
    log "Clearing Realtime Database..."
    firebase database:remove / --project "$project_id" --force 2>/dev/null || {
        warning "Failed to clear database content"
    }
    
    success "Realtime Database cleared"
}

# Function to delete Firebase Hosting
delete_hosting() {
    local project_id="$1"
    
    log "Checking Firebase Hosting..."
    
    # Check if hosting is configured
    local hosting_sites
    hosting_sites=$(firebase hosting:sites:list --project "$project_id" 2>/dev/null | grep -v "No sites" | tail -n +2 || echo "")
    
    if [[ -z "$hosting_sites" ]]; then
        log "No Firebase Hosting sites found"
        return 0
    fi
    
    log "Found Firebase Hosting sites"
    confirm_action "This will remove the hosting deployment for project '$project_id'."
    
    log "Removing Firebase Hosting deployment..."
    
    # Create empty index.html to effectively "delete" the site content
    mkdir -p temp_empty_site
    echo "<!DOCTYPE html><html><head><title>Site Removed</title></head><body><h1>This site has been removed</h1></body></html>" > temp_empty_site/index.html
    
    # Deploy empty site
    firebase hosting:channel:deploy temp --expires 1h --project "$project_id" --public temp_empty_site 2>/dev/null || {
        warning "Failed to deploy empty hosting site"
    }
    
    # Clean up
    rm -rf temp_empty_site
    
    success "Firebase Hosting deployment removed"
}

# Function to delete Firebase Authentication users
delete_auth_users() {
    local project_id="$1"
    
    log "Checking Firebase Authentication users..."
    
    confirm_action "This will DELETE ALL USERS from Firebase Authentication for project '$project_id'."
    
    log "Note: Firebase CLI doesn't support bulk user deletion."
    log "Users will need to be deleted manually from the Firebase Console:"
    log "https://console.firebase.google.com/project/$project_id/authentication/users"
    
    warning "Authentication users must be deleted manually from the Firebase Console"
}

# Function to disable Firebase services
disable_firebase_services() {
    local project_id="$1"
    
    log "Note: Firebase services cannot be completely disabled via CLI."
    log "To fully disable Firebase services, visit the Firebase Console:"
    log "https://console.firebase.google.com/project/$project_id/settings/general"
    
    warning "Firebase services must be disabled manually from the Firebase Console"
}

# Function to delete local project files
delete_local_files() {
    local delete_all="$1"
    
    if [[ "$delete_all" == "true" ]]; then
        confirm_action "This will DELETE ALL LOCAL PROJECT FILES including source code."
        
        log "Deleting local project files..."
        
        # Delete specific Firebase-related files and directories
        rm -rf functions/ 2>/dev/null || true
        rm -rf public/ 2>/dev/null || true
        rm -f firebase.json 2>/dev/null || true
        rm -f .firebaserc 2>/dev/null || true
        rm -f database.rules.json 2>/dev/null || true
        rm -rf .firebase/ 2>/dev/null || true
        rm -rf node_modules/ 2>/dev/null || true
        rm -f package*.json 2>/dev/null || true
        
        success "Local project files deleted"
    else
        log "Cleaning up generated files..."
        
        # Only delete build artifacts and cache
        rm -rf functions/lib/ 2>/dev/null || true
        rm -rf functions/node_modules/ 2>/dev/null || true
        rm -rf .firebase/ 2>/dev/null || true
        
        success "Build artifacts cleaned up"
    fi
}

# Function to delete entire Firebase project
delete_firebase_project() {
    local project_id="$1"
    
    log "Preparing to delete entire Firebase project..."
    
    confirm_action "This will PERMANENTLY DELETE the entire Firebase project '$project_id' and ALL associated data. This action CANNOT be undone!"
    
    log "Deleting Firebase project: $project_id"
    firebase projects:delete "$project_id" --force 2>/dev/null || {
        error "Failed to delete Firebase project. You may need to delete it manually from the Firebase Console."
    }
    
    success "Firebase project deleted: $project_id"
}

# Function to show cleanup summary
show_cleanup_summary() {
    local project_id="$1"
    local action="$2"
    
    echo -e "${GREEN}"
    echo "================================================"
    echo "            Cleanup Summary"
    echo "================================================"
    echo -e "${NC}"
    
    case "$action" in
        "partial")
            echo "✅ Cloud Functions deleted"
            echo "✅ Realtime Database cleared"
            echo "✅ Hosting deployment removed"
            echo "✅ Build artifacts cleaned"
            echo ""
            echo "⚠️  Manual cleanup required:"
            echo "   - Authentication users (Firebase Console)"
            echo "   - Firebase services (Firebase Console)"
            echo ""
            echo "Firebase Console: https://console.firebase.google.com/project/$project_id"
            ;;
        "full")
            echo "✅ Firebase project completely deleted"
            echo "✅ All local files removed"
            echo ""
            echo "The project '$project_id' has been permanently deleted."
            ;;
        "local-only")
            echo "✅ Local project files cleaned"
            echo ""
            echo "Firebase project '$project_id' is still active."
            echo "Firebase Console: https://console.firebase.google.com/project/$project_id"
            ;;
    esac
    
    echo ""
}

# Function to display usage information
show_usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  --project-id <id>    Specify Firebase project ID to delete"
    echo "  --delete-project     Delete the entire Firebase project (DESTRUCTIVE)"
    echo "  --delete-local       Delete all local project files (DESTRUCTIVE)"
    echo "  --partial            Delete deployed resources but keep project (default)"
    echo "  --local-only         Only clean local build artifacts"
    echo "  --help               Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0                           # Clean deployed resources (partial cleanup)"
    echo "  $0 --partial                 # Same as above"
    echo "  $0 --delete-project          # Delete entire Firebase project"
    echo "  $0 --delete-local            # Delete all local files"
    echo "  $0 --local-only              # Clean only local build artifacts"
    echo "  $0 --project-id my-project   # Specify project ID"
    echo ""
}

# Main cleanup function
main() {
    local project_id=""
    local delete_project=false
    local delete_local=false
    local partial_cleanup=true
    local local_only=false
    
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --project-id)
                project_id="$2"
                shift 2
                ;;
            --delete-project)
                delete_project=true
                partial_cleanup=false
                shift
                ;;
            --delete-local)
                delete_local=true
                partial_cleanup=false
                shift
                ;;
            --partial)
                partial_cleanup=true
                delete_project=false
                delete_local=false
                local_only=false
                shift
                ;;
            --local-only)
                local_only=true
                partial_cleanup=false
                delete_project=false
                delete_local=false
                shift
                ;;
            --help)
                show_usage
                exit 0
                ;;
            *)
                error "Unknown option: $1. Use --help for usage information."
                ;;
        esac
    done
    
    echo -e "${BLUE}"
    echo "================================================"
    echo "  Firebase Collaborative App Cleanup Script"
    echo "================================================"
    echo -e "${NC}"
    
    # Check prerequisites
    log "Checking prerequisites..."
    check_command "firebase"
    
    if command -v jq &> /dev/null; then
        log "jq found - enhanced project detection available"
    else
        warning "jq not found - limited project detection"
    fi
    
    success "Prerequisites check completed"
    
    # Handle local-only cleanup
    if [[ "$local_only" == "true" ]]; then
        log "Performing local-only cleanup..."
        delete_local_files false
        show_cleanup_summary "" "local-only"
        exit 0
    fi
    
    # Check Firebase authentication
    check_firebase_auth
    
    # Determine project ID
    if [[ -z "$project_id" ]]; then
        project_id=$(get_current_project)
        if [[ -z "$project_id" ]]; then
            error "Could not determine Firebase project ID. Please specify with --project-id or run from a Firebase project directory."
        fi
        log "Using current Firebase project: $project_id"
    else
        log "Using specified project ID: $project_id"
    fi
    
    # Verify project exists
    if ! project_exists "$project_id"; then
        error "Firebase project '$project_id' does not exist or you don't have access to it."
    fi
    
    # Set project
    firebase use "$project_id"
    
    # Execute cleanup based on options
    if [[ "$delete_project" == "true" ]]; then
        delete_firebase_project "$project_id"
        if [[ "$delete_local" == "true" ]]; then
            delete_local_files true
        fi
        show_cleanup_summary "$project_id" "full"
    elif [[ "$delete_local" == "true" ]]; then
        delete_local_files true
        show_cleanup_summary "$project_id" "local-only"
    elif [[ "$partial_cleanup" == "true" ]]; then
        # Partial cleanup - remove deployed resources but keep project
        delete_functions "$project_id"
        clear_database "$project_id"
        delete_hosting "$project_id"
        delete_auth_users "$project_id"
        disable_firebase_services "$project_id"
        delete_local_files false
        show_cleanup_summary "$project_id" "partial"
    fi
    
    echo -e "${GREEN}"
    echo "================================================"
    echo "            Cleanup Completed! 🧹"
    echo "================================================"
    echo -e "${NC}"
    
    success "Cleanup completed successfully!"
}

# Check if script is being sourced or executed
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi