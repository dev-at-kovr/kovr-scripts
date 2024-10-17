#!/bin/bash

# =============================================================================
# Script Name: setup_kovr.sh
# Description: Automates the setup and execution of the kovr-resource-collector
#              tool for AWS, including:
#              - Configuring AWS credentials
#              - Cloning the kovr-resource-collector repository via HTTPS
#              - Creating and activating a Python virtual environment
#              - Installing Python dependencies
#              - Running the service scanner
#              - Aggregating JSON output files
#              - Extracting and copying output files
#              - Cleaning up after completion
# =============================================================================

# Exit immediately if a command exits with a non-zero status
set -e

# Trap unexpected errors and perform cleanup if necessary
trap 'error_exit "An unexpected error occurred."' ERR

# Function to display error messages and exit
error_exit() {
    echo "Error: $1" >&2
    exit 1
}

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to prompt for AWS credentials or use environment variables
prompt_credentials() {
    echo "Checking for AWS credentials in environment variables."

    AWS_ACCESS_KEY_ID=${AWS_ACCESS_KEY_ID_ENV_VAR}
    AWS_SECRET_ACCESS_KEY=${AWS_SECRET_ACCESS_KEY_ENV_VAR}
    AWS_SESSION_TOKEN=${AWS_SESSION_TOKEN_ENV_VAR}

    if [ -z "$AWS_ACCESS_KEY_ID" ] || [ -z "$AWS_SECRET_ACCESS_KEY" ]; then
        echo "Environment variables for AWS credentials not found. Please enter them manually."
        read -p "AWS Access Key ID: " AWS_ACCESS_KEY_ID
        read -p "AWS Secret Access Key: " AWS_SECRET_ACCESS_KEY
        echo
        read -p "AWS Session Token (leave blank if not applicable): " AWS_SESSION_TOKEN
        echo
    else
        echo "AWS credentials loaded from environment variables."
    fi
}

# Function to configure AWS credentials
configure_aws_credentials() {
    AWS_DIR="$HOME/.aws"
    CREDENTIALS_FILE="$AWS_DIR/credentials"

    # Create .aws directory if it doesn't exist
    if [ ! -d "$AWS_DIR" ]; then
        mkdir -p "$AWS_DIR" || error_exit "Failed to create directory $AWS_DIR"
        echo "Created directory $AWS_DIR"
    fi

    # Backup existing credentials file
    if [ -f "$CREDENTIALS_FILE" ]; then
        BACKUP_FILE="${CREDENTIALS_FILE}.backup_$(date +%F_%T)"
        cp "$CREDENTIALS_FILE" "$BACKUP_FILE" || error_exit "Failed to backup existing credentials file."
        echo "Existing AWS credentials backed up to $BACKUP_FILE"
    fi

    # Write credentials to the file
    {
        echo "[default]"
        echo "aws_access_key_id=$AWS_ACCESS_KEY_ID"
        echo "aws_secret_access_key=$AWS_SECRET_ACCESS_KEY"
        if [ -n "$AWS_SESSION_TOKEN" ]; then
            echo "aws_session_token=$AWS_SESSION_TOKEN"
        fi
    } > "$CREDENTIALS_FILE" || error_exit "Failed to write AWS credentials to $CREDENTIALS_FILE"

    echo "AWS credentials have been configured successfully."
}

# Function to check and install Git if not present
ensure_git_installed() {
    if ! command_exists git; then
        echo "Git is not installed. Attempting to install Git..."
        if command_exists apt-get; then
            sudo apt-get update && sudo apt-get install -y git || error_exit "Failed to install Git using apt-get."
        elif command_exists yum; then
            sudo yum install -y git || error_exit "Failed to install Git using yum."
        elif command_exists brew; then
            brew install git || error_exit "Failed to install Git using Homebrew."
        else
            error_exit "Git is not installed and automatic installation is not supported on this OS."
        fi
        echo "Git has been installed successfully."
    else
        echo "Git is already installed."
    fi
}

# Function to clone the kovr-resource-collector repository via HTTPS
clone_repository() {
    REPO_URL="https://github.com/kovr-ai/kovr-resource-collector.git"
    CLONE_DIR="$HOME/kovr-resource-collector"

    if [ -d "$CLONE_DIR" ]; then
        echo "The directory $CLONE_DIR already exists."
        read -p "Do you want to remove it and re-clone the repository? (y/n): " choice
        case "$choice" in
            y|Y )
                rm -rf "$CLONE_DIR" || error_exit "Failed to remove existing directory $CLONE_DIR"
                echo "Removed existing directory $CLONE_DIR"
                ;;
            * )
                echo "Using existing repository at $CLONE_DIR"
                ;;
        esac
    fi

    # Clone the repository only if it doesn't exist
    if [ ! -d "$CLONE_DIR" ]; then
        echo "Cloning the repository from $REPO_URL to $CLONE_DIR..."
        git clone "$REPO_URL" "$CLONE_DIR" || error_exit "Failed to clone repository."
        echo "Repository cloned successfully."
    fi
}

# Function to create and activate Python virtual environment
setup_virtual_env() {
    VENV_DIR="venv"
    CLONE_DIR="$HOME/kovr-resource-collector"

    cd "$CLONE_DIR" || error_exit "Failed to navigate to $CLONE_DIR"

    # Create virtual environment
    echo "Creating Python virtual environment..."
    python3 -m venv "$VENV_DIR" || error_exit "Failed to create virtual environment."
    echo "Virtual environment created at $CLONE_DIR/$VENV_DIR"

    # Detect OS and activate virtual environment accordingly
    echo "Activating virtual environment..."
    if [[ "$OSTYPE" == "linux-gnu"* ]] || [[ "$OSTYPE" == "darwin"* ]]; then
        # Linux or macOS
        source "$VENV_DIR/bin/activate" || error_exit "Failed to activate virtual environment."
    elif [[ "$OSTYPE" == "cygwin" || "$OSTYPE" == "msys" || "$OSTYPE" == "win32" ]]; then
        # Windows (Git Bash)
        source "$VENV_DIR/Scripts/activate" || error_exit "Failed to activate virtual environment."
    else
        error_exit "Unsupported OS: $OSTYPE"
    fi

    echo "Virtual environment activated."
}

# Function to install Python dependencies
install_python_dependencies() {
    REQUIREMENTS_FILE="requirements.txt"
    CLONE_DIR="$HOME/kovr-resource-collector"

    if [ -f "$CLONE_DIR/$REQUIREMENTS_FILE" ]; then
        echo "Installing Python dependencies from $REQUIREMENTS_FILE..."
        pip install --upgrade pip
        pip install -r "$CLONE_DIR/$REQUIREMENTS_FILE" || error_exit "Failed to install Python dependencies."
        echo "Python dependencies installed successfully."
    else
        echo "No $REQUIREMENTS_FILE found. Skipping Python dependencies installation."
    fi
}

# Function to run the service scanner
run_service_scanner() {
    SCANNER_SCRIPT="kovr_aws_service_scanner.py"
    CLONE_DIR="$HOME/kovr-resource-collector"

    if [ ! -d "$CLONE_DIR" ]; then
        error_exit "The directory $CLONE_DIR does not exist. Please ensure the repository is cloned."
    fi

    cd "$CLONE_DIR" || error_exit "Failed to navigate to $CLONE_DIR"

    # Check if the Python script exists
    if [ ! -f "$SCANNER_SCRIPT" ]; then
        error_exit "The script $SCANNER_SCRIPT does not exist in $CLONE_DIR"
    fi

    echo "Running the AWS service scanner..."
    python "$SCANNER_SCRIPT" || error_exit "Failed to execute $SCANNER_SCRIPT"

    echo "Service scanner executed successfully."
}

# Function to extract and copy output files for upload
extract_and_copy_output_files() {
    CLONE_DIR="$HOME/kovr-resource-collector"
    SOURCE_FOLDER="$CLONE_DIR/kovr-scan"
    SOURCE_ZIP="$SOURCE_FOLDER/kovr-scan-compressed.zip"
    SOURCE_COMBINED_JSON="$SOURCE_FOLDER/aws_resources_combined.json"

    # Define the directory path
    DESTINATION_DIR="$(pwd)/output"

    # Check if the directory exists, if not, create it
    if [ ! -d "$DESTINATION_DIR" ]; then
        echo "Directory $DESTINATION_DIR does not exist. Creating it now..."
        mkdir -p "$DESTINATION_DIR" || { echo "Failed to create directory $DESTINATION_DIR"; exit 1; }
    else
        echo "Directory $DESTINATION_DIR already exists."
    fi
    
    echo "Extracting and copying the output files..."

    # Check if the source folder exists
    if [ ! -d "$SOURCE_FOLDER" ]; then
        error_exit "Source folder $SOURCE_FOLDER does not exist."
    fi

    # Check if the zip file exists
    if [ ! -f "$SOURCE_ZIP" ]; then
        error_exit "Compressed zip file $SOURCE_ZIP does not exist."
    fi

    # Check if the combined JSON file exists
    if [ ! -f "$SOURCE_COMBINED_JSON" ]; then
        error_exit "Combined JSON file $SOURCE_COMBINED_JSON does not exist."
    fi

    # Copy the kovr-scan folder
    echo "1. Copying 'kovr-scan' folder for individual config upload..."
    cp -r "$SOURCE_FOLDER" "$DESTINATION_DIR/kovr-scan" || error_exit "Failed to copy $SOURCE_FOLDER to $DESTINATION_DIR/kovr-scan"
    echo "'kovr-scan' folder has been copied to $DESTINATION_DIR/kovr-scan."

    # Copy the compressed zip file
    echo "2. Copying 'kovr-scan-compressed.zip' for individual zip upload..."
    cp "$SOURCE_ZIP" "$DESTINATION_DIR/kovr-scan-compressed.zip" || error_exit "Failed to copy $SOURCE_ZIP to $DESTINATION_DIR/kovr-scan-compressed.zip"
    echo "'kovr-scan-compressed.zip' has been copied to $DESTINATION_DIR/kovr-scan-compressed.zip."

    # Copy the combined JSON file
    echo "3. Copying 'aws_resources_combined.json' for all AWS resources upload..."
    cp "$SOURCE_COMBINED_JSON" "$DESTINATION_DIR/aws_resources_combined.json" || error_exit "Failed to copy $SOURCE_COMBINED_JSON to $DESTINATION_DIR/aws_resources_combined.json"
    echo "'aws_resources_combined.json' has been copied to $DESTINATION_DIR/aws_resources_combined.json."

    echo "Please upload the following files as needed:"
    echo "1. 'kovr-scan' folder for individual configuration."
    echo "2. 'kovr-scan-compressed.zip' for individual zip upload."
    echo "3. 'aws_resources_combined.json' for all AWS resources."
}


# Function to deactivate and delete the virtual environment and cloned repository
cleanup() {
    VENV_DIR="venv"
    CLONE_DIR="$HOME/kovr-resource-collector"

    echo "Deactivating virtual environment..."
    deactivate || echo "No virtual environment to deactivate."

    echo "Deleting the cloned repository at $CLONE_DIR..."
    rm -rf "$CLONE_DIR" || error_exit "Failed to delete the cloned repository."
    echo "Cloned repository deleted successfully."
}

# Function to display usage information
display_usage() {
    echo "Usage: $0 [--help]"
    echo ""
    echo "Automates the setup and execution of the kovr-resource-collector tool for AWS,"
    echo "including cloning the kovr-resource-collector repository via HTTPS, setting up"
    echo "a Python virtual environment, installing dependencies, running the service scanner,"
    echo "aggregating JSON output files, extracting and copying the combined JSON file,"
    echo "and cleaning up by deleting the repository after completion."
    echo ""
    echo "Options:"
    echo "  --help      Display this help message and exit."
}

# Main script execution
main() {
    echo "==============================="
    echo " kovr Resource Collector Setup"
    echo "==============================="

    # Parse command-line arguments
    if [ "$#" -gt 0 ]; then
        case "$1" in
            --help )
                display_usage
                exit 0
                ;;
            * )
                echo "Unknown option: $1"
                display_usage
                exit 1
                ;;
        esac
    fi

    prompt_credentials
    configure_aws_credentials
    ensure_git_installed
    clone_repository
    setup_virtual_env
    install_python_dependencies
    run_service_scanner
    extract_and_copy_output_files
    cleanup

    echo "Setup and execution completed successfully."
}

# Invoke the main function
main "$@"