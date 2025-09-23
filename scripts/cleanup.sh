#!/bin/bash

# cleanup.sh - Safe cleanup script for BDA Resume Processing infrastructure
# This script reads actual CDK-generated resources and only deletes those specific resources

set -e  # Exit on any error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
STACK_NAME="BDAResumeStack"
REGION="ap-south-1"
CDK_DIR="infrastructure"
FORCE_DELETE=${1:-false}  # Pass 'true' as first argument to force delete

echo -e "${BLUE}🧹 Starting Safe BDA Resume Processing Infrastructure Cleanup${NC}"
echo "=================================================="

# Function to print colored output
log_info() {
    echo -e "${BLUE}ℹ️  $1${NC}"
}

log_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

log_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

log_error() {
    echo -e "${RED}❌ $1${NC}"
}

# Function to check if AWS CLI is configured
check_aws_cli() {
    if ! command -v aws &> /dev/null; then
        log_error "AWS CLI not found. Please install AWS CLI first."
        exit 1
    fi
    
    if ! aws sts get-caller-identity &> /dev/null; then
        log_error "AWS CLI not configured or no valid credentials found."
        exit 1
    fi
    
    log_success "AWS CLI is configured"
}

# Function to get AWS account ID
get_account_id() {
    aws sts get-caller-identity --query Account --output text
}

# Function to read actual CDK-generated resources
read_cdk_resources() {
    log_info "Reading CDK-generated resources from CloudFormation..."
    
    # Initialize variables
    BUCKET_NAME=""
    LAMBDA_FUNCTION_NAME=""
    BLUEPRINT_ARN=""
    PROJECT_ARN=""
    DLQ_URL=""
    LAMBDA_ROLE_NAME=""
    
    # Check if stack exists first
    if ! aws cloudformation describe-stacks --stack-name "$STACK_NAME" --region "$REGION" &> /dev/null; then
        log_warning "Stack $STACK_NAME does not exist"
        return 1
    fi
    
    # Get stack outputs (safer than pattern matching)
    STACK_OUTPUTS=$(aws cloudformation describe-stacks --stack-name "$STACK_NAME" --region "$REGION" --query 'Stacks[0].Outputs' --output json 2>/dev/null || echo "[]")
    
    if [ "$STACK_OUTPUTS" != "[]" ]; then
        # Extract resource names from outputs
        BUCKET_NAME=$(echo "$STACK_OUTPUTS" | jq -r '.[] | select(.OutputKey=="BucketName") | .OutputValue' 2>/dev/null || echo "")
        LAMBDA_FUNCTION_NAME=$(echo "$STACK_OUTPUTS" | jq -r '.[] | select(.OutputKey=="LambdaFunctionName") | .OutputValue' 2>/dev/null || echo "")
        BLUEPRINT_ARN=$(echo "$STACK_OUTPUTS" | jq -r '.[] | select(.OutputKey=="BlueprintArn") | .OutputValue' 2>/dev/null || echo "")
        PROJECT_ARN=$(echo "$STACK_OUTPUTS" | jq -r '.[] | select(.OutputKey=="ProjectArn") | .OutputValue' 2>/dev/null || echo "")
        
        log_success "CDK outputs read successfully"
    fi
    
    # Get additional resources from stack resources (more comprehensive)
    STACK_RESOURCES=$(aws cloudformation describe-stack-resources --stack-name "$STACK_NAME" --region "$REGION" --query 'StackResources' --output json 2>/dev/null || echo "[]")
    
    if [ "$STACK_RESOURCES" != "[]" ]; then
        # Extract additional resource identifiers
        if [ -z "$BUCKET_NAME" ]; then
            BUCKET_NAME=$(echo "$STACK_RESOURCES" | jq -r '.[] | select(.ResourceType=="AWS::S3::Bucket") | .PhysicalResourceId' 2>/dev/null || echo "")
        fi
        
        if [ -z "$LAMBDA_FUNCTION_NAME" ]; then
            LAMBDA_FUNCTION_NAME=$(echo "$STACK_RESOURCES" | jq -r '.[] | select(.ResourceType=="AWS::Lambda::Function") | .PhysicalResourceId' 2>/dev/null || echo "")
        fi
        
        # Get DLQ URL
        DLQ_URL=$(echo "$STACK_RESOURCES" | jq -r '.[] | select(.ResourceType=="AWS::SQS::Queue") | .PhysicalResourceId' 2>/dev/null || echo "")
        
        # Get IAM Role name
        LAMBDA_ROLE_NAME=$(echo "$STACK_RESOURCES" | jq -r '.[] | select(.ResourceType=="AWS::IAM::Role") | .PhysicalResourceId' 2>/dev/null || echo "")
        
        # Get BDA resources if not from outputs
        if [ -z "$BLUEPRINT_ARN" ]; then
            BLUEPRINT_ARN=$(echo "$STACK_RESOURCES" | jq -r '.[] | select(.ResourceType=="AWS::Bedrock::Blueprint") | .PhysicalResourceId' 2>/dev/null || echo "")
        fi
        
        if [ -z "$PROJECT_ARN" ]; then
            PROJECT_ARN=$(echo "$STACK_RESOURCES" | jq -r '.[] | select(.ResourceType=="AWS::Bedrock::DataAutomationProject") | .PhysicalResourceId' 2>/dev/null || echo "")
        fi
        
        log_success "Stack resources read successfully"
    fi
    
    # Log what we found
    log_info "Found resources:"
    [ -n "$BUCKET_NAME" ] && log_info "  S3 Bucket: $BUCKET_NAME"
    [ -n "$LAMBDA_FUNCTION_NAME" ] && log_info "  Lambda Function: $LAMBDA_FUNCTION_NAME"
    [ -n "$DLQ_URL" ] && log_info "  SQS DLQ: $DLQ_URL"
    [ -n "$LAMBDA_ROLE_NAME" ] && log_info "  IAM Role: $LAMBDA_ROLE_NAME"
    [ -n "$BLUEPRINT_ARN" ] && log_info "  BDA Blueprint: $BLUEPRINT_ARN"
    [ -n "$PROJECT_ARN" ] && log_info "  BDA Project: $PROJECT_ARN"
    
    return 0
}

# Function to destroy CDK stack
destroy_cdk_stack() {
    log_info "Destroying CDK stack: $STACK_NAME"
    
    cd "$CDK_DIR"
    
    # Check if stack exists
    if ! aws cloudformation describe-stacks --stack-name "$STACK_NAME" --region "$REGION" &> /dev/null; then
        log_warning "Stack $STACK_NAME does not exist or already deleted"
        cd ..
        return 0
    fi
    
    # Destroy the stack
    if [ "$FORCE_DELETE" = "true" ]; then
        log_warning "Force destroying CDK stack..."
        uv run cdk destroy --force --require-approval never
    else
        log_info "Destroying CDK stack (will prompt for confirmation)..."
        uv run cdk destroy --require-approval never
    fi
    
    # Wait for stack deletion to complete
    log_info "Waiting for stack deletion to complete..."
    aws cloudformation wait stack-delete-complete --stack-name "$STACK_NAME" --region "$REGION" || {
        log_error "Stack deletion failed or timed out"
        cd ..
        return 1
    }
    
    cd ..
    log_success "CDK stack destroyed successfully"
}

# Function to clean up specific S3 bucket (only the one from our stack)
cleanup_s3_bucket() {
    if [ -z "$BUCKET_NAME" ]; then
        log_info "No S3 bucket found in stack resources"
        return 0
    fi
    
    log_info "Cleaning up S3 bucket: $BUCKET_NAME"
    
    # Check if bucket exists
    if ! aws s3api head-bucket --bucket "$BUCKET_NAME" --region "$REGION" 2>/dev/null; then
        log_success "S3 bucket $BUCKET_NAME does not exist or already deleted"
        return 0
    fi
    
    if [ "$FORCE_DELETE" = "true" ]; then
        log_info "Force deleting bucket contents and bucket: $BUCKET_NAME"
        # Empty bucket first
        aws s3 rm "s3://$BUCKET_NAME" --recursive --region "$REGION" 2>/dev/null || true
        # Delete bucket
        aws s3api delete-bucket --bucket "$BUCKET_NAME" --region "$REGION" 2>/dev/null || {
            log_error "Failed to delete bucket: $BUCKET_NAME"
            return 1
        }
        log_success "S3 bucket $BUCKET_NAME deleted successfully"
    else
        log_warning "S3 bucket $BUCKET_NAME found but not deleted (use 'true' as argument to force delete)"
    fi
}

# Function to clean up specific Lambda function (only the one from our stack)
cleanup_lambda_function() {
    if [ -z "$LAMBDA_FUNCTION_NAME" ]; then
        log_info "No Lambda function found in stack resources"
        return 0
    fi
    
    log_info "Cleaning up Lambda function: $LAMBDA_FUNCTION_NAME"
    
    # Check if function exists
    if ! aws lambda get-function --function-name "$LAMBDA_FUNCTION_NAME" --region "$REGION" &>/dev/null; then
        log_success "Lambda function $LAMBDA_FUNCTION_NAME does not exist or already deleted"
        return 0
    fi
    
    if [ "$FORCE_DELETE" = "true" ]; then
        log_info "Force deleting Lambda function: $LAMBDA_FUNCTION_NAME"
        aws lambda delete-function --function-name "$LAMBDA_FUNCTION_NAME" --region "$REGION" 2>/dev/null || {
            log_error "Failed to delete Lambda function: $LAMBDA_FUNCTION_NAME"
            return 1
        }
        log_success "Lambda function $LAMBDA_FUNCTION_NAME deleted successfully"
    else
        log_warning "Lambda function $LAMBDA_FUNCTION_NAME found but not deleted (use 'true' as argument to force delete)"
    fi
}

# Function to clean up specific SQS queue (only the DLQ from our stack)
cleanup_sqs_queue() {
    if [ -z "$DLQ_URL" ]; then
        log_info "No SQS DLQ found in stack resources"
        return 0
    fi
    
    QUEUE_NAME=$(basename "$DLQ_URL")
    log_info "Cleaning up SQS DLQ: $QUEUE_NAME"
    
    # Check if queue exists
    if ! aws sqs get-queue-attributes --queue-url "$DLQ_URL" --region "$REGION" &>/dev/null; then
        log_success "SQS DLQ $QUEUE_NAME does not exist or already deleted"
        return 0
    fi
    
    if [ "$FORCE_DELETE" = "true" ]; then
        log_info "Force deleting SQS DLQ: $QUEUE_NAME"
        aws sqs delete-queue --queue-url "$DLQ_URL" --region "$REGION" 2>/dev/null || {
            log_error "Failed to delete SQS DLQ: $QUEUE_NAME"
            return 1
        }
        log_success "SQS DLQ $QUEUE_NAME deleted successfully"
    else
        log_warning "SQS DLQ $QUEUE_NAME found but not deleted (use 'true' as argument to force delete)"
    fi
}

# Function to clean up specific BDA project (only the one from our stack)
cleanup_bda_project() {
    # First try to use the PROJECT_ARN from stack resources
    if [ -n "$PROJECT_ARN" ]; then
        PROJECT_NAME=$(echo "$PROJECT_ARN" | cut -d'/' -f2)
        log_info "Cleaning up BDA project from stack: $PROJECT_NAME"
        
        # Check if project exists
        if aws bedrock-data-automation get-data-automation-project --project-arn "$PROJECT_ARN" --region "$REGION" &>/dev/null; then
            if [ "$FORCE_DELETE" = "true" ]; then
                log_info "Force deleting BDA project: $PROJECT_NAME"
                aws bedrock-data-automation delete-data-automation-project --project-arn "$PROJECT_ARN" --region "$REGION" 2>/dev/null || {
                    log_error "Failed to delete BDA project: $PROJECT_NAME"
                    return 1
                }
                log_success "BDA project $PROJECT_NAME deleted successfully"
            else
                log_warning "BDA project $PROJECT_NAME found but not deleted (use 'true' as argument to force delete)"
            fi
            return 0
        fi
    fi
    
    # Fallback: Search for BDA projects by pattern
    log_info "Searching for BDA projects by pattern..."
    ACCOUNT_ID=$(get_account_id)
    
    # List all BDA projects and find ones matching our pattern
    BDA_PROJECTS=$(aws bedrock-data-automation list-data-automation-projects --region "$REGION" --query "projects[].{Name:projectName,Arn:projectArn}" --output json 2>/dev/null || echo "[]")
    
    if [ "$BDA_PROJECTS" != "[]" ]; then
        # Look for projects with our naming pattern
        MATCHING_PROJECTS=$(echo "$BDA_PROJECTS" | jq -r ".[] | select(.Name | contains(\"resume-parser-project-$ACCOUNT_ID\")) | .Arn" 2>/dev/null || echo "")
        
        if [ -n "$MATCHING_PROJECTS" ]; then
            for project_arn in $MATCHING_PROJECTS; do
                project_name=$(echo "$project_arn" | cut -d'/' -f2)
                log_info "Found BDA project: $project_name"
                
                if [ "$FORCE_DELETE" = "true" ]; then
                    log_info "Force deleting BDA project: $project_name"
                    aws bedrock-data-automation delete-data-automation-project --project-arn "$project_arn" --region "$REGION" 2>/dev/null || {
                        log_error "Failed to delete BDA project: $project_name"
                        continue
                    }
                    log_success "BDA project $project_name deleted successfully"
                else
                    log_warning "BDA project $project_name found but not deleted (use 'true' as argument to force delete)"
                fi
            done
        else
            log_info "No matching BDA projects found"
        fi
    else
        log_info "No BDA projects found"
    fi
}

# Function to clean up specific BDA blueprint (only the one from our stack)
cleanup_bda_blueprint() {
    # First try to use the BLUEPRINT_ARN from stack resources
    if [ -n "$BLUEPRINT_ARN" ]; then
        BLUEPRINT_NAME=$(echo "$BLUEPRINT_ARN" | cut -d'/' -f2)
        log_info "Cleaning up BDA blueprint from stack: $BLUEPRINT_NAME"
        
        # Check if blueprint exists
        if aws bedrock-data-automation get-blueprint --blueprint-arn "$BLUEPRINT_ARN" --region "$REGION" &>/dev/null; then
            if [ "$FORCE_DELETE" = "true" ]; then
                log_info "Force deleting BDA blueprint: $BLUEPRINT_NAME"
                aws bedrock-data-automation delete-blueprint --blueprint-arn "$BLUEPRINT_ARN" --region "$REGION" 2>/dev/null || {
                    log_error "Failed to delete BDA blueprint: $BLUEPRINT_NAME"
                    return 1
                }
                log_success "BDA blueprint $BLUEPRINT_NAME deleted successfully"
            else
                log_warning "BDA blueprint $BLUEPRINT_NAME found but not deleted (use 'true' as argument to force delete)"
            fi
            return 0
        fi
    fi
    
    # Fallback: Search for BDA blueprints by pattern
    log_info "Searching for BDA blueprints by pattern..."
    ACCOUNT_ID=$(get_account_id)
    
    # List all BDA blueprints and find ones matching our pattern
    BDA_BLUEPRINTS=$(aws bedrock-data-automation list-blueprints --region "$REGION" --query "blueprints[].{Name:blueprintName,Arn:blueprintArn}" --output json 2>/dev/null || echo "[]")
    
    if [ "$BDA_BLUEPRINTS" != "[]" ]; then
        # Look for blueprints with our naming pattern
        MATCHING_BLUEPRINTS=$(echo "$BDA_BLUEPRINTS" | jq -r ".[] | select(.Name | contains(\"resume-parser-hierarchical-$ACCOUNT_ID\")) | .Arn" 2>/dev/null || echo "")
        
        if [ -n "$MATCHING_BLUEPRINTS" ]; then
            for blueprint_arn in $MATCHING_BLUEPRINTS; do
                blueprint_name=$(echo "$blueprint_arn" | cut -d'/' -f2)
                log_info "Found BDA blueprint: $blueprint_name"
                
                if [ "$FORCE_DELETE" = "true" ]; then
                    log_info "Force deleting BDA blueprint: $blueprint_name"
                    aws bedrock-data-automation delete-blueprint --blueprint-arn "$blueprint_arn" --region "$REGION" 2>/dev/null || {
                        log_error "Failed to delete BDA blueprint: $blueprint_name"
                        continue
                    }
                    log_success "BDA blueprint $blueprint_name deleted successfully"
                else
                    log_warning "BDA blueprint $blueprint_name found but not deleted (use 'true' as argument to force delete)"
                fi
            done
        else
            log_info "No matching BDA blueprints found"
        fi
    else
        log_info "No BDA blueprints found"
    fi
}

# Function to clean up specific IAM role (only the one from our stack)
cleanup_iam_role() {
    if [ -z "$LAMBDA_ROLE_NAME" ]; then
        log_info "No IAM role found in stack resources"
        return 0
    fi
    
    log_info "Cleaning up IAM role: $LAMBDA_ROLE_NAME"
    
    # Check if role exists
    if ! aws iam get-role --role-name "$LAMBDA_ROLE_NAME" &>/dev/null; then
        log_success "IAM role $LAMBDA_ROLE_NAME does not exist or already deleted"
        return 0
    fi
    
    if [ "$FORCE_DELETE" = "true" ]; then
        log_info "Force deleting IAM role: $LAMBDA_ROLE_NAME"
        
        # Detach managed policies
        ATTACHED_POLICIES=$(aws iam list-attached-role-policies --role-name "$LAMBDA_ROLE_NAME" --query "AttachedPolicies[].PolicyArn" --output text 2>/dev/null || echo "")
        for policy_arn in $ATTACHED_POLICIES; do
            aws iam detach-role-policy --role-name "$LAMBDA_ROLE_NAME" --policy-arn "$policy_arn" 2>/dev/null || true
        done
        
        # Delete inline policies
        INLINE_POLICIES=$(aws iam list-role-policies --role-name "$LAMBDA_ROLE_NAME" --query "PolicyNames" --output text 2>/dev/null || echo "")
        for policy_name in $INLINE_POLICIES; do
            aws iam delete-role-policy --role-name "$LAMBDA_ROLE_NAME" --policy-name "$policy_name" 2>/dev/null || true
        done
        
        # Delete role
        aws iam delete-role --role-name "$LAMBDA_ROLE_NAME" 2>/dev/null || {
            log_error "Failed to delete IAM role: $LAMBDA_ROLE_NAME"
            return 1
        }
        log_success "IAM role $LAMBDA_ROLE_NAME deleted successfully"
    else
        log_warning "IAM role $LAMBDA_ROLE_NAME found but not deleted (use 'true' as argument to force delete)"
    fi
}

# Function to verify cleanup of specific resources
verify_cleanup() {
    log_info "Verifying cleanup..."
    
    # Check if stack still exists
    if aws cloudformation describe-stacks --stack-name "$STACK_NAME" --region "$REGION" &> /dev/null; then
        log_error "Stack $STACK_NAME still exists!"
        return 1
    fi
    
    log_success "Stack verification passed"
    
    # Check for remaining resources if force delete was used
    if [ "$FORCE_DELETE" = "true" ]; then
        log_info "Checking for any remaining resources..."
        
        ACCOUNT_ID=$(get_account_id)
        
        # Check S3 buckets
        REMAINING_BUCKETS=$(aws s3api list-buckets --query "Buckets[?contains(Name, 'bda-resume-processing-$ACCOUNT_ID')].Name" --output text 2>/dev/null || echo "")
        if [ -n "$REMAINING_BUCKETS" ]; then
            log_warning "Remaining S3 buckets: $REMAINING_BUCKETS"
        fi
        
        # Check Lambda functions
        REMAINING_FUNCTIONS=$(aws lambda list-functions --region "$REGION" --query "Functions[?contains(FunctionName, 'BDAProcessor') || contains(FunctionName, 'BDAResumeStack')].FunctionName" --output text 2>/dev/null || echo "")
        if [ -n "$REMAINING_FUNCTIONS" ]; then
            log_warning "Remaining Lambda functions: $REMAINING_FUNCTIONS"
        fi
        
        # Check BDA projects
        REMAINING_PROJECTS=$(aws bedrock-data-automation list-data-automation-projects --region "$REGION" --query "projects[?contains(projectName, 'resume-parser-project-$ACCOUNT_ID')].projectName" --output text 2>/dev/null || echo "")
        if [ -n "$REMAINING_PROJECTS" ]; then
            log_warning "Remaining BDA projects: $REMAINING_PROJECTS"
        fi
        
        # Check BDA blueprints
        REMAINING_BLUEPRINTS=$(aws bedrock-data-automation list-blueprints --region "$REGION" --query "blueprints[?contains(blueprintName, 'resume-parser-hierarchical-$ACCOUNT_ID')].blueprintName" --output text 2>/dev/null || echo "")
        if [ -n "$REMAINING_BLUEPRINTS" ]; then
            log_warning "Remaining BDA blueprints: $REMAINING_BLUEPRINTS"
        fi
    fi
    
    log_success "Cleanup verification completed"
}

# Main execution
main() {
    echo -e "${BLUE}Starting cleanup process...${NC}"
    echo "Force delete mode: $FORCE_DELETE"
    echo ""
    
    # Check prerequisites
    check_aws_cli
    
    # Read CDK resources (optional, may fail if stack doesn't exist)
    read_cdk_resources || log_warning "Could not read CDK resources, proceeding with pattern-based cleanup"
    
    # Destroy CDK stack first
    destroy_cdk_stack
    
    # Clean up any stale resources
    if [ "$FORCE_DELETE" = "true" ]; then
        log_info "Performing force cleanup of stale resources..."
        cleanup_s3_bucket
        cleanup_lambda_function
        cleanup_sqs_queue
        cleanup_bda_project
        cleanup_bda_blueprint
        cleanup_iam_role
    else
        log_info "Scanning for stale resources (use 'true' as argument to force delete)..."
        cleanup_s3_bucket
        cleanup_lambda_function
        cleanup_sqs_queue
        cleanup_bda_project
        cleanup_bda_blueprint
        cleanup_iam_role
    fi
    
    # Verify cleanup
    verify_cleanup
    
    echo ""
    log_success "🎉 Cleanup completed successfully!"
    
    if [ "$FORCE_DELETE" != "true" ]; then
        echo ""
        log_info "💡 To force delete any remaining stale resources, run:"
        echo "   ./scripts/cleanup.sh true"
    fi
}

# Run main function
main "$@"