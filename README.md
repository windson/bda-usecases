# BDA Resume Parser - Real-Time Processing

Automated resume parsing using Amazon Bedrock Data Automation with hierarchical data extraction and real-time S3 event triggers.

## Architecture

![BDA Architecture](architecture/bda_architecture.png)

**Real-Time Event-Driven Processing:**
1. **S3 Upload** → Automatic trigger via S3 Event Notifications
2. **Lambda Processing** → BDA hierarchical blueprint extraction  
3. **Structured Output** → Organized JSON results saved to S3
4. **Error Handling** → DLQ + monitoring for failures

More detailed description in [Architecture](architecture/README.md)

**Key Benefits:**
- ✅ **Hierarchical Data Structure** - Organized sections (Personal, Education, Experience, Skills)
- ✅ **Sub-second triggers** - Immediate processing on upload
- ✅ **Auto-scaling** - Handle multiple concurrent resumes  
- ✅ **Infrastructure as Code** - Complete CDK deployment with blueprints
- ✅ **Development Workflow** - DEV → LIVE promotion for safe deployments

## Quick Start

### 1. Deploy Complete Infrastructure (Blueprint + Resources)
```bash
# Deploy everything with CDK (blueprint, project, S3, Lambda, etc.)
cd infrastructure
uv sync
uv run cdk bootstrap  # One-time setup
uv run cdk deploy

# Note: This creates blueprint and project in DEVELOPMENT stage
```

### 2. Test in Development
```bash
# Test with sample resume in DEV stage
uv run cli/test_upload.py data/sample_resume.pdf

# Verify results and blueprint performance
```

### 3. Promote to Production
```bash
# When ready, promote blueprint and project to LIVE stage
uv run cli/promote_blueprint.py

# Script automatically reads ARNs from CDK outputs - no manual input needed!
```

### 4. Interactive Processing
```bash
# 🚀 Launch interactive menu
./scripts/bda_workflow.sh data/sample_resume.pdf

# Choose from menu:
# Option 3: Production processing with blueprint stage verification
# Option 5: Full DEV→LIVE workflow automation
# Option 1-2: Individual development and promotion steps
# Option 4: LIVE stage testing
```

## Project Structure

```
bda_usecases/
├── infrastructure/              # CDK Infrastructure as Code
│   ├── app.py                  # CDK app entry point
│   ├── stacks/bda_stack.py     # S3, Lambda, IAM resources
│   └── pyproject.toml          # CDK dependencies
├── lambda/                     # Lambda function code
│   ├── handler.py              # S3 event processor
│   ├── bda_parser/             # Core BDA processing module
│   │   ├── bda_client.py       # BDA client with blueprint processing
│   │   ├── blueprint_schema.json # Custom extraction schema
│   │   └── config.py           # AWS configuration
│   └── pyproject.toml          # Runtime dependencies
├── cli/                        # Setup & testing tools
│   ├── promote_blueprint.py    # Promote DEV → LIVE stage
│   └── test_upload.py          # Manual upload testing
├── scripts/                    # Automation scripts
│   ├── bda_workflow.sh         # 🚀 Unified processing & workflow automation
│   └── cleanup.sh              # Infrastructure cleanup script
├── data/
│   └── sample_resume.pdf       # Test document
└── architecture/               # Architecture diagrams and documentation
    ├── README.md               # Detailed architecture overview
    ├── bda_architecture.png    # System architecture diagram
    └── bda_workflow.png        # Development workflow diagram
```

## Real-Time Processing Flow

### 1. **Automatic Trigger**
```
Resume Upload → s3://bucket/input/resume.pdf
                     ↓ (S3 Event Notification)
                Lambda Function Invoked
```

### 2. **Lambda Processing**
```python
# Lambda receives S3 event
{
  "Records": [{
    "s3": {
      "bucket": {"name": "bda-resume-bucket"},
      "object": {"key": "input/resume.pdf"}
    }
  }]
}

# Processes with BDA blueprint
# Saves results to output/ prefix
```

### 3. **Output Structure**
```
s3://bucket/
├── input/
│   └── 20240923_112801_resume.pdf     # Uploaded resume
└── output/
    └── 20240923_112801_resume/        # Processing results
        └── 0/custom_output/0/
            └── result.json            # Structured data
```

### Development Workflow

![BDA Workflow](architecture/bda_workflow.png)

1. **DEVELOPMENT Stage** - Blueprint and project created for testing
2. **Testing Phase** - Validate extraction quality with sample resumes
3. **LIVE Promotion** - Move to production when ready
4. **Monitoring** - CloudWatch logs and error tracking

### Hierarchical Blueprint Schema
Extracts structured resume data in organized sections:
```json
{
  "matched_blueprint": {
    "arn": "arn:aws:bedrock:ap-south-1:###:blueprint/###",
    "name": "resume-parser-hierarchical-###",
    "confidence": 1
  },
  "document_class": {
    "type": "Resume"
  },
  "split_document": {
    "page_indices": [0, 1]
  },
  "inference_result": {
    "skills": {
      "technical": "Programming Languages: Python, JavaScript, Java, Go, SQL Cloud Platforms: AWS, Azure, Google Cloud Platform Frameworks: React, Django, Flask, Express.js Databases: PostgreSQL, MongoDB, Redis, DynamoDB DevOps: Docker, Kubernetes, Jenkins, Terraform, Git",
      "languages": "English (Native), Spanish (Conversational)",
      "certifications": "AWS Solutions Architect Associate (AWS-SAA-123456), Certified Kubernetes Administrator (CKA-789012)",
      "tools": "Python, AWS, Docker, Kubernetes, PostgreSQL, JavaScript, React, Django, Flask, Express.js, JavaScript, React, Node.js, MongoDB, PostgreSQL, Redis, DynamoDB, Jenkins, Terraform, Git",
      "soft": "Leadership, Team Collaboration, Problem Solving, Communication, Project Management"
    },
    "personal_info": {
      "full_name": "John Smith",
      "address": "123 Main Street, Seattle, WA 98101",
      "phone": "(555) 123-4567",
      "linkedin": "linkedin.com/in/johnsmith",
      "email": "john.smith@email.com"
    },
    "educational_info": {
      "institution": "University of Washington, Seattle, WA",
      "graduation_year": "June 2020",
      "degree": "Bachelor of Science",
      "gpa": "3.8",
      "field_of_study": "Computer Science"
    },
    "experience": {
      "key_achievements": "Lead development of cloud-native applications using AWS services, Reduced system latency by 40% through performance optimization, Led team of 5 engineers on microservices migration project, Implemented CI/CD pipeline reducing deployment time by 60%, Developed full-stack web applications for e-commerce platform, Built payment processing system handling $1M+ in monthly transactions, Improved application performance by 50% through code optimization",
      "current_position": "Senior Software Engineer",
      "current_company": "Tech Corp",
      "years_total": "4+",
      "previous_roles": "Software Engineer, StartupXYZ, July 2020 - December 2021"
    }
  }
}
```

**Benefits of Hierarchical Structure:**
- ✅ **Organized Output** - Clear sections for downstream processing
- ✅ **Easy Integration** - Structured for databases and APIs
- ✅ **Maintainable Schema** - Reusable object definitions
- ✅ **Type Safety** - Consistent data types per section

### Monitoring
```bash
# Lambda function logs
aws logs tail /aws/lambda/BDAResumeStack-BDAProcessorFunction --follow

# DLQ messages (failed processing)
aws sqs receive-message --queue-url <dlq-url>

# S3 event notifications
aws s3api get-bucket-notification-configuration --bucket <bucket-name>
```

## Monitoring & Debugging

### Real-Time Monitoring
```bash
# Check Lambda logs (real-time)
aws logs tail /aws/lambda/BDAResumeStack-BDAProcessorFunction --follow

# List processed results
aws s3 ls s3://<bucket-name>/output/ --recursive

# Check CDK stack outputs
cd infrastructure && uv run cdk list --json
```

### Error Handling
```bash
# Check DLQ for failed processing
aws sqs receive-message --queue-url <dlq-url>

# S3 event configuration
aws s3api get-bucket-notification-configuration --bucket <bucket-name>
```

## Advanced Usage

### 🚀 Script Usage Options
```bash
# Interactive menu (recommended)
./scripts/bda_workflow.sh data/sample_resume.pdf

# Process multiple files (choose option 3 for each)
for file in resumes/*.pdf; do
    echo "Processing $file..."
    ./scripts/bda_workflow.sh "$file"
    # Select option 3 for production processing
done
```

### Infrastructure Management
```bash
cd infrastructure

# Preview changes before deployment
uv run cdk diff

# Deploy updates
uv run cdk deploy

# View stack outputs (ARNs, bucket names, etc.)
uv run aws cloudformation describe-stacks --stack-name BDAResumeStack --query "Stacks[0].Outputs"

# Cleanup (removes all resources)
uv run cdk destroy
```

### Complete Infrastructure Cleanup
The project includes a comprehensive cleanup script that safely removes all AWS resources:

```bash
# Safe cleanup - shows what would be deleted but doesn't delete
./scripts/cleanup.sh

# Force cleanup - actually deletes all resources
./scripts/cleanup.sh true
```

**Cleanup Script Features:**
- ✅ **Safe by default** - Dry run mode shows resources without deleting
- ✅ **CDK-aware** - Reads actual resources from CloudFormation stack
- ✅ **Comprehensive** - Removes S3 buckets, Lambda functions, BDA resources, IAM roles
- ✅ **Smart detection** - Finds resources even if stack is partially deleted
- ✅ **Force mode** - `true` argument enables actual deletion
- ✅ **Verification** - Confirms cleanup completion and shows any remaining resources

**What gets cleaned up:**
- CloudFormation stack (CDK-managed resources)
- S3 bucket and all contents
- Lambda functions
- BDA blueprints and projects
- SQS dead letter queues
- IAM roles and policies

**Usage Examples:**
```bash
# Check what would be deleted (safe preview)
./scripts/cleanup.sh

# Actually delete everything (use with caution)
./scripts/cleanup.sh true

# Alternative: CDK-only cleanup (may leave some resources)
cd infrastructure && uv run cdk destroy
```
