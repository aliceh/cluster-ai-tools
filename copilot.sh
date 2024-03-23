#!/usr/bin/env bash

set -o pipefail
set -o errexit
set -o nounset

source lib/styles
source lib/alertHandlers
source lib/pagerDuty

# checkEnvironment tests for the presence of required tools
checkEnvironment() {
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
}

# checkOnCall prompts the user to confirm that the on-call engineer is the person running the script
checkOnCall() {
  local on_call="${1}"

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
}


main() {
  local dryRun="FALSE"

  OPTS="i:d"

  while getopts $OPTS opt; do
    case ${opt} in
      d )
        dryRun="TRUE"
        echo "### Dry Run ###"
        ;;
      i )
        incidentFile="${OPTARG}"
        echo "Using incident file $incidentFile"
        ;; 
      \?)
        echo "Usage: copilot.sh [-d]"
        exit 1
        ;;
    esac
  done

  checkEnvironment

  gum style --border normal --margin "1" --padding "1 2" --border-foreground 57 "Hello and welcome to $(red 'Copilot')."

  # Get On-Call Engineer
  if [[ "${dryRun}_x" == "FALSE_x" ]] 
  then
    # (lib/pagerDuty/pagerDutyOnCall)
    on_call=$(pagerDutyOnCall)
    checkOnCall $on_call
  fi

  # Prompt for which alerts to watch (lib/alertHandlers/alertsToWatch)
  echo -e "Which alert should I watch today?"
  echo -e $(green "Hit") $(blue "SPACE" ) $(green "for all the alerts you wish to select.")
  declare -a ALERTS
  readarray -t ALERTS < <(alertsToWatch $dryRun)

  if [[ ${#ALERTS[@]} -gt 0 ]]; then
      echo "Watching ${ALERTS[*]}... I'll keep that in mind!"
  else
      echo "No alerts selected."
      exit 1
  fi

  # PROCESSED_ALERT_IDS keeps track of which alerts have been acted on
  # This is just for the POC; in a real life situation, we need something more durable
  declare -a PROCESSED_ALERT_IDS

  # Trap SIGINT and SIGTERM to exit gracefully from the while loop if the user wants to exit
  trap exit SIGINT SIGTERM

  while true
  do 
    declare -a incidents
    if [[ "${dryRun}_x" == "FALSE_x" ]]
    then
      # Parse the raw PagerDuty JSON array to a bash array
      readarray -t incidents < <(pagerDutyGetIncidents "${on_call}" | jq -c '.[]')
    else
      readarray -t incidents < <(jq -c '.[]' "${incidentFile}")
    fi

    declare -a alerts_to_remediate
    for incident in "${incidents[@]}"
    do
      local incident_id
      incident_id=$(jq -r .id <<< "$incident")

      declare -a raw_alerts
      readarray -t raw_alerts < <(pagerDutyGetAlertsFromIncident "$incident_id" | jq -c '.[]')

      for raw_alert in "${raw_alerts[@]}"
      do
        declare -a alert_summaries
        readarray -t alert_summaries < <(summarizeAlertDetailsFromAlert "$raw_alert")
        alerts_to_remediate+=("${alert_summaries[@]}")
      done
    done

    for alert in "${alerts_to_remediate[@]}"
    do
      pd_id=$(jq -r .pd.id <<< "$alert")
      for processed_alert in "${PROCESSED_ALERT_IDS[@]}"
      do
        if [[ "${pd_id}" == "${processed_alert}" ]]
        then
          # The alert has already been processed; break
          break
        fi
      done

      # Else handle the alert
      PROCESSED_ALERT_IDS+=("$pd_id")
      processAlert "$alert" "$dryRun"
    done

    gum spin --spinner dot --title "Waiting for alerts..." -- sleep 120
  done

}

main "$@"