# BDA Resume Parser - Data Flow

## Real-Time Processing Flow

```
┌─────────────────┐    ┌──────────────────┐    ┌─────────────────┐
│ Interactive     │───▶│  S3 Event        │───▶│ Lambda Trigger  │
│ Menu System     │    │  Notification    │    │ (Sub-second)    │
│ bda_workflow.sh │    │                  │    │                 │
└─────────────────┘    └──────────────────┘    └─────────────────┘
         │                                               │
         ▼ (monitors)                                    ▼
┌─────────────────┐    ┌──────────────────┐    ┌─────────────────┐
│ Lambda Logs     │    │ Structured JSON  │◀───│  BDA Blueprint  │
│ Real-time       │    │ Output to S3     │    │  Processing     │
│ Monitoring      │    │                  │    │ (Stage Check)   │
└─────────────────┘    └──────────────────┘    └─────────────────┘
         │                       │                       │
         ▼ (on error)            ▼ (success)             ▼ (on failure)
┌─────────────────┐    ┌──────────────────┐    ┌─────────────────┐
│ Return to Menu  │    │ Results Download │    │ DLQ + Retry     │
│ with Error      │    │ & Return to Menu │    │ Logic           │
└─────────────────┘    └──────────────────┘    └─────────────────┘
```

## Data Transformation Pipeline

```
INPUT: ./scripts/bda_workflow.sh resume.pdf

INTERACTIVE MENU:
├── 1. Test in DEVELOPMENT stage
├── 2. Promote blueprint to LIVE
├── 3. Process resume (Production) ← Blueprint stage verification
├── 4. Test in LIVE stage
├── 5. Full workflow (DEV → Promote → LIVE)
└── 6. Exit

PROCESSING FLOW (Option 3 - Production):
├── Blueprint Check: Verify LIVE stage or warn user
├── Upload: s3://bucket/input/20250923_201646_resume.pdf
├── Lambda Trigger: S3 Event → handler.py
├── BDA Processing:
│   ├── Blueprint: Hierarchical extraction schema (verified stage)
│   ├── Processing: ~24 seconds average
│   ├── Retry Logic: 3 attempts with exponential backoff
│   └── Error Detection: Script monitors logs and returns to menu on errors
├── Results: s3://bucket/output/20250923_201646_resume/job_metadata.json/.../result.json
├── Download: ./results/20250923_201646_resume_result.json
└── Return: Back to interactive menu

SCRIPT MONITORING:
├── Real-time log tailing: aws logs tail /aws/lambda/function-name --follow
├── Error detection: Monitors Lambda logs for ERROR patterns (fixed integer handling)
├── Timeout protection: Max 5 minutes wait time
├── Immediate cleanup: pkill -f "aws logs tail" on completion
└── Menu return: Always returns to menu after operation

STRUCTURED OUTPUT:
{
  "inference_result": {
    "personal_info": {"full_name", "email", "phone", "address", "linkedin"},
    "educational_info": {"institution", "degree", "graduation_year", "gpa"},
    "experience": {"current_position", "years_total", "key_achievements"},
    "skills": {"technical", "soft", "languages", "certifications"}
  }
}
```

## Component Interactions

```
┌─────────────────────────────────────────────────────────────────┐
│                        AWS INFRASTRUCTURE                       │
├─────────────────────────────────────────────────────────────────┤
│  S3 Bucket                Lambda Function         IAM Roles     │
│  ├── input/               ├── handler.py          ├── Execution │
│  ├── output/              ├── bda_parser/ (local) ├── S3 Access │
│  └── Event Config         └── Retry Logic         └── BDA Access│
├─────────────────────────────────────────────────────────────────┤
│  CloudWatch Logs          DLQ + SNS              BDA Service    │
│  ├── Function Logs        ├── Failed Messages    ├── Blueprint  │
│  ├── Error Tracking       └── Alert Notifications├── LIVE Stage │
│  └── Real-time Tailing    └── Automatic Cleanup  └── Processing │
└─────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────┐
│                  INTERACTIVE MENU SYSTEM                       │
├─────────────────────────────────────────────────────────────────┤
│  bda_workflow.sh          CDK Infrastructure      CLI Tools     │
│  ├── Menu-driven UI       ├── app.py              ├── promote_  │
│  ├── 6 operation modes    ├── bda_stack.py        │   blueprint │
│  ├── Blueprint checking   └── Auto-deployment     └── Blueprint │
│  ├── Log monitoring       └── Layer-free design   └── Promotion │
│  ├── Error detection      └── Direct inclusion    └── Validation│
│  ├── Results preview      └── Menu return system  └── Stage Mgmt│
│  └── Production safety    └── Integer fix applied └── User Flow │
└─────────────────────────────────────────────────────────────────┘
```

## Interactive Menu Modes

### Production Processing (Option 3)
```
Menu Choice → Blueprint Check → Upload → Monitor → Download → Menu Return
     ↓             ↓             ↓        ↓         ↓          ↓
   Option 3    LIVE Stage?    S3 Event  Lambda   Results   Continue?
              Warn if not      ↓        Logs     JSON      Next Action
              User decides   Process    ↓        ↓
              Continue/      BDA       Wait     Preview
              Promote/       ↓         ↓        ↓
              Return        Success   Error    Menu
```

### Full Workflow (Option 5)
```
Menu Choice → DEV Test → Promote → LIVE Test → Menu Return
     ↓          ↓          ↓         ↓          ↓
   Option 5   Upload    Inline    Upload    Complete
             Process   Blueprint  Process   Success
               ↓       Promotion    ↓         ↓
             Results      ↓       Results   Menu
             Preview   No Menu    Preview   Return
               ↓       Return       ↓
             Continue    ↓        Continue
               ↓       Auto        ↓
             Step 2    Continue   Done
```

### Individual Operations (Options 1,2,4)
```
Menu Choice → Single Operation → Results → Menu Return
     ↓              ↓              ↓         ↓
   1,2,4        Specific Task   Success/   Continue?
              (DEV/Promote/     Error      Next
               LIVE Test)        ↓        Action
                  ↓           Preview
                Task           ↓
               Complete      Menu
                  ↓         Return
                Menu
               Return
```
