#!/bin/bash
#set -x

################################################################################
#                      S C R I P T    D E F I N I T I O N
################################################################################
#

#-------------------------------------------------------------------------------
# Revision History
#-------------------------------------------------------------------------------
# 20150630     Jason W. Plummer          Original: A script to register, query,
#                                        deregister services and/or service 
#                                        checks with consul
# 20150715     Jason W. Plummer          Shifted to subroutine architecture

################################################################################
# DESCRIPTION
################################################################################
#

# NAME: consul-client
# 
# This script performs queries against the consul service api
#
# OPTIONS:
#
#     query                 - Perform a query against a consul URL.  Valid 
#                             query arguments are:
#         --type                - Set the query type.  Valid arguments are:
#             datacenter            - list registered datacenters
#             services              - list registered services
#             nodes                 - list registered nodes
#         --datacenter      - Query a datacenter.  Takes the name of the 
#                             datacenter as the argument.
#         --service         - Query a service.  Takes the name of the service
#                             as the argument.
#         --node            - Query a node.  Takes the name of the node as
#                             the argument.
#     register              - Register service/check against a consul URL.
#                             Valid register arguments are:
#         --datacenter          - the name of the datacenter to register
#         --node                - the name of the node to register
#         --node_address        - the IP address of the node to register
#         --service_id          - the unique ID of the service to register
#         --service_name        - a single string moniker for the service
#                                 to register
#         --tags                - key words associated with the service to
#                                 register
#         --service_address     - the IP address to associate with the 
#                                 service to register
#         --service_port        - port associated with the service_address
#         --check_node          - the name of the node to check
#         --check_id            - a JSON kv pair, formed by
#                                 "CheckID": "service:<service_id>"
#         --check_name          - a terse description of the check
#         --check_notes         - a verbose description of the check
#         --check_status        - keyword used to detect successful check
#         --check_serviceid     - a JSON kv pair, formed by 
#                                 "ServiceID": "<service_id>"
#     deregister            - Deregister service/check against a consul URL.
#                             Valid deregister arguments are:
#         --datacenter          - the name of the datacenter to deregister
#         --node                - the name of the node to deregister
#         --service_id          - the unique ID of the service to deregister

################################################################################
# CONSTANTS
################################################################################
#

PATH=/bin:/usr/bin:/usr/local/bin:/sbin:/usr/sbin:/usr/local/sbin
TERM=vt100
export TERM PATH

SUCCESS=0
ERROR=1

STDOUT_OFFSET="    "

SCRIPT_NAME="${0}"

USAGE_ENDLINE="\n${STDOUT_OFFSET}${STDOUT_OFFSET}${STDOUT_OFFSET}${STDOUT_OFFSET}"
USAGE="${SCRIPT_NAME}${USAGE_ENDLINE}"
USAGE="${USAGE}[ < query | register | deregister >   <sets operational mode *REQUIRED*> ${USAGE_ENDLINE}"
USAGE="${USAGE}      query                           <perform query> ${USAGE_ENDLINE}"
USAGE="${USAGE}          --type datacenter           <list registered datacenters> ${USAGE_ENDLINE}"
USAGE="${USAGE}          --type services             <list registered services> ${USAGE_ENDLINE}"
USAGE="${USAGE}          --type nodes                <list registered nodes> ${USAGE_ENDLINE}"
USAGE="${USAGE}          --datacenter < datacenter > <query datacenter resource named *datacenter* > ${USAGE_ENDLINE}"
USAGE="${USAGE}          --service < service >       <query service resource whose name is *service* > ${USAGE_ENDLINE}"
USAGE="${USAGE}          --node < node >             <query node resource whose hostname is *node* > ]${USAGE_ENDLINE}"
USAGE="${USAGE}      register                        <perform service/check registration against a consul URL> ${USAGE_ENDLINE}"
USAGE="${USAGE}          --datacenter                <the name of the datacenter to register> ${USAGE_ENDLINE}"
USAGE="${USAGE}          --node                      <the name of the node to register> ${USAGE_ENDLINE}"
USAGE="${USAGE}          --node_address              <the IP address of the node to register> ${USAGE_ENDLINE}"
USAGE="${USAGE}          --service_id                <the unique ID of the service to register> ${USAGE_ENDLINE}"
USAGE="${USAGE}          --service_name              <a single string moniker for the service to register> ${USAGE_ENDLINE}"
USAGE="${USAGE}          --tags                      <key words associated with the service to register> ${USAGE_ENDLINE}"
USAGE="${USAGE}          --service_address           <the IP address to associate with the service to register> ${USAGE_ENDLINE}"
USAGE="${USAGE}          --service_port              <port associated with the service_address> ${USAGE_ENDLINE}"
USAGE="${USAGE}          --check_node                <the name of the node to check> ${USAGE_ENDLINE}"
USAGE="${USAGE}          --check_id                  <a JSON kv pair, formed by \"CheckID\": \"service:<service_id>\" ${USAGE_ENDLINE}"
USAGE="${USAGE}          --check_name                <a terse description of the check> ${USAGE_ENDLINE}"
USAGE="${USAGE}          --check_notes               <a verbose description of the check> ${USAGE_ENDLINE}"
USAGE="${USAGE}          --check_status              <keyword used to detect successful check> ${USAGE_ENDLINE}"
USAGE="${USAGE}          --check_serviceid           <a JSON kv pair, formed by \"ServiceID\": \"<service_id>\""
USAGE="${USAGE}      deregister                      <perform service/check deregistration against a consul URL> ${USAGE_ENDLINE}"
USAGE="${USAGE}          --datacenter                <the name of the datacenter to deregister> ${USAGE_ENDLINE}"
USAGE="${USAGE}          --node                      <the name of the node to deregister> ${USAGE_ENDLINE}"
USAGE="${USAGE}          --service_id                <the unique ID of the service to deregister>"

################################################################################
# VARIABLES
################################################################################
#

err_msg=""
exit_code=${SUCCESS}
return_code=${SUCCESS}

################################################################################
# SUBROUTINES
################################################################################
#

# WHAT: Subroutine f__check_command
# WHY:  This subroutine checks the contents of lexically scoped ${1} and then
#       searches ${PATH} for the command.  If found, a variable of the form
#       my_${1} is created.
# NOTE: Lexically scoped ${1} should not be null, otherwise the command for
#       which we are searching is not present via the defined ${PATH} and we
#       should complain
#
f__check_command() {
    return_code=${SUCCESS}
    my_command="${1}"

    if [ "${my_command}" != "" ]; then
        my_command_check=`unalias "${i}" 2> /dev/null ; which "${1}" 2> /dev/null`

        if [ "${my_command_check}" = "" ]; then
            return_code=${ERROR}
        else
            eval my_${my_command}="${my_command_check}"
        fi

    else
        echo "${STDOUT_OFFSET}ERROR:  No command was specified"
        return_code=${ERROR}
    fi

    return ${return_code}
}

#-------------------------------------------------------------------------------

# WHAT: Subroutine f__query
# WHY:  This subroutine sets up the variables needed to query a service
#       and/or check in consul
#
f__query() {
    return_code=${SUCCESS}
    these_inputs="${*}"
    key="query"

    if [ "${these_inputs}" = "" ]; then
        err_msg="No ${key} arguments were provided"
        return_code=${ERROR}
        return ${return_code}
    fi

    while [ "${*}" != "" ] ; do
        value=`echo "${1}" | ${my_sed} -e 's?\`??g'`
        let type_check=`echo "${value}" | ${my_egrep} -c "^\-\-"`

        if [ ${type_check} -gt 0 ]; then
            ktype=`echo "${value}" | ${my_sed} -e 's?^--??g'`
            value=`echo "${2}" | ${my_sed} -e 's?\`??g'`

            case "${ktype}" in

                type)

                    if [ "${value}" != "" ]; then

                        case "${value}" in 

                            datacenter|services|nodes)
                                eval ${key}_${ktype}="${value}"
                                shift
                                shift
                            ;;

                            *)
                                err_msg="Invalid sub ${key} type: \"${value}\""
                                return_code=${ERROR}
                                break
                            ;;

                        esac

                    else
                        err_msg="${key} type \"--${ktype}\" requires an argument"
                        return_code=${ERROR}
                        break
                    fi

                ;;

                datacenter|service|node)

                    if [ "${value}" != "" ]; then
                        eval ${key}_${ktype}="${value}"
                        shift
                        shift
                    else
                        err_msg="${key} type \"--${ktype}\" requires an argument"
                        return_code=${ERROR}
                        break
                    fi

                ;;

                *)
                    err_msg="Invalid ${key} type: \"--${ktype}\""
                    return_code=${ERROR}
                    break
                ;;

            esac

        else

            if [ "${value}" = "" ]; then
                err_msg="${key} directive requires an argument"
            else
                err_msg="Invalid ${key} argument: \"${value}\""
            fi

            return_code=${ERROR}
            break
        fi

    done

    return ${return_code}
}

#-------------------------------------------------------------------------------

# WHAT: Subroutine f__register
# WHY:  This subroutine sets up the variables needed to register a service
#       and/or check in consul
#
f__register() {
    return_code=${SUCCESS}
    these_inputs="${*}"
    key="register"

    if [ "${these_inputs}" = "" ]; then
        err_msg="No ${key} arguments were provided"
        return_code=${ERROR}
        return ${return_code}
    fi

    while [ "${*}" != "" ] ; do
        value=`echo "${1}" | ${my_sed} -e 's?\`??g'`
        let type_check=`echo "${value}" | ${my_egrep} -c "^\-\-"`

        if [ ${type_check} -gt 0 ]; then
            ktype=`echo "${value}" | ${my_sed} -e 's?^--??g'`
            value=`echo "${2}" | ${my_sed} -e 's?\`??g'`

            case "${ktype}" in

                check_id|check_name|check_node|check_notes|check_serviceid|check_status|datacenter|node|node_address|service_address|service_id|service_name|service_port|tags)

                    if [ "${value}" != "" ]; then
                        eval ${key}_${ktype}="${value}"
                        shift
                        shift
                    else
                        err_msg="${key} type \"--${ktype}\" requires an argument"
                        return_code=${ERROR}
                        break
                    fi

                ;;

                *)
                    err_msg="Invalid ${key} type: \"--${ktype}\""
                    return_code=${ERROR}
                    break
                ;;

            esac

        else

            if [ "${value}" = "" ]; then
                err_msg="${key} directive requires an argument"
            else
                err_msg="Invalid ${key} argument: \"${value}\""
            fi

            return_code=${ERROR}
            break
        fi

    done

# --datacenter
# --node
# --node_address
# --service_id
# --service_name
# --tags
# --service_address
# --service_port
# --check_node
# --check_id
# --check_name
# --check_notes
# --check_status
# --check_serviceid

    return ${return_code}
}

#-------------------------------------------------------------------------------

# WHAT: Subroutine f__deregister
# WHY:  This subroutine sets up the variables needed to deregister a service
#       and/or check in consul
#
f__deregister() {
    return_code=${SUCCESS}
    these_inputs="${*}"
    key="deregister"

    if [ "${these_inputs}" = "" ]; then
        err_msg="No ${key} arguments were provided"
        return_code=${ERROR}
        return ${return_code}
    fi

    while [ "${*}" != "" ] ; do
        value=`echo "${1}" | ${my_sed} -e 's?\`??g'`
        let type_check=`echo "${value}" | ${my_egrep} -c "^\-\-"`

        if [ ${type_check} -gt 0 ]; then
            ktype=`echo "${value}" | ${my_sed} -e 's?^--??g'`
            value=`echo "${2}" | ${my_sed} -e 's?\`??g'`

            case "${ktype}" in

                datacenter|node|service_id)

                    if [ "${value}" != "" ]; then
                        eval ${key}_${ktype}="${value}"
                        shift
                        shift
                    else
                        err_msg="${key} type \"--${ktype}\" requires an argument"
                        return_code=${ERROR}
                        break
                    fi

                ;;

                *)
                    err_msg="Invalid ${key} type: \"--${ktype}\""
                    return_code=${ERROR}
                    break
                ;;

            esac

        else

            if [ "${value}" = "" ]; then
                err_msg="${key} directive requires an argument"
            else
                err_msg="Invalid ${key} argument: \"${value}\""
            fi

            return_code=${ERROR}
            break
        fi

    done

# --datacenter
# --node
# --node_address
# --service_id
# --service_name
# --tags
# --service_address
# --service_port
# --check_node
# --check_id
# --check_name
# --check_notes
# --check_status
# --check_serviceid

    return ${return_code}
}

#-------------------------------------------------------------------------------

###############################################################################
# MAIN
################################################################################
#

# WHAT: Make sure we have some useful commands
# WHY:  Cannot proceed otherwise
#
if [ ${exit_code} -eq ${SUCCESS} ]; then

    for command in curl egrep jq sed ; do
        unalias ${command} > /dev/null 2>&1
        f__check_command "${command}"

        if [ ${?} -ne ${SUCCESS} ]; then
            let exit_code=${exit_code}+1
        fi

    done

fi

# WHAT: Make sure we have necessary arguments
# WHY:  Cannot proceed otherwise
#
if [ ${exit_code} -eq ${SUCCESS} ]; then
    key=`echo "${1}" | ${my_sed} -e 's?\`??g'`
    shift

    case "${key}" in

        query)
            f__query ${*}
            exit_code=${?}
        ;;

        register)
            f__register ${*}
            exit_code=${?}
        ;;

        deregister)
            f__deregister ${*}
            exit_code=${?}
        ;;

        *)
            # We bail immediately on unknown or malformed inputs
            err_msg="Unknown command line argument"
            exit_code=${ERROR}
        ;;

    esac

fi

# WHAT: Make JSON based on ${key}
# WHY:  Asked to
#

# WHAT: Perform the requested consul action, based on ${key}
# WHY:  The reason we are here
#

# WHAT: Complain if necessary and exit
# WHY:  Success or failure, either way we are through
#
if [ ${exit_code} -ne ${SUCCESS} ]; then

    if [ "${err_msg}" != "" ]; then
        echo 
        echo "${STDOUT_OFFSET}ERROR:  ${err_msg} ... processing halted"
        echo 
    fi

fi

exit ${exit_code}
