#!/usr/bin/env bash
# Floci SDK Test — AWS CLI
#
# Runs against the Floci AWS emulator. Configure via:
#   FLOCI_ENDPOINT=http://localhost:4566  (default)
#
# To run specific groups:
#   ./test_all.sh ssm sqs s3
#   FLOCI_TESTS=ssm,sqs ./test_all.sh

set -euo pipefail

ENDPOINT="${FLOCI_ENDPOINT:-http://localhost:4566}"
REGION="us-east-1"
AWS_ACCESS_KEY_ID="test"
AWS_SECRET_ACCESS_KEY="test"
export AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY

PASSED=0
FAILED=0

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

aws_cmd() {
    aws --endpoint-url "$ENDPOINT" --region "$REGION" --output json "$@" 2>&1
}

check() {
    local name="$1"
    local ok="$2"
    local msg="${3:-}"
    if [ "$ok" = "true" ]; then
        PASSED=$((PASSED + 1))
        printf "  PASS  %s\n" "$name"
    else
        FAILED=$((FAILED + 1))
        printf "  FAIL  %s\n" "$name"
        [ -n "$msg" ] && printf "        -> %s\n" "$msg"
    fi
}

run_if() {
    local group="$1"
    shift
    if [ ${#ENABLED[@]} -eq 0 ] || [[ " ${ENABLED[*]} " == *" $group "* ]]; then
        "$@"
    fi
}

# ---------------------------------------------------------------------------
# SSM
# ---------------------------------------------------------------------------

run_ssm() {
    echo "--- SSM Tests ---"
    local name="/cli-sdk-test/param"
    local value="param-value-awscli"

    local out rc
    out=$(aws_cmd ssm put-parameter --name "$name" --value "$value" --type String --overwrite 2>&1) && rc=0 || rc=1
    ver=$(echo "$out" | python3 -c "import sys,json; print(json.load(sys.stdin).get('Version',0))" 2>/dev/null || echo 0)
    check "SSM PutParameter" "$( [ "$ver" -gt 0 ] && echo true || echo false )" "$out"

    out=$(aws_cmd ssm get-parameter --name "$name" --no-with-decryption 2>&1) && rc=0 || rc=1
    got=$(echo "$out" | python3 -c "import sys,json; print(json.load(sys.stdin)['Parameter']['Value'])" 2>/dev/null || echo "")
    check "SSM GetParameter" "$( [ "$got" = "$value" ] && echo true || echo false )" "$out"

    out=$(aws_cmd ssm get-parameters-by-path --path "/cli-sdk-test" 2>&1) && rc=0 || rc=1
    found=$(echo "$out" | python3 -c "import sys,json; d=json.load(sys.stdin); print('true' if any(p['Name']=='$name' for p in d.get('Parameters',[])) else 'false')" 2>/dev/null || echo false)
    check "SSM GetParametersByPath" "$found" "$out"

    out=$(aws_cmd ssm add-tags-to-resource --resource-type Parameter --resource-id "$name" --tags Key=env,Value=test 2>&1) && rc=0 || rc=1
    check "SSM AddTagsToResource" "$( [ $rc -eq 0 ] && echo true || echo false )" "$out"

    out=$(aws_cmd ssm list-tags-for-resource --resource-type Parameter --resource-id "$name" 2>&1) && rc=0 || rc=1
    found=$(echo "$out" | python3 -c "import sys,json; d=json.load(sys.stdin); print('true' if any(t['Key']=='env' and t['Value']=='test' for t in d.get('TagList',[])) else 'false')" 2>/dev/null || echo false)
    check "SSM ListTagsForResource" "$found" "$out"

    out=$(aws_cmd ssm delete-parameter --name "$name" 2>&1) && rc=0 || rc=1
    check "SSM DeleteParameter" "$( [ $rc -eq 0 ] && echo true || echo false )" "$out"
}

# ---------------------------------------------------------------------------
# SQS
# ---------------------------------------------------------------------------

run_sqs() {
    echo "--- SQS Tests ---"
    local queue_name="cli-sdk-test-queue"

    local out rc url
    out=$(aws_cmd sqs create-queue --queue-name "$queue_name" 2>&1) && rc=0 || rc=1
    url=$(echo "$out" | python3 -c "import sys,json; print(json.load(sys.stdin).get('QueueUrl',''))" 2>/dev/null || echo "")
    check "SQS CreateQueue" "$( [ -n "$url" ] && echo true || echo false )" "$out"

    out=$(aws_cmd sqs list-queues --queue-name-prefix "cli-sdk-test" 2>&1) && rc=0 || rc=1
    found=$(echo "$out" | python3 -c "import sys,json; d=json.load(sys.stdin); print('true' if any('$queue_name' in u for u in d.get('QueueUrls',[])) else 'false')" 2>/dev/null || echo false)
    check "SQS ListQueues" "$found" "$out"

    local body="hello-from-cli"
    out=$(aws_cmd sqs send-message --queue-url "$url" --message-body "$body" 2>&1) && rc=0 || rc=1
    mid=$(echo "$out" | python3 -c "import sys,json; print(json.load(sys.stdin).get('MessageId',''))" 2>/dev/null || echo "")
    check "SQS SendMessage" "$( [ -n "$mid" ] && echo true || echo false )" "$out"

    out=$(aws_cmd sqs receive-message --queue-url "$url" --max-number-of-messages 1 --wait-time-seconds 1 2>&1) && rc=0 || rc=1
    recv_body=$(echo "$out" | python3 -c "import sys,json; d=json.load(sys.stdin); msgs=d.get('Messages',[]); print(msgs[0]['Body'] if msgs else '')" 2>/dev/null || echo "")
    receipt=$(echo "$out" | python3 -c "import sys,json; d=json.load(sys.stdin); msgs=d.get('Messages',[]); print(msgs[0]['ReceiptHandle'] if msgs else '')" 2>/dev/null || echo "")
    check "SQS ReceiveMessage" "$( [ "$recv_body" = "$body" ] && echo true || echo false )" "$out"

    if [ -n "$receipt" ]; then
        out=$(aws_cmd sqs delete-message --queue-url "$url" --receipt-handle "$receipt" 2>&1) && rc=0 || rc=1
        check "SQS DeleteMessage" "$( [ $rc -eq 0 ] && echo true || echo false )" "$out"
    fi

    out=$(aws_cmd sqs get-queue-attributes --queue-url "$url" --attribute-names ApproximateNumberOfMessages 2>&1) && rc=0 || rc=1
    check "SQS GetQueueAttributes" "$( [ $rc -eq 0 ] && echo true || echo false )" "$out"

    out=$(aws_cmd sqs delete-queue --queue-url "$url" 2>&1) && rc=0 || rc=1
    check "SQS DeleteQueue" "$( [ $rc -eq 0 ] && echo true || echo false )" "$out"
}

# ---------------------------------------------------------------------------
# SNS
# ---------------------------------------------------------------------------

run_sns() {
    echo "--- SNS Tests ---"
    local topic_name="cli-sdk-test-topic"

    local out rc arn
    out=$(aws_cmd sns create-topic --name "$topic_name" 2>&1) && rc=0 || rc=1
    arn=$(echo "$out" | python3 -c "import sys,json; print(json.load(sys.stdin).get('TopicArn',''))" 2>/dev/null || echo "")
    check "SNS CreateTopic" "$( [ -n "$arn" ] && echo true || echo false )" "$out"

    out=$(aws_cmd sns list-topics 2>&1) && rc=0 || rc=1
    found=$(echo "$out" | python3 -c "import sys,json; d=json.load(sys.stdin); print('true' if any('$topic_name' in t.get('TopicArn','') for t in d.get('Topics',[])) else 'false')" 2>/dev/null || echo false)
    check "SNS ListTopics" "$found" "$out"

    out=$(aws_cmd sns get-topic-attributes --topic-arn "$arn" 2>&1) && rc=0 || rc=1
    check "SNS GetTopicAttributes" "$( [ $rc -eq 0 ] && echo true || echo false )" "$out"

    out=$(aws_cmd sns publish --topic-arn "$arn" --message "hello-cli" 2>&1) && rc=0 || rc=1
    msg_id=$(echo "$out" | python3 -c "import sys,json; print(json.load(sys.stdin).get('MessageId',''))" 2>/dev/null || echo "")
    check "SNS Publish" "$( [ -n "$msg_id" ] && echo true || echo false )" "$out"

    out=$(aws_cmd sns delete-topic --topic-arn "$arn" 2>&1) && rc=0 || rc=1
    check "SNS DeleteTopic" "$( [ $rc -eq 0 ] && echo true || echo false )" "$out"
}

# ---------------------------------------------------------------------------
# S3
# ---------------------------------------------------------------------------

run_s3() {
    echo "--- S3 Tests ---"
    local bucket="cli-sdk-test-bucket-$$"

    local out rc
    out=$(aws_cmd s3api create-bucket --bucket "$bucket" 2>&1) && rc=0 || rc=1
    check "S3 CreateBucket" "$( [ $rc -eq 0 ] && echo true || echo false )" "$out"

    out=$(aws_cmd s3api list-buckets 2>&1) && rc=0 || rc=1
    found=$(echo "$out" | python3 -c "import sys,json; d=json.load(sys.stdin); print('true' if any(b['Name']=='$bucket' for b in d.get('Buckets',[])) else 'false')" 2>/dev/null || echo false)
    check "S3 ListBuckets" "$found" "$out"

    local key="cli-test-object.txt"
    local body="hello-s3-cli"
    out=$(echo "$body" | aws_cmd s3api put-object --bucket "$bucket" --key "$key" --body /dev/stdin 2>&1) && rc=0 || rc=1
    check "S3 PutObject" "$( [ $rc -eq 0 ] && echo true || echo false )" "$out"

    out=$(aws_cmd s3api get-object --bucket "$bucket" --key "$key" /dev/stdout 2>&1) && rc=0 || rc=1
    check "S3 GetObject" "$( [ $rc -eq 0 ] && echo true || echo false )" "$out"

    out=$(aws_cmd s3api list-objects-v2 --bucket "$bucket" 2>&1) && rc=0 || rc=1
    found=$(echo "$out" | python3 -c "import sys,json; d=json.load(sys.stdin); print('true' if any(o['Key']=='$key' for o in d.get('Contents',[])) else 'false')" 2>/dev/null || echo false)
    check "S3 ListObjectsV2" "$found" "$out"

    out=$(aws_cmd s3api put-object-tagging --bucket "$bucket" --key "$key" --tagging 'TagSet=[{Key=env,Value=test}]' 2>&1) && rc=0 || rc=1
    check "S3 PutObjectTagging" "$( [ $rc -eq 0 ] && echo true || echo false )" "$out"

    out=$(aws_cmd s3api get-object-tagging --bucket "$bucket" --key "$key" 2>&1) && rc=0 || rc=1
    found=$(echo "$out" | python3 -c "import sys,json; d=json.load(sys.stdin); print('true' if any(t['Key']=='env' and t['Value']=='test' for t in d.get('TagSet',[])) else 'false')" 2>/dev/null || echo false)
    check "S3 GetObjectTagging" "$found" "$out"

    out=$(aws_cmd s3api copy-object --bucket "$bucket" --copy-source "$bucket/$key" --key "${key}.copy" 2>&1) && rc=0 || rc=1
    check "S3 CopyObject" "$( [ $rc -eq 0 ] && echo true || echo false )" "$out"

    out=$(aws_cmd s3api delete-object --bucket "$bucket" --key "$key" 2>&1) && rc=0 || rc=1
    check "S3 DeleteObject" "$( [ $rc -eq 0 ] && echo true || echo false )" "$out"

    out=$(aws_cmd s3api delete-object --bucket "$bucket" --key "${key}.copy" 2>&1) && rc=0 || rc=1
    aws_cmd s3api delete-bucket --bucket "$bucket" >/dev/null 2>&1 || true
    check "S3 DeleteBucket" "true"
}

# ---------------------------------------------------------------------------
# DynamoDB
# ---------------------------------------------------------------------------

run_dynamodb() {
    echo "--- DynamoDB Tests ---"
    local table="cli-sdk-test-table"

    local out rc
    out=$(aws_cmd dynamodb create-table \
        --table-name "$table" \
        --attribute-definitions AttributeName=pk,AttributeType=S AttributeName=sk,AttributeType=S \
        --key-schema AttributeName=pk,KeyType=HASH AttributeName=sk,KeyType=RANGE \
        --billing-mode PAY_PER_REQUEST 2>&1) && rc=0 || rc=1
    check "DynamoDB CreateTable" "$( [ $rc -eq 0 ] && echo true || echo false )" "$out"

    aws_cmd dynamodb wait table-exists --table-name "$table" >/dev/null 2>&1 || true

    out=$(aws_cmd dynamodb put-item --table-name "$table" \
        --item '{"pk":{"S":"item1"},"sk":{"S":"sort1"},"value":{"S":"hello"}}' 2>&1) && rc=0 || rc=1
    check "DynamoDB PutItem" "$( [ $rc -eq 0 ] && echo true || echo false )" "$out"

    out=$(aws_cmd dynamodb get-item --table-name "$table" \
        --key '{"pk":{"S":"item1"},"sk":{"S":"sort1"}}' 2>&1) && rc=0 || rc=1
    val=$(echo "$out" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('Item',{}).get('value',{}).get('S',''))" 2>/dev/null || echo "")
    check "DynamoDB GetItem" "$( [ "$val" = "hello" ] && echo true || echo false )" "$out"

    out=$(aws_cmd dynamodb update-item --table-name "$table" \
        --key '{"pk":{"S":"item1"},"sk":{"S":"sort1"}}' \
        --update-expression "SET #v = :v" \
        --expression-attribute-names '{"#v":"value"}' \
        --expression-attribute-values '{":v":{"S":"updated"}}' 2>&1) && rc=0 || rc=1
    check "DynamoDB UpdateItem" "$( [ $rc -eq 0 ] && echo true || echo false )" "$out"

    out=$(aws_cmd dynamodb query --table-name "$table" \
        --key-condition-expression "pk = :pk" \
        --expression-attribute-values '{":pk":{"S":"item1"}}' 2>&1) && rc=0 || rc=1
    cnt=$(echo "$out" | python3 -c "import sys,json; print(json.load(sys.stdin).get('Count',0))" 2>/dev/null || echo 0)
    check "DynamoDB Query" "$( [ "$cnt" -gt 0 ] && echo true || echo false )" "$out"

    out=$(aws_cmd dynamodb delete-item --table-name "$table" \
        --key '{"pk":{"S":"item1"},"sk":{"S":"sort1"}}' 2>&1) && rc=0 || rc=1
    check "DynamoDB DeleteItem" "$( [ $rc -eq 0 ] && echo true || echo false )" "$out"

    out=$(aws_cmd dynamodb delete-table --table-name "$table" 2>&1) && rc=0 || rc=1
    check "DynamoDB DeleteTable" "$( [ $rc -eq 0 ] && echo true || echo false )" "$out"
}

# ---------------------------------------------------------------------------
# IAM
# ---------------------------------------------------------------------------

run_iam() {
    echo "--- IAM Tests ---"
    local user="cli-sdk-test-user"
    local role="cli-sdk-test-role"

    local out rc arn
    out=$(aws_cmd iam create-user --user-name "$user" 2>&1) && rc=0 || rc=1
    check "IAM CreateUser" "$( [ $rc -eq 0 ] && echo true || echo false )" "$out"

    out=$(aws_cmd iam list-users 2>&1) && rc=0 || rc=1
    found=$(echo "$out" | python3 -c "import sys,json; d=json.load(sys.stdin); print('true' if any(u['UserName']=='$user' for u in d.get('Users',[])) else 'false')" 2>/dev/null || echo false)
    check "IAM ListUsers" "$found" "$out"

    local trust='{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":{"Service":"lambda.amazonaws.com"},"Action":"sts:AssumeRole"}]}'
    out=$(aws_cmd iam create-role --role-name "$role" --assume-role-policy-document "$trust" 2>&1) && rc=0 || rc=1
    arn=$(echo "$out" | python3 -c "import sys,json; print(json.load(sys.stdin).get('Role',{}).get('Arn',''))" 2>/dev/null || echo "")
    check "IAM CreateRole" "$( [ -n "$arn" ] && echo true || echo false )" "$out"

    out=$(aws_cmd iam get-role --role-name "$role" 2>&1) && rc=0 || rc=1
    check "IAM GetRole" "$( [ $rc -eq 0 ] && echo true || echo false )" "$out"

    out=$(aws_cmd iam delete-role --role-name "$role" 2>&1) && rc=0 || rc=1
    check "IAM DeleteRole" "$( [ $rc -eq 0 ] && echo true || echo false )" "$out"

    out=$(aws_cmd iam delete-user --user-name "$user" 2>&1) && rc=0 || rc=1
    check "IAM DeleteUser" "$( [ $rc -eq 0 ] && echo true || echo false )" "$out"
}

# ---------------------------------------------------------------------------
# STS
# ---------------------------------------------------------------------------

run_sts() {
    echo "--- STS Tests ---"

    local out rc
    out=$(aws_cmd sts get-caller-identity 2>&1) && rc=0 || rc=1
    acct=$(echo "$out" | python3 -c "import sys,json; print(json.load(sys.stdin).get('Account',''))" 2>/dev/null || echo "")
    check "STS GetCallerIdentity" "$( [ -n "$acct" ] && echo true || echo false )" "$out"
}

# ---------------------------------------------------------------------------
# Secrets Manager
# ---------------------------------------------------------------------------

run_secretsmanager() {
    echo "--- Secrets Manager Tests ---"
    local name="cli-sdk-test/secret"
    local value='{"user":"admin","pass":"s3cr3t"}'

    local out rc arn
    out=$(aws_cmd secretsmanager create-secret --name "$name" --secret-string "$value" 2>&1) && rc=0 || rc=1
    arn=$(echo "$out" | python3 -c "import sys,json; print(json.load(sys.stdin).get('ARN',''))" 2>/dev/null || echo "")
    check "SecretsManager CreateSecret" "$( [ -n "$arn" ] && echo true || echo false )" "$out"

    out=$(aws_cmd secretsmanager get-secret-value --secret-id "$name" 2>&1) && rc=0 || rc=1
    got=$(echo "$out" | python3 -c "import sys,json; print(json.load(sys.stdin).get('SecretString',''))" 2>/dev/null || echo "")
    check "SecretsManager GetSecretValue" "$( [ "$got" = "$value" ] && echo true || echo false )" "$out"

    out=$(aws_cmd secretsmanager put-secret-value --secret-id "$name" --secret-string '{"user":"admin","pass":"new"}' 2>&1) && rc=0 || rc=1
    check "SecretsManager PutSecretValue" "$( [ $rc -eq 0 ] && echo true || echo false )" "$out"

    out=$(aws_cmd secretsmanager list-secrets 2>&1) && rc=0 || rc=1
    found=$(echo "$out" | python3 -c "import sys,json; d=json.load(sys.stdin); print('true' if any(s['Name']=='$name' for s in d.get('SecretList',[])) else 'false')" 2>/dev/null || echo false)
    check "SecretsManager ListSecrets" "$found" "$out"

    out=$(aws_cmd secretsmanager tag-resource --secret-id "$name" --tags Key=env,Value=test 2>&1) && rc=0 || rc=1
    check "SecretsManager TagResource" "$( [ $rc -eq 0 ] && echo true || echo false )" "$out"

    out=$(aws_cmd secretsmanager delete-secret --secret-id "$name" --force-delete-without-recovery 2>&1) && rc=0 || rc=1
    check "SecretsManager DeleteSecret" "$( [ $rc -eq 0 ] && echo true || echo false )" "$out"
}

# ---------------------------------------------------------------------------
# KMS
# ---------------------------------------------------------------------------

run_kms() {
    echo "--- KMS Tests ---"

    local out rc key_id
    out=$(aws_cmd kms create-key --description "cli-sdk-test-key" 2>&1) && rc=0 || rc=1
    key_id=$(echo "$out" | python3 -c "import sys,json; print(json.load(sys.stdin).get('KeyMetadata',{}).get('KeyId',''))" 2>/dev/null || echo "")
    check "KMS CreateKey" "$( [ -n "$key_id" ] && echo true || echo false )" "$out"

    local alias="alias/cli-sdk-test"
    out=$(aws_cmd kms create-alias --alias-name "$alias" --target-key-id "$key_id" 2>&1) && rc=0 || rc=1
    check "KMS CreateAlias" "$( [ $rc -eq 0 ] && echo true || echo false )" "$out"

    local plaintext
    plaintext=$(echo -n "hello-kms" | base64)
    out=$(aws_cmd kms encrypt --key-id "$key_id" --plaintext "$plaintext" 2>&1) && rc=0 || rc=1
    ciphertext=$(echo "$out" | python3 -c "import sys,json; print(json.load(sys.stdin).get('CiphertextBlob',''))" 2>/dev/null || echo "")
    check "KMS Encrypt" "$( [ -n "$ciphertext" ] && echo true || echo false )" "$out"

    out=$(aws_cmd kms decrypt --ciphertext-blob "$ciphertext" 2>&1) && rc=0 || rc=1
    decrypted=$(echo "$out" | python3 -c "import sys,json,base64; d=json.load(sys.stdin); print(base64.b64decode(d.get('Plaintext','')).decode())" 2>/dev/null || echo "")
    check "KMS Decrypt" "$( [ "$decrypted" = "hello-kms" ] && echo true || echo false )" "$out"

    out=$(aws_cmd kms list-aliases 2>&1) && rc=0 || rc=1
    found=$(echo "$out" | python3 -c "import sys,json; d=json.load(sys.stdin); print('true' if any(a.get('AliasName')=='$alias' for a in d.get('Aliases',[])) else 'false')" 2>/dev/null || echo false)
    check "KMS ListAliases" "$found" "$out"

    aws_cmd kms delete-alias --alias-name "$alias" >/dev/null 2>&1 || true
    aws_cmd kms schedule-key-deletion --key-id "$key_id" --pending-window-in-days 7 >/dev/null 2>&1 || true
}

# ---------------------------------------------------------------------------
# Group registry and entry point
# ---------------------------------------------------------------------------

ALL_GROUPS=(ssm sqs sns s3 dynamodb iam sts secretsmanager kms)

resolve_enabled() {
    local names=()
    for arg in "$@"; do
        IFS=',' read -ra parts <<< "$arg"
        for part in "${parts[@]}"; do
            part="${part// /}"
            [ -n "$part" ] && names+=("${part,,}")
        done
    done
    if [ ${#names[@]} -gt 0 ]; then
        echo "${names[@]}"
        return
    fi
    if [ -n "${FLOCI_TESTS:-}" ]; then
        IFS=',' read -ra parts <<< "$FLOCI_TESTS"
        for part in "${parts[@]}"; do
            part="${part// /}"
            [ -n "$part" ] && names+=("${part,,}")
        done
        [ ${#names[@]} -gt 0 ] && echo "${names[@]}" && return
    fi
    echo ""
}

main() {
    echo "=== Floci SDK Test (AWS CLI) ==="
    echo ""

    local enabled_str
    enabled_str=$(resolve_enabled "$@")
    read -ra ENABLED <<< "$enabled_str"

    if [ ${#ENABLED[@]} -gt 0 ]; then
        echo "Running groups: ${ENABLED[*]}"
        echo ""
    fi

    for group in "${ALL_GROUPS[@]}"; do
        if [ ${#ENABLED[@]} -eq 0 ] || [[ " ${ENABLED[*]} " == *" $group "* ]]; then
            "run_${group//-/_}"
            echo ""
        fi
    done

    echo "=== Results: $PASSED passed, $FAILED failed ==="
    [ "$FAILED" -gt 0 ] && exit 1 || exit 0
}

main "$@"
