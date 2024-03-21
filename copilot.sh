#!/usr/bin/env bash

set -o pipefail
set -o errexit
set -o nounset

# This script requires https://github.com/charmbracelet/gum
command -v gum >/dev/null 2>&1 \
  || { echo >&2 "This script requires https://github.com/charmbracelet/gum, but it's not installed.  Aborting."; exit 1; }

# This script requires https://github.com/martindstone/pagerduty-cli
command -v pd >/dev/null 2>&1 \
  || { echo >&2 "This script requires https://github.com/martindstone/pagerduty-cli, but it's not installed.  Aborting."; exit 1; }

# Other tools are likely to be installed
# * oc
# * ocm
# * jq

beginningRepairMsg() {
  echo "Beginning to repair $1 on $2"
}

# Alert handler functions
UpgradeNodeUpgradeTimeoutSRE() {
  local cluster
  read -r cluster

  ocm backplane login $cluster
  oc get upgrade -n openshift-managed-upgrade-operator
}

PruningCronjobErrorSRE() {
  local cluster
  read -r cluster

  ocm backplane login $cluster
  oc get po -n openshift-sre-pruning 
  OUTPUT=$(ocm backplane managedjob create SREP/retry-failed-pruning-cronjob|tail -1)
  echo $OUTPUT
  job=$(awk '{print $NF}' <<< $OUTPUT)
  sleep 3
  ocm backplane managedjob logs $job
  oc get po -n openshift-sre-pruning 
}

ClusterProvisioningDelay() {
  local cluster
  read -r cluster

  osdctl cluster context $cluster
  ocm backplane login $cluster
  cat ~/.config/osdctl
  osdctl cluster cpd --cluster-id $cluster --profile rhcontrol

}

  KubeNodeUnschedulableSRE() {
  local cluster
  read -r cluster

  ocm backplane login $cluster
  ocm backplane context
  oc get no -o wide
  echo "Running the script for KubeNodeUnschedulableSRE alert"
  ~/ops-sop/v4/utils/kube-node-unscheduleable.sh
}

console-ErrorBudgetBurn() {
  local cluster
  read -r cluster

  ocm backplane login $cluster
  oc get co

}

api-ErrorBudgetBurn() {
  local cluster
  read -r cluster

  ocm backplane login $cluster
  oc get co
}

# getAlerts retrieves a list of incidents assigned to the $on_call engineer and returns JSON lists of the alerts for the incident
getAlerts() {
  # Retrieve incidents and return their alerts in the format:
  #
  # {
  #    "external_id":"cluster_UID",
  #    "pd":{
  #      "id":"pd_alert_id",
  #      "title": "pd_alert_title"
  #    }
  #  }
  local on_call="${*}"
  local incidents
  incidents="$(pd incident list --teams='Platform SRE' --assignees="$on_call" --json 2>/dev/null | jq -rc '.[].id')"

  # These are useful for testing local data
  # incidents="$(pd incident list --me --json 2>/dev/null | jq -rc '.[].id')"
  # incidents="$(cat /tmp/incidents.json | jq -rc '.[].id')"

  for incident in $incidents
  do 
    # Select the !ALERT! id for use here; since an incident can have multiple alerts
    # and we fix alerts, not incidents
    pd incident alerts -i "${incident}" --json 2>/dev/null| \
      jq -cj '.[] | "{\"external_id\": \"\(.body.details.cluster_id)\", \"pd\": {\"id\": \"\(.id)\", \"title\": \"\(.summary)\"}}"'
  done
}

# processAlerts accepts output from getAlerts as stdin and checks the alert to see if it is one of the "watched" alerts
# If so, it executes the function with that alert name, passing the cluster id as stdin
processAlerts() {
  local alerts
  read -r alerts

  if [[ -z "$alerts" ]]
  then
    return
  fi

  for x in "${ALERTS[@]}"
  do 
    id=$(jq --arg alertToWatch "${x}" -r '.[] | select(.pd.title | contains($alertToWatch)) | .external_id' <<< $alerts)
    if [[ -n "$id" ]]
    then
      # Disable errexit to allow the loop to continue if the individual repair fails
      beginningRepairMsg "$x" "$id"
      set +o errexit
      $x <<< "$id"
      set -o errexit
    fi
  done
  
}

### This is the start of the main process
gum style --border normal --margin "1" --padding "1 2" --border-foreground 57 "Hello and welcome to $(gum style --foreground 57 'Copilot')."

on_call=$(
  pd schedule oncall -n '0-SREP: Weekday Primary' --json 2>/dev/null | \
  jq -rc '.[0].user.summary' || \

  pd schedule oncall -n '0-SREP: Weekend Oncall 4x6' --json 2>/dev/null | \
  jq -rc '.[0].user.summary'
)

# If we can't find the on-call person, we should exit
# This would be covered by set -x errexit & nounset, but it's nice to be explicit
if [[ -z "$on_call" ]]
then
  echo "ERROR: could not retrieve on-call information. Exiting."
  exit 1
fi

echo -e "I can see that $(gum style --foreground 57 "$on_call") is Primary on call."
echo -e "Are you $(gum style --foreground 57 "$on_call") ?"

CHOICE=$(gum choose --item.foreground 250 "Yes" "No" "It's complicated")
[[ "$CHOICE" == "Yes" ]] && echo "I thought so." || echo "I'm sorry to hear that." 
[[ "$CHOICE" == "No" ]] && exit 0
[[ "$CHOICE" == "It's complicated" ]] && exit 0

echo -e "Which alert should I watch today?"

PCE="PruningCronjobErrorSRE"
KNU="KubeNodeUnschedulableSRE"
CER="console-ErrorBudgetBurn"
AER="api-ErrorBudgetBurn"
UPG="UpgradeNodeUpgradeTimeoutSRE"
CPD="ClusterProvisioningDelay"

mapfile -t ALERTS < <(gum choose --no-limit "$PCE" "$KNU" "$CER" "$UPG" "$AER" "$CPD")


echo "Selected options:"
for alert in "${ALERTS[@]}"; do
    echo "$alert"
done

# Check if ALERTS is populated
if [[ ${#ALERTS[@]} -gt 0 ]]; then
    echo "Watching ${ALERTS[@]}... I'll keep that in mind!"
else
    echo "No alerts selected."
fi

echo "I'll keep that in mind!"

# TODO:
# Priority - Have to prevent the script from running trying to fix the same alert twice at the same time - maybe a "lockfile" via PD note?
# Get the script to run the prunejobfix script, maybe we can copy it from /sop/v4/utils
# Nice to have: run something on KubeNodeUnschedulableSRE and console-ErrorBudgetBurn

# Trap SIGINT and SIGTERM to exit gracefully from the while loop if the user wants to exit
trap exit SIGINT SIGTERM

while true
do 
  alerts=$(getAlerts "$on_call" | jq -rc --slurp .)
  processAlerts <<< "$alerts"
  gum spin --spinner dot --title "Waiting for alerts..." -- sleep 30
done

