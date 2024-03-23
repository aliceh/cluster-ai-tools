#!/usr/bin/env bash -xe

set -o pipefail
set -o errexitczach
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

#"#f14e32"
red(){
 text=$1
 gum style --foreground 1 "$text"
}

purple(){
  text=$1
  gum style --foreground 57 "$text"
}

#"#267683"
blue(){
  text=$1
  gum style --foreground 4 "$text"
}

green(){
  text=$1
  gum style --foreground 2 "$text"
}

beginningRepairMsg() {
  echo $(green "Beginning to repair") $(purple $1) $(green "on") $(blue $2)
}

# Alert handler functions
UpgradeNodeUpgradeTimeoutSRE() {
  local cluster
  read -r cluster

  ocm backplane login $cluster
  echo $(blue "Checking MUO")
  oc get upgrade -n openshift-managed-upgrade-operator
  
  echo $(blue "Checking nodes")
  oc get no -o wide | grep SchedulingDisabled
  sleep 3

  echo $(blue "Checking MCP")
  oc get mcp
  sleep 3

  #TODO: drain node, check pdb, Special case - Twistlock, Special case - rpm-ostreed timeout
}


PruningCronjobErrorSRE() {
  local cluster
  read -r cluster

  ocm backplane login $cluster
  oc get po -n openshift-sre-pruning 
  echo $(blue "Running the script for PruningCronjobErrorSRE alert")
  OUTPUT=$(ocm backplane managedjob create SREP/retry-failed-pruning-cronjob|tail -2)
  echo $(blue "Outputting the script's log")
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
  echo $(blue "Running osdctl cluster cpd --cluster-id $cluster --profile rhcontrol")
  osdctl cluster cpd --cluster-id $cluster --profile rhcontrol
  sleep 3
  echo "...."

}

KubeNodeUnschedulableSRE() {
  local cluster
  read -r cluster

  ocm backplane login $cluster
  ocm backplane context
  echo $(blue "Running the script for KubeNodeUnschedulableSRE alert")
  ~/ops-sop/v4/utils/kube-node-unscheduleable.sh

}

#console-ErrorBudgetBurn() {
ClusterMonitoringErrorBudgetBurnSRE() {
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
  #replace the SilentTest user --assignees="P8QS6CC"
  incidents="$(pd incident list --teams='Platform SRE'  --json 2>/dev/null | jq -rc '.[].id')"
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
  echo $(red "Found alerts" $alerts)

  if [[ -z "$alerts" ]]
  then
    return
  fi

  for x in "${ALERTS[@]}"
  do 
   
    # id=$(jq --arg alertToWatch "${x}" -r '.[] | select(.pd.title | contains($alertToWatch)) | .external_id' <<< $alerts)
    pd_id=$(jq --arg alertToWatch "${x}" -r '.[] | select(.pd.title | contains($alertToWatch)) | "{.external_id,: .pd.id}"' <<< $alerts)

    for y in pd_id
    do 
      cluster_id = $(jq .external_id)
      alert_id = $(jq alertid)
      
      #Replacing for the test duration 
      #id="0e835c13-cf99-4500-ab29-18012ab5550c"
      if [[ -n "$id" ]]
      #check if not repaired alert ID is not in array
      then
        for i in "${PROCESSED_ALERTS[@]}"
        if [ "$i" -nq "$alert_id" ]
          then
          # We realize this only works while copilot.sh is running, but this is a POC
          PROCESSED_ALERTS+=($alert_id)
          # Disable errexit to allow the loop to continue if the individual repair fails
          beginningRepairMsg "$x" "$cluster_id"
          # check if we tried to repair before
          set +o errexit
          $x <<< "$cluster_id"
          set -o errexit
        fi
      fi

      echo "Fixed alert id $(jq --arg externalid "${id}" -r .id[.external_id])"

    done
  done
  
}

### This is the start of the main process
gum style --border normal --margin "1" --padding "1 2" --border-foreground 57 "Hello and welcome to $(red 'Copilot')."

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
  echo $(red "ERROR: could not retrieve on-call information. Exiting.")
  exit 1
fi

echo -e "I can see that $(green "$on_call") is Primary on call."
echo -e "Are you $(green "$on_call") ?"

CHOICE=$(gum choose --item.foreground 250 "Yes" "No" "It's complicated")
[[ "$CHOICE" == "Yes" ]] && echo "I thought so." || echo "I'm sorry to hear that." 
[[ "$CHOICE" == "No" ]] && exit 0
[[ "$CHOICE" == "It's complicated" ]] && echo "It is what it is..."

echo -e "Which alert should I watch today?"
echo -e $(green "Hit") $(blue "SPACE" ) $(green "for all the alerts you wish to select.")

PCE="PruningCronjobErrorSRE"
KNU="KubeNodeUnschedulableSRE"
CER="ClusterMonitoringErrorBudgetBurnSRE" #"console-ErrorBudgetBurn"
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



# TODO:
# Priority - Have to prevent the script from running trying to fix the same alert twice at the same time - maybe a "lockfile" via PD note?
# Get the script to run the prunejobfix script, maybe we can copy it from /sop/v4/utils
# Nice to have: run something on KubeNodeUnschedulableSRE and console-ErrorBudgetBurn

# Trap SIGINT and SIGTERM to exit gracefully from the while loop if the user wants to exit
trap exit SIGINT SIGTERM

PROCESSED_ALERTS = ()

while true
do 
  alerts=$(getAlerts "$on_call" | jq -rc --slurp .)
  for alert in 
  processAlerts <<< "$alerts"
  gum spin --spinner dot --title "Waiting for alerts..." -- sleep 120
done

