#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

yml_merge() {
    run_script 'env_update'
    run_script 'appvars_create_all'
    info "Compiling arguments to merge docker-compose.yml file."
    local YML_ARGS
    YML_ARGS="${YML_ARGS:-} -y -s 'reduce .[] as \$item ({}; . * \$item) | del(.version)'"
    YML_ARGS="${YML_ARGS:-} \"${SCRIPTPATH}/compose/.reqs/r1.yml\""
    YML_ARGS="${YML_ARGS:-} \"${SCRIPTPATH}/compose/.reqs/r2.yml\""
    info "Required files included."
    notice "Adding compose configurations for enabled apps. Please be patient, this can take a while."
    while IFS= read -r line; do
        local APPNAME=${line%%_ENABLED=*}
        local FILENAME=${APPNAME,,}
        local APPTEMPLATES="${SCRIPTPATH}/compose/.apps/${FILENAME}"
        if [[ -d ${APPTEMPLATES}/ ]]; then
            if [[ -f ${APPTEMPLATES}/${FILENAME}.yml ]]; then
                local APPDEPRECATED
                APPDEPRECATED=$(grep --color=never -Po "\scom\.dockstarter\.appinfo\.deprecated: \K.*" "${APPTEMPLATES}/${FILENAME}.labels.yml" | sed -E 's/^([^"].*[^"])$/"\1"/' | xargs || echo false)
                if [[ ${APPDEPRECATED} == true ]]; then
                    warn "${APPNAME} IS DEPRECATED!"
                    warn "Please edit ${COMPOSE_ENV} and set ${APPNAME}_ENABLED to false."
                    continue
                fi
                if [[ ! -f ${APPTEMPLATES}/${FILENAME}.${ARCH}.yml ]]; then
                    error "${APPTEMPLATES}/${FILENAME}.${ARCH}.yml does not exist."
                    continue
                fi
                YML_ARGS="${YML_ARGS:-} \"${APPTEMPLATES}/${FILENAME}.${ARCH}.yml\""
                local APPNETMODE
                APPNETMODE=$(run_script 'env_get' "${APPNAME}_NETWORK_MODE")
                if [[ -z ${APPNETMODE} ]] || [[ ${APPNETMODE} == "bridge" ]]; then
                    if [[ -f ${APPTEMPLATES}/${FILENAME}.hostname.yml ]]; then
                        YML_ARGS="${YML_ARGS:-} \"${APPTEMPLATES}/${FILENAME}.hostname.yml\""
                    else
                        info "${APPTEMPLATES}/${FILENAME}.hostname.yml does not exist."
                    fi
                    if [[ -f ${APPTEMPLATES}/${FILENAME}.ports.yml ]]; then
                        YML_ARGS="${YML_ARGS:-} \"${APPTEMPLATES}/${FILENAME}.ports.yml\""
                    else
                        info "${APPTEMPLATES}/${FILENAME}.ports.yml does not exist."
                    fi
                elif [[ -n ${APPNETMODE} ]]; then
                    if [[ -f ${APPTEMPLATES}/${FILENAME}.netmode.yml ]]; then
                        YML_ARGS="${YML_ARGS:-} \"${APPTEMPLATES}/${FILENAME}.netmode.yml\""
                    else
                        info "${APPTEMPLATES}/${FILENAME}.netmode.yml does not exist."
                    fi
                fi
                YML_ARGS="${YML_ARGS:-} \"${APPTEMPLATES}/${FILENAME}.yml\""
                info "All configurations for ${APPNAME} are included."
            else
                warn "${APPTEMPLATES}/${FILENAME}.yml does not exist."
            fi
        else
            error "${APPTEMPLATES}/ does not exist."
        fi
    done < <(grep --color=never -P '_ENABLED='"'"'?true'"'"'?$' "${COMPOSE_ENV}")
    YML_ARGS="${YML_ARGS:-} > \"${SCRIPTPATH}/compose/docker-compose.yml\""
    info "Running compiled arguments to merge docker-compose.yml file."
    export YQ_OPTIONS="${YQ_OPTIONS:-} -v ${SCRIPTPATH}:${SCRIPTPATH}"
    run_script 'run_yq' "${YML_ARGS}"
    info "Merging docker-compose.yml complete."
}

test_yml_merge() {
    run_script 'appvars_create' WATCHTOWER
    cat "${COMPOSE_ENV}"
    run_script 'yml_merge'
    cd "${SCRIPTPATH}/compose/" || fatal "Failed to change directory.\nFailing command: ${F[C]}cd \"${SCRIPTPATH}/compose/\""
    run_script 'run_compose' "config"
    cd "${SCRIPTPATH}" || fatal "Failed to change directory.\nFailing command: ${F[C]}cd \"${SCRIPTPATH}\""
    run_script 'appvars_purge' WATCHTOWER
}
