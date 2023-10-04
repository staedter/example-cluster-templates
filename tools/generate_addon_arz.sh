#!/bin/bash
set -e
set -o pipefail

# Add user to k8s using service account, no RBAC (must create RBAC after this script)
if [[ -z "$1" ]] || [[ -z "$2" ]]; then
  echo "description: The script is used to add a serviceAccount in the Harvester cluster for the Harvester cloud provider and generate the RKE addon configuration. It depends on kubectl."
  echo "usage: $0 <service_account_name> <namespace>"
  exit 1
fi

SERVICE_ACCOUNT_NAME=$1
ROLE_BINDING_NAME=$1
NAMESPACE="$2"
CLUSTER_ROLE_NAME="harvesterhci.io:cloudprovider"
KUBECFG_FILE_NAME="./tmp/kube/k8s-${SERVICE_ACCOUNT_NAME}-${NAMESPACE}-conf"
CLOUD_CONFIG_TEMPLATE="userdata-example-cluster-template"
CLOUD_CONFIG_NAMESPACE="devops"
TARGET_FOLDER="./tmp/kube"
USERDATA_FOLDER="./userdata/${NAMESPACE}"
#USERDATA_FILE="${USERDATE_FOLDER}/${CLOUD_CONFIG_TEMPLATE}-b64.txt"

create_userdata_folder() {
  echo -n "Creating target directory to hold files in ${USERDATA_FOLDER}..."
  mkdir -p "${USERDATA_FOLDER}"
  printf "done"
}

create_target_folder() {
  echo -n "Creating target directory to hold files in ${TARGET_FOLDER}..."
  mkdir -p "${TARGET_FOLDER}"
  printf "done"
}

create_service_account() {
  echo -e "\\nCreating a service account in ${NAMESPACE} namespace: ${SERVICE_ACCOUNT_NAME}"
  # use kubectl apply to ignore AlreadyExists error
  kubectl create sa "${SERVICE_ACCOUNT_NAME}" --namespace "${NAMESPACE}" --dry-run -o yaml | kubectl apply -f -
}

create_clusterrolebinding() {
  echo -e "\\nCreating a clusterrolebinding ${ROLE_BINDING_NAME}-${NAMESPACE}"
  kubectl create clusterrolebinding "${ROLE_BINDING_NAME}-${NAMESPACE}" --serviceaccount=${NAMESPACE}:${SERVICE_ACCOUNT_NAME} --clusterrole=${CLUSTER_ROLE_NAME} --dry-run -o yaml | kubectl apply -f -
}

get_secret_name_from_service_account() {
  read -r SERVER_MAJOR_VERSION SERVER_MINOR_VERSION < <(kubectl version -ojson | jq -r '[.serverVersion | .major, .minor] | join(" ")')
  if [ "${SERVER_MAJOR_VERSION}" -ge 1 ] && [ "${SERVER_MINOR_VERSION}" -ge 24 ]; then
    SECRET_NAME="${SERVICE_ACCOUNT_NAME}-token"
    echo -e "\\nGetting uid of service account ${SERVICE_ACCOUNT_NAME} on ${NAMESPACE}"
    SERVICE_ACCOUNT_UID=$(kubectl get sa "${SERVICE_ACCOUNT_NAME}" --namespace "${NAMESPACE}" -o jsonpath="{.metadata.uid}")
    echo "Service Account uid: ${SERVICE_ACCOUNT_UID}"
    echo -e "\\nCreating a user token secret in ${NAMESPACE} namespace: ${SECRET_NAME}"
    cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Secret
metadata:
  annotations:
    kubernetes.io/service-account.name: ${SERVICE_ACCOUNT_NAME}
    kubernetes.io/service-account.uid: ${SERVICE_ACCOUNT_UID}
  name: ${SECRET_NAME}
  namespace: ${NAMESPACE}
  ownerReferences:
  - apiVersion: v1
    kind: ServiceAccount
    name: ${SERVICE_ACCOUNT_NAME}
    uid: ${SERVICE_ACCOUNT_UID}
type: kubernetes.io/service-account-token
EOF
  else
    while [ -z "${SECRET_NAME}" ]; do
    echo -e "\\nGetting secret of service account ${SERVICE_ACCOUNT_NAME} on ${NAMESPACE}"
    SECRET_NAME=$(kubectl get sa "${SERVICE_ACCOUNT_NAME}" --namespace="${NAMESPACE}" -o jsonpath="{.secrets[].name}")
    done
  fi
  echo "Secret name: ${SECRET_NAME}"
}

extract_ca_crt_from_secret() {
  # while [ -z "${CA_CRT}" ]; do
  #   echo -e -n "\\nExtracting ca.crt from secret..."
  #   CA_CRT=$(kubectl get secret --namespace "${NAMESPACE}" "${SECRET_NAME}" -o jsonpath="{.data.ca\.crt}")
  # done
  CA_CRT="LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0tDQpNSUlGRmpDQ0F2NmdBd0lCQWdJUkFKRXJDRXJQREJpblUvYldMaVduWDFvd0RRWUpLb1pJaHZjTkFRRUxCUUF3DQpUekVMTUFrR0ExVUVCaE1DVl
ZNeEtUQW5CZ05WQkFvVElFbHVkR1Z5Ym1WMElGTmxZM1Z5YVhSNUlGSmxjMlZoDQpjbU5vSUVkeWIzVndNUlV3RXdZRFZRUURFd3hKVTFKSElGSnZiM1FnV0RFd0hoY05NakF3T1RBME1EQXdNREF3DQpXaGNOTWpVd09URTFNVFl3TURBd1dq
QXlNUXN3Q1FZRFZRUUdFd0pWVXpFV01CUUdBMVVFQ2hNTlRHVjBKM01nDQpSVzVqY25sd2RERUxNQWtHQTFVRUF4TUNVak13Z2dFaU1BMEdDU3FHU0liM0RRRUJBUVVBQTRJQkR3QXdnZ0VLDQpBb0lCQVFDN0FoVW96UGFnbE5NUEV1eU5WWk
xEK0lMeG1hWjZRb2luWFNhcXRTdTV4VXl4cjQ1citYWElvOWNQDQpSNVFVVlRWWGpKNm9vamtaOVlJOFFxbE9idlU3d3k3YmpjQ3dYUE5aT09mdHoybndXZ3NidnNDVUpDV0gramR4DQpzeFBuSEt6aG0rL2I1RHRGVWtXV3FjRlR6alRJVXU2
MXJ1MlAzbUJ3NHFWVXE3WnREcGVsUURScks5TzhadXRtDQpOSHo2YTR1UFZ5bVorREFYWGJweWIvdUJ4YTNTaGxnOUY4Zm5DYnZ4Sy9lRzNNSGFjVjNVUnVQTXJTWEJpTHhnDQpaM1Ztcy9FWTk2SmM1bFAvT29pMlI2WC9FeGpxbUFsM1A1MV
QrYzhCNWZXbWNCY1VyMk9rLzVtems1M2NVNmNHDQova2lGSGFGcHJpVjF1eFBNVWdQMTdWR2hpOXNWQWdNQkFBR2pnZ0VJTUlJQkJEQU9CZ05WSFE4QkFmOEVCQU1DDQpBWVl3SFFZRFZSMGxCQll3RkFZSUt3WUJCUVVIQXdJR0NDc0dBUVVG
QndNQk1CSUdBMVVkRXdFQi93UUlNQVlCDQpBZjhDQVFBd0hRWURWUjBPQkJZRUZCUXVzeGUzV0ZiTHJsQUpRT1lmcjUyTEZNTEdNQjhHQTFVZEl3UVlNQmFBDQpGSG0wV2VaN3R1WGtBWE9BQ0lqSUdsajI2WnR1TURJR0NDc0dBUVVGQndFQk
JDWXdKREFpQmdnckJnRUZCUWN3DQpBb1lXYUhSMGNEb3ZMM2d4TG1rdWJHVnVZM0l1YjNKbkx6QW5CZ05WSFI4RUlEQWVNQnlnR3FBWWhoWm9kSFJ3DQpPaTh2ZURFdVl5NXNaVzVqY2k1dmNtY3ZNQ0lHQTFVZElBUWJNQmt3Q0FZR1o0RU1B
UUlCTUEwR0N5c0dBUVFCDQpndDhUQVFFQk1BMEdDU3FHU0liM0RRRUJDd1VBQTRJQ0FRQ0Z5azVIUHFQM2hVU0Z2TlZuZUxLWVk2MTFUUjZXDQpQVE5sY2xRdGdhRHF3KzM0SUw5ZnpMZHdBTGR1Ty9aZWxON2tJSittNzR1eUErZWl0Ulk4a2M2MDdUa0M1M3dsDQppa2ZtWlc0L1J2VFo4TTZVSys1VXpoSzhqQ2RMdU1HWUw2S3Z6WEdSU2dpM3lMZ2pld1F0Q1BrSVZ6NkQyUVF6DQpDa2NoZUFtQ0o4TXF5SnU1emx6eVpNakF2bm5BVDQ1dFJBeGVrcnN1OTRzUTRlZ2RSQ25iV1NEdFk3a2grQkltDQpsSk5Yb0IxbEJNRUtJcTRRRFVPWG9SZ2ZmdURnaGplMVdyRzlNTCtIYmlzcS95Rk9Hd1hEOVJpWDhGNnN3Nlc0DQphdkF1dkRzenVlNUwzc3o4NUsrRUM0WS93RlZETnZabzRUWVhhbzZaMGYrbFFLYzB0OERRWXprMU9YVnU4cnAyDQp5Sk1DNmFsTGJCZk9EQUxadllIN243ZG8xQVpsczRJOWQxUDRqbmtEclFveEIzVXFROWhWbDNMRUtRNzN4RjFPDQp5SzVHaEREWDhvVmZHS0Y1dStkZWNJc0g0WWFUdzdtUDNHRnhKU3F2MyswbFVGSm9pNUxjNWRhMTQ5cDkwSWRzDQpoQ0V4cm9MMSs3bXJ5SWtYUGVGTTVUZ085cjBydlphQkZPdlYyejBncDM1WjArTDRXUGxidUVqTi9seFBGaW4rDQpIbFVqcjhnUnNJM3FmSk9RRnkvOXJLSUpSMFkvOE9td3QvOG9UV2d5MW1kZUhtbWprN2oxbllzdkM5SlNRNlp2DQpNbGRsVFRLQjN6aFRoVjErWFdZcDZyamQ1SlcxemJWV0VrTE54RTdHSlRoRVVHM3N6Z0JWR1A3cFNXVFVUc3FYDQpuTFJid0hPb3E3aEh3Zz09DQotLS0tLUVORCBDRVJUSUZJQ0FURS0tLS0t"
  echo "${CA_CRT}" | base64 -d >"${TARGET_FOLDER}/ca.crt"
  printf "done"
}

get_user_token_from_secret() {
  while [ -z "${USER_TOKEN}" ]; do
    echo -e -n "\\nGetting user token from secret..."
    USER_TOKEN=$(kubectl get secret --namespace "${NAMESPACE}" "${SECRET_NAME}" -o jsonpath="{.data.token}" | base64 -d)
  done
  printf "done"
}

set_kube_config_values() {
  context=$(kubectl config current-context)
  echo -e "\\nSetting current context to: $context"

  CLUSTER_NAME=$(kubectl config get-contexts "$context" | awk '{print $3}' | tail -n 1)
  echo "Cluster name: ${CLUSTER_NAME}"

  ENDPOINT=$(kubectl config view \
    -o jsonpath="{.clusters[?(@.name == \"${CLUSTER_NAME}\")].cluster.server}")
  echo "Endpoint: ${ENDPOINT}"

  # Set up the config
  echo -e "\\nPreparing k8s-${SERVICE_ACCOUNT_NAME}-${NAMESPACE}-conf"
  echo -n "Setting a cluster entry in kubeconfig..."
  kubectl config set-cluster "${CLUSTER_NAME}" \
    --kubeconfig="${KUBECFG_FILE_NAME}" \
    --server="${ENDPOINT}" \
    --certificate-authority="${TARGET_FOLDER}/ca.crt" \
    --embed-certs=true

  echo -n "Setting token credentials entry in kubeconfig..."
  kubectl config set-credentials \
    "${SERVICE_ACCOUNT_NAME}-${NAMESPACE}-${CLUSTER_NAME}" \
    --kubeconfig="${KUBECFG_FILE_NAME}" \
    --token="${USER_TOKEN}"

  echo -n "Setting a context entry in kubeconfig..."
  kubectl config set-context \
    "${SERVICE_ACCOUNT_NAME}-${NAMESPACE}-${CLUSTER_NAME}" \
    --kubeconfig="${KUBECFG_FILE_NAME}" \
    --cluster="${CLUSTER_NAME}" \
    --user="${SERVICE_ACCOUNT_NAME}-${NAMESPACE}-${CLUSTER_NAME}" \
    --namespace="${NAMESPACE}"

  echo -n "Setting the current-context in the kubeconfig file..."
  kubectl config use-context "${SERVICE_ACCOUNT_NAME}-${NAMESPACE}-${CLUSTER_NAME}" \
    --kubeconfig="${KUBECFG_FILE_NAME}"
}

create_target_folder
create_userdata_folder
create_service_account
create_clusterrolebinding
get_secret_name_from_service_account
extract_ca_crt_from_secret
get_user_token_from_secret
set_kube_config_values
echo "########## cloud config ############"
cat ${KUBECFG_FILE_NAME}
echo
echo "########## cloud-init user data ############"
if [[ $OSTYPE == 'darwin'* ]]; then
  KUBECONFIG_B64=$(base64 -b 0 < "${KUBECFG_FILE_NAME}")
else
  KUBECONFIG_B64=$(base64 -w 0 < "${KUBECFG_FILE_NAME}")
fi
kubectl get cm ${CLOUD_CONFIG_TEMPLATE} -n ${CLOUD_CONFIG_NAMESPACE} -o jsonpath='{.data.cloudInit}'
cat <<EOF
write_files:
- encoding: b64
  content: ${KUBECONFIG_B64}
  owner: root:root
  path: /etc/kubernetes/cloud-config
  permissions: '0644'
EOF


echo "########## cloud-init user data base64 ############"
CLOUD_CONFIG_TEMPLATE_DATA=$(kubectl get cm ${CLOUD_CONFIG_TEMPLATE} -n ${CLOUD_CONFIG_NAMESPACE} -o jsonpath='{.data.cloudInit}')
CLOUD_CONFIG_SCRIPT_DATA=$(cat <<EOF
write_files:
- encoding: b64
  content: ${KUBECONFIG_B64}
  owner: root:root
  path: /etc/kubernetes/cloud-config
  permissions: '0644'
EOF
)
CLOUD_CONFIG_USERDATA="${CLOUD_CONFIG_TEMPLATE_DATA}\n###Harvester cloud provider config for namespace ${NAMESPACE}###\n${CLOUD_CONFIG_SCRIPT_DATA}"
CLOUD_CONFIG_USERDATA_BASE64=$(echo -e "${CLOUD_CONFIG_USERDATA}" | base64 -w 0)
echo "${CLOUD_CONFIG_USERDATA_BASE64}" 
echo "${CLOUD_CONFIG_USERDATA_BASE64}" > "${USERDATA_FOLDER}/${CLOUD_CONFIG_TEMPLATE}.b64"

rm -r ${TARGET_FOLDER}
