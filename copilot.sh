#!/bin/bash
set -euo pipefail

gum style --border normal --margin "1" --padding "1 2" --border-foreground 57 "Hello and welcome to $(gum style --foreground 57 'Copilot')."

on_call=$(
  pd schedule oncall -n '0-SREP: Weekday Primary' --json | \
  jq -rc '.[0].user.summary' || \

  pd schedule oncall -n '0-SREP: Weekend Oncall 4x6' --json | \
  jq -rc '.[0].user.summary'
)

echo -e " I can see that $(gum style --foreground 57 "$on_call") is Primary on call."

echo -e  "Are you $(gum style --foreground 57 "$on_call") ?"

CHOICE=$(gum choose --item.foreground 250 "Yes" "No" "It's complicated")
[[ "$CHOICE" == "Yes" ]] && echo "I thought so." || echo "I'm sorry to hear that." 
[[ "$CHOICE" == "No" ]] && exit 0
[[ "$CHOICE" == "It's complicated" ]] && exit 0

echo -e "Which alert should I watch today?"

PCE="PruningCronjobErrorSRE"; KNU="KubeNodeUnschedulableSRE"; CER="console-ErrorBudgetBurn"
INCIDENTS=$(gum choose --no-limit "$PCE" "$KNU" "$CER")
echo "I'll keep that in mind!"



ALL_INCIDENTS=$(pd incident list --teams='Platform SRE' --assignees="$on_call" --json | jq -rc '.[]' | while read pd
do
  pd_id=$(echo "$pd" | jq -rc '.id')
  pd_title=$(echo "$pd" | jq -rc '.title')
  pd incident alerts -i "$pd_id" --json | \
  jq -rc '.[].body.details.cluster_id' | \
  sort | \
  uniq | \
  jq -Rrc --arg pd_id "$pd_id" --arg pd_title "$pd_title" '{external_id: ., pd: {id: $pd_id, title: $pd_title}}'
done
)

echo "$ALL_INCIDENTS"

for incident in "${INCIDENTS[@]}"
do
   echo $(gum style --foreground 57 "Checking for" $incident) 
   echo $ALL_INCIDENTS| jq -rc --arg incident "$incident" 'select(.pd.title | contains($incident))' | \
while read pd_data; do pd_id=$(echo "$pd_data" | jq -rc '.pd.id'); echo $(gum style --foreground 57 "Found incident" $pd_id "," $incident); cluster_id=$(echo "$pd_data" | \
 jq -rc '.external_id'); echo "External cluster ID: $cluster_id"; ocm backplane login "$cluster_id"; oc get po -n openshift-sre-pruning -o wide;  done 

done

#echo $ALL_INCIDENTS| jq -rc 'select(.pd.title | contains("PruningCronjobErrorSRE"))' | \
#while read pd_data; do pd_id=$(echo "$pd_data" | jq -rc '.pd.id'); echo $pd_id; cluster_id=$(echo "$pd_data" | \
# jq -rc '.external_id'); echo "External cluster ID: $cluster_id"; ocm backplane session "$cluster_id"; oc get po -n openshift-sre-pruning -o wide;  done 

#echo $ALL_INCIDENTS| jq -rc 'select(.pd.title | contains("KubeNodeUnschedulableSRE"))' | while read pd_data; do pd_id=$(echo "$pd_data" | jq -rc '.pd.id'); echo $pd_id; cluster_id=$(echo "$pd_data" | jq -rc '.external_id'); echo "External cluster ID: $cluster_id"; ocm backplane session "$cluster_id"; oc logs -n openshift-machine-api deploy/machine-api-controllers -c machine-controller ;  done 