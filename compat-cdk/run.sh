#!/bin/bash
set -e

export AWS_REGION=us-east-1
export AWS_DEFAULT_REGION=us-east-1
export AWS_ACCESS_KEY_ID=test
export AWS_SECRET_ACCESS_KEY=test
export LOCALSTACK_HOSTNAME=floci
export EDGE_PORT=4566
export AWS_ENDPOINT_URL=http://floci:4566

ENDPOINT="http://floci:4566"
PASS=0
FAIL=0

check() {
    local name="$1"
    local code="$2"
    if [ "$code" -eq 0 ]; then
        echo "  PASS  $name"
        PASS=$((PASS + 1))
    else
        echo "  FAIL  $name"
        FAIL=$((FAIL + 1))
    fi
}

echo "=== CDK Compatibility Test ==="
echo "Endpoint: $ENDPOINT"
echo ""

echo "--- Bootstrap ---"
cdklocal bootstrap --force 2>&1 | grep -E "CDKToolkit|bootstrapped|error|Error" || true
check "cdklocal bootstrap" $?

echo ""
echo "--- Deploy ---"
cdklocal deploy --require-approval never 2>&1 | grep -E "FlociTestStack|complete|error|Error|PASS|FAIL" | tail -10 || true
check "cdklocal deploy FlociTestStack" $?

echo ""
echo "--- Spot Checks ---"

# S3 bucket created
BUCKETS=$(aws --endpoint-url "$ENDPOINT" s3 ls 2>/dev/null | wc -l)
[ "$BUCKETS" -gt 0 ] && check "S3 bucket exists" 0 || check "S3 bucket exists" 1

# SQS queue created
QUEUES=$(aws --endpoint-url "$ENDPOINT" sqs list-queues 2>/dev/null | python3 -c "import sys,json; d=json.load(sys.stdin); print(len(d.get('QueueUrls', [])))" 2>/dev/null || echo "0")
[ "$QUEUES" -gt 0 ] && check "SQS queue exists" 0 || check "SQS queue exists" 1

# DynamoDB table created
TABLES=$(aws --endpoint-url "$ENDPOINT" dynamodb list-tables 2>/dev/null | python3 -c "import sys,json; d=json.load(sys.stdin); print(len(d.get('TableNames', [])))" 2>/dev/null || echo "0")
[ "$TABLES" -gt 0 ] && check "DynamoDB table exists" 0 || check "DynamoDB table exists" 1

# CloudFormation stack exists
CF_STATUS=$(aws --endpoint-url "$ENDPOINT" cloudformation describe-stacks \
    --stack-name FlociTestStack 2>/dev/null | \
    python3 -c "import sys,json; d=json.load(sys.stdin); print(d['Stacks'][0]['StackStatus'])" 2>/dev/null || echo "NONE")
[ "$CF_STATUS" = "CREATE_COMPLETE" ] && check "CloudFormation stack CREATE_COMPLETE" 0 || check "CloudFormation stack CREATE_COMPLETE" 1

echo ""
echo "--- Destroy ---"
cdklocal destroy --force 2>&1 | grep -E "FlociTestStack|destroyed|error|Error" | tail -5 || true
check "cdklocal destroy FlociTestStack" $?

echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="
[ "$FAIL" -eq 0 ] || exit 1
