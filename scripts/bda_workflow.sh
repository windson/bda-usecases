#!/bin/bash

# BDA Resume Processing Script
# Unified script for all BDA resume processing operations

set -e  # Exit on any error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Configuration
REGION="ap-south-1"
MAX_WAIT_TIME=300  # 5 minutes

# Get account ID dynamically
get_account_id() {
    aws sts get-caller-identity --query Account --output text 2>/dev/null || {
        print_error "Failed to get AWS account ID. Please check your AWS credentials."
        exit 1
    }
}

# Set bucket name dynamically
ACCOUNT_ID=$(get_account_id)
BUCKET_NAME="bda-resume-processing-${ACCOUNT_ID}"

# Function to print colored output
print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_header() {
    echo -e "${CYAN}========================================${NC}"
    echo -e "${CYAN}$1${NC}"
    echo -e "${CYAN}========================================${NC}"
}

# Function to show main menu
show_main_menu() {
    local resume_file="$1"
    
    while true; do
        echo
        print_header "BDA Resume Processing Menu"
        echo "Resume file: $resume_file"
        echo
        echo "1. Test in DEVELOPMENT stage"
        echo "2. Promote blueprint to LIVE"
        echo "3. Process resume (Production)"
        echo "4. Test in LIVE stage"
        echo "5. Full workflow (DEV → Promote → LIVE)"
        echo "6. Exit"
        echo
        echo -e "${YELLOW}Enter your choice (1-6):${NC}"
        read -r choice
        
        case $choice in
            1)
                test_development "$resume_file"
                ;;
            2)
                promote_blueprint
                ;;
            3)
                process_resume "$resume_file"
                ;;
            4)
                test_live "$resume_file"
                ;;
            5)
                full_workflow "$resume_file"
                ;;
            6)
                print_status "Goodbye!"
                exit 0
                ;;
            *)
                print_error "Invalid choice. Please enter 1-6."
                ;;
        esac
    done
}

# Function to upload and process resume
upload_and_process() {
    local resume_file="$1"
    local stage="$2"
    
    if [ ! -f "$resume_file" ]; then
        print_error "Resume file not found: $resume_file"
        return 1
    fi
    
    # Generate unique filename with timestamp
    TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
    FILENAME=$(basename "$resume_file")
    FILENAME_NO_EXT="${FILENAME%.*}"
    S3_KEY="input/${TIMESTAMP}_${FILENAME}"
    
    print_status "📤 Uploading resume to S3 ($stage)..."
    print_status "File: $resume_file"
    
    # Upload to S3
    aws s3 cp "$resume_file" "s3://$BUCKET_NAME/$S3_KEY" --region "$REGION"
    if [ $? -eq 0 ]; then
        print_success "Upload completed: s3://$BUCKET_NAME/$S3_KEY"
    else
        print_error "Upload failed"
        return 1
    fi
    
    # Get Lambda function name
    LAMBDA_FUNCTION_NAME=$(aws cloudformation describe-stacks --stack-name BDAResumeStack --region "$REGION" --query "Stacks[0].Outputs[?OutputKey=='LambdaFunctionName'].OutputValue" --output text 2>/dev/null || echo "")
    
    if [ -z "$LAMBDA_FUNCTION_NAME" ]; then
        print_warning "Could not get Lambda function name from stack"
    fi
    
    # Start tailing logs
    print_status "📋 Monitoring Lambda logs..."
    if [ ! -z "$LAMBDA_FUNCTION_NAME" ]; then
        aws logs tail "/aws/lambda/$LAMBDA_FUNCTION_NAME" --follow --region "$REGION" --since 1m &
        LOG_PID=$!
        sleep 2
    fi
    
    # Wait for processing
    print_status "⏳ Waiting for BDA processing to complete..."
    OUTPUT_PREFIX="output/${TIMESTAMP}_${FILENAME_NO_EXT}/"
    RESULT_FOUND=false
    START_TIME=$(date +%s)
    ERROR_DETECTED=false
    
    while [ $RESULT_FOUND = false ] && [ $ERROR_DETECTED = false ]; do
        CURRENT_TIME=$(date +%s)
        ELAPSED=$((CURRENT_TIME - START_TIME))
        
        if [ $ELAPSED -gt $MAX_WAIT_TIME ]; then
            if [ ! -z "$LOG_PID" ]; then
                pkill -f "aws logs tail" 2>/dev/null || true
            fi
            print_error "Timeout: Processing took longer than $MAX_WAIT_TIME seconds"
            return 1
        fi
        
        # Check for Lambda errors in recent logs
        if [ ! -z "$LAMBDA_FUNCTION_NAME" ]; then
            ERROR_COUNT=$(aws logs filter-log-events --log-group-name "/aws/lambda/$LAMBDA_FUNCTION_NAME" --region "$REGION" --start-time $(($(date +%s) - 60))000 --filter-pattern "ERROR" --query 'length(events)' --output text 2>/dev/null || echo "0")
            
            # Convert to integer to handle cases like "00"
            ERROR_COUNT=$((ERROR_COUNT + 0))
            
            if [ "$ERROR_COUNT" -gt 0 ]; then
                ERROR_DETECTED=true
                if [ ! -z "$LOG_PID" ]; then
                    pkill -f "aws logs tail" 2>/dev/null || true
                fi
                print_error "Lambda function errors detected. Check logs above."
                return 1
            fi
        fi
        
        # Check if results are available
        RESULT_COUNT=$(aws s3 ls "s3://$BUCKET_NAME/$OUTPUT_PREFIX" --recursive --region "$REGION" 2>/dev/null | grep "result.json" | wc -l || echo "0")
        
        if [ "$RESULT_COUNT" -gt 0 ]; then
            RESULT_FOUND=true
            # Kill log tailing immediately
            if [ ! -z "$LOG_PID" ]; then
                pkill -f "aws logs tail" 2>/dev/null || true
            fi
            print_success "Processing completed successfully in ${ELAPSED} seconds!"
        else
            printf "\r${BLUE}[INFO]${NC} Waiting... (${ELAPSED}s elapsed)"
            sleep 5
        fi
    done
    
    echo  # New line after progress
    
    # Download and show results
    if [ $RESULT_FOUND = true ]; then
        print_status "📥 Downloading results..."
        
        RESULT_PATH=$(aws s3 ls "s3://$BUCKET_NAME/$OUTPUT_PREFIX" --recursive --region "$REGION" | grep "result.json" | awk '{print $4}' | head -1)
        
        if [ ! -z "$RESULT_PATH" ]; then
            OUTPUT_FILE="./results/${TIMESTAMP}_${FILENAME_NO_EXT}_result.json"
            mkdir -p ./results
            aws s3 cp "s3://$BUCKET_NAME/$RESULT_PATH" "$OUTPUT_FILE" --region "$REGION"
            
            if [ $? -eq 0 ]; then
                print_success "Results saved: $OUTPUT_FILE"
                
                # Show preview
                print_status "📋 Quick Preview:"
                python3 -c "
import json
try:
    with open('$OUTPUT_FILE', 'r') as f:
        data = json.load(f)
    result = data.get('inference_result', {})
    personal = result.get('personal_info', {})
    if personal:
        print(f'   Name: {personal.get(\"full_name\", \"N/A\")}')
        print(f'   Email: {personal.get(\"email\", \"N/A\")}')
except: pass
"
            fi
        fi
    fi
    
    return 0
}

# Function for production processing
process_resume() {
    local resume_file="$1"
    
    print_header "Production Processing"
    
    # Check if blueprint is in LIVE stage for production
    print_status "🔍 Checking blueprint stage..."
    BLUEPRINT_ARN=$(aws cloudformation describe-stacks --stack-name BDAResumeStack --region "$REGION" --query "Stacks[0].Outputs[?OutputKey=='BlueprintArn'].OutputValue" --output text 2>/dev/null || echo "")
    
    if [ ! -z "$BLUEPRINT_ARN" ]; then
        STAGE=$(aws bedrock-data-automation get-blueprint --blueprint-arn "$BLUEPRINT_ARN" --region "$REGION" --query 'blueprint.blueprintStage' --output text 2>/dev/null || echo "")
        
        if [ "$STAGE" != "LIVE" ]; then
            print_warning "Blueprint is in $STAGE stage, not LIVE"
            print_warning "For production processing, blueprint should be in LIVE stage"
            echo
            echo "Would you like to:"
            echo "1. Continue anyway (use $STAGE stage)"
            echo "2. Promote blueprint to LIVE first"
            echo "3. Return to menu"
            echo
            echo -e "${YELLOW}Enter your choice (1-3):${NC}"
            read -r choice
            
            case $choice in
                1)
                    print_status "Continuing with $STAGE stage..."
                    ;;
                2)
                    promote_blueprint
                    return
                    ;;
                3)
                    return
                    ;;
                *)
                    print_error "Invalid choice. Returning to menu."
                    return
                    ;;
            esac
        else
            print_success "Blueprint is in LIVE stage ✓"
        fi
    fi
    
    if upload_and_process "$resume_file" "PRODUCTION"; then
        print_success "🎉 Processing completed successfully!"
        print_status "💡 Results saved to ./results/"
    else
        print_error "Processing failed"
    fi
    
    echo
    print_status "Press Enter to return to menu..."
    read
}

# Function for development testing
test_development() {
    local resume_file="$1"
    
    print_header "Development Stage Testing"
    
    if upload_and_process "$resume_file" "DEVELOPMENT"; then
        print_success "🎉 DEVELOPMENT testing completed successfully!"
    else
        print_error "DEVELOPMENT testing failed"
    fi
    
    echo
    print_status "Press Enter to return to menu..."
    read
}

# Function for LIVE testing
test_live() {
    local resume_file="$1"
    
    print_header "LIVE Stage Testing"
    
    if upload_and_process "$resume_file" "LIVE"; then
        print_success "🎉 LIVE testing completed successfully!"
    else
        print_error "LIVE testing failed"
    fi
    
    echo
    print_status "Press Enter to return to menu..."
    read
}

# Function to promote blueprint
promote_blueprint() {
    print_header "Blueprint Promotion"
    print_status "🚀 Promoting blueprint to LIVE stage..."
    
    # Get blueprint ARN from CDK outputs
    BLUEPRINT_ARN=$(aws cloudformation describe-stacks --stack-name BDAResumeStack --region "$REGION" --query "Stacks[0].Outputs[?OutputKey=='BlueprintArn'].OutputValue" --output text 2>/dev/null || echo "")
    
    if [ -z "$BLUEPRINT_ARN" ]; then
        print_error "Could not get BlueprintArn from CDK stack"
        echo
        print_status "Press Enter to return to menu..."
        read
        return 1
    fi
    
    # Check if already promoted
    STAGE=$(aws bedrock-data-automation get-blueprint --blueprint-arn "$BLUEPRINT_ARN" --region "$REGION" --query 'blueprint.blueprintStage' --output text 2>/dev/null || echo "")
    
    if [ "$STAGE" = "LIVE" ]; then
        print_warning "Blueprint is already in LIVE stage"
        print_status "Blueprint ARN: $BLUEPRINT_ARN"
        echo
        print_status "Press Enter to return to menu..."
        read
        return 0
    fi
    
    # Run promotion script
    if [ -f "cli/promote_blueprint.py" ]; then
        print_status "Running promotion script..."
        if uv run cli/promote_blueprint.py; then
            print_success "Blueprint promoted to LIVE stage!"
        else
            print_error "Blueprint promotion failed"
        fi
    else
        print_error "Promotion script not found: cli/promote_blueprint.py"
    fi
    
    echo
    print_status "Press Enter to return to menu..."
    read
}

# Function for full workflow
full_workflow() {
    local resume_file="$1"
    
    print_header "Full Workflow: DEV → Promote → LIVE"
    
    # Step 1: Development testing
    print_status "Step 1: Testing in DEVELOPMENT stage..."
    if ! upload_and_process "$resume_file" "DEVELOPMENT"; then
        print_error "DEVELOPMENT stage testing failed"
        echo
        print_status "Press Enter to return to menu..."
        read
        return 1
    fi
    
    print_success "✅ DEVELOPMENT stage completed!"
    echo
    
    # Step 2: Promote blueprint (inline, no menu return)
    print_status "Step 2: Promoting blueprint to LIVE..."
    BLUEPRINT_ARN=$(aws cloudformation describe-stacks --stack-name BDAResumeStack --region "$REGION" --query "Stacks[0].Outputs[?OutputKey=='BlueprintArn'].OutputValue" --output text 2>/dev/null || echo "")
    
    if [ -z "$BLUEPRINT_ARN" ]; then
        print_error "Could not get BlueprintArn from CDK stack"
        echo
        print_status "Press Enter to return to menu..."
        read
        return 1
    fi
    
    # Check if already promoted
    STAGE=$(aws bedrock-data-automation get-blueprint --blueprint-arn "$BLUEPRINT_ARN" --region "$REGION" --query 'blueprint.blueprintStage' --output text 2>/dev/null || echo "")
    
    if [ "$STAGE" = "LIVE" ]; then
        print_warning "Blueprint is already in LIVE stage"
        print_success "✅ Blueprint promotion step completed!"
    else
        # Run promotion script
        if [ -f "cli/promote_blueprint.py" ]; then
            print_status "Running promotion script..."
            if uv run cli/promote_blueprint.py; then
                print_success "✅ Blueprint promoted to LIVE stage!"
            else
                print_error "Blueprint promotion failed"
                echo
                print_status "Press Enter to return to menu..."
                read
                return 1
            fi
        else
            print_error "Promotion script not found: cli/promote_blueprint.py"
            echo
            print_status "Press Enter to return to menu..."
            read
            return 1
        fi
    fi
    
    echo
    
    # Step 3: LIVE testing
    print_status "Step 3: Testing in LIVE stage..."
    if ! upload_and_process "$resume_file" "LIVE"; then
        print_error "LIVE stage testing failed"
        echo
        print_status "Press Enter to return to menu..."
        read
        return 1
    fi
    
    print_success "✅ Full workflow completed successfully!"
    print_status "🎉 Your system is ready for production!"
    
    echo
    print_status "Press Enter to return to menu..."
    read
}

# Main function
main() {
    # Check arguments
    if [ $# -lt 1 ]; then
        print_error "Usage: $0 <resume_file>"
        print_error "Example: $0 data/sample_resume.pdf"
        exit 1
    fi
    
    RESUME_FILE="$1"
    
    if [ ! -f "$RESUME_FILE" ]; then
        print_error "Resume file not found: $RESUME_FILE"
        exit 1
    fi
    
    # Show main menu
    show_main_menu "$RESUME_FILE"
}

# Run main function
main "$@"