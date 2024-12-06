#!/bin/bash

# BEG - Environment variables

# MAX_VPN_INSTANCES - maximum allowed instances to be executed, default 2
# CREATE_TEST_PKI   - create a PKI for testing purposes on first run, default true
# TEST_PKI_REMOTE   - set 'remote' on test pki configuration, ignored if CREATE_TEST_PKI=false, default ""

# END - Environment variables

pidlist=() # List of openvpn instances' PID's
declare -A instances # instance['myServer']="$pid;$status;$log;listen_ip;listen_port;protocol"

function __ctrl_c_handler(){
    printf -- "Cleaning up before exiting...\n"

    for id in "${pidlist[@]}"; do
        kill "$id" &>/dev/null
        wait "$id" &>/dev/null
    done
}

function set_TUN(){
    printf -- "-- Creating /dev/net/tun device\n"
    
    # Create the /dev/net directory if it does not exist
    
    if ! mkdir -p /dev/net; then
        printf -- "-- Failed to create /dev/net directory\n"
        return 1
    fi
    
    # Create the TUN device if it hasn't been created
    if [ ! -e /dev/net/tun ]; then
    	mknod /dev/net/tun c 10 200
    	if [[ $? -ne 0 ]]; then
    	    printf -- "-- Failed to create /dev/net/tun device\n"
    	    return 1
    	fi
    fi

    # Set permissions on the TUN device
    if ! chmod 600 /dev/net/tun; then
        printf -- "-- Failed to set permissions on /dev/net/tun\n"
        return 1
    fi

    printf -- "-- /dev/net/tun device created successfully\n"
    return 0
}

function start_Monitoring() {
    # ${instance[N]}="$pid;$status;$log;$lip;$lport;$protocol"

    # Initialize maximum widths for each column (default values are column names' length + 2)
    local max_name_width=6
    local max_pid_width=5
    local max_status_width=8
    local max_log_width=5
    local max_lip_width=11
    local max_lport_width=13
    local max_protocol_width=10

    # First pass: Determine maximum widths
    for i in "${!instances[@]}"; do
        local pid="$(cut -d: -f1 <<< "${instances[$i]}")"
        local status="$(cut -d: -f2 <<< "${instances[$i]}")"
        local log="$(cut -d: -f3 <<< "${instances[$i]}")"
        local lip="$(cut -d: -f4 <<< "${instances[$i]}")"
        local lport="$(cut -d: -f5 <<< "${instances[$i]}")"
        local protocol="$(cut -d: -f6 <<< "${instances[$i]}")"

        (( ${#i} > max_name_width )) && max_name_width=${#i}
        (( ${#pid} > max_pid_width )) && max_pid_width=${#pid}
        (( ${#status} > max_status_width )) && max_status_width=${#status}
        (( ${#log} > max_log_width )) && max_log_width=${#log}
        (( ${#lip} > max_lip_width )) && max_lip_width=${#lip}
        (( ${#lport} > max_lport_width )) && max_lport_width=${#lport}
        (( ${#protocol} > max_protocol_width )) && max_protocol_width=${#protocol}
    done

    # Add some padding to the maximum widths
    max_name_width=$((max_name_width + 2))
    max_pid_width=$((max_pid_width + 2))
    max_status_width=$((max_status_width + 2))
    max_log_width=$((max_log_width + 2))
    max_lip_width=$((max_lip_width + 2))
    max_lport_width=$((max_lport_width + 2))
    max_protocol_width=$((max_protocol_width + 2))

    # Print header
    printf "%-${max_name_width}s\t%-${max_pid_width}s\t%-${max_status_width}s\t%-${max_log_width}s\t%-${max_lip_width}s\t%-${max_lport_width}s\t%-${max_protocol_width}s\n" "NAME" "PID" "STATUS" "LOG" "LISTEN IP" "LISTEN PORT" "PROTOCOL"
    printf "%-${max_name_width}s\t%-${max_pid_width}s\t%-${max_status_width}s\t%-${max_log_width}s\t%-${max_lip_width}s\t%-${max_lport_width}s\t%-${max_protocol_width}s\n" "----" "---" "------" "---" "--------" "----------" "--------"

    # Second pass: Print the values
    for i in "${!instances[@]}"; do
        local pid="$(cut -d: -f1 <<< "${instances[$i]}")"
        local status="$(cut -d: -f2 <<< "${instances[$i]}")"
        local log="$(cut -d: -f3 <<< "${instances[$i]}")"
        local lip="$(cut -d: -f4 <<< "${instances[$i]}")"
        local lport="$(cut -d: -f5 <<< "${instances[$i]}")"
        local protocol="$(cut -d: -f6 <<< "${instances[$i]}")"

        printf "%-${max_name_width}s\t%-${max_pid_width}s\t%-${max_status_width}s\t%-${max_log_width}s\t%-${max_lip_width}s\t%-${max_lport_width}s\t%-${max_protocol_width}s\n" "$i" "$pid" "$status" "$log" "$lip" "$lport" "$protocol"
    done
}

function start_OpenVPN(){
    if ! set_TUN; then
        return $?
    fi

    # Check server instances to launch (file must have .ovpn|.conf extension)
    OpenVPNInstances=($(ls /etc/openvpn/config | grep -E '\.(ovpn|conf)$'))
    
    if [ ${#OpenVPNInstances[@]} -eq 0 ]; then
        printf -- "-- No suitable server configuration files found in /etc/openvpn/config\n"
        return 1
    fi

    if (( "${#OpenVPNInstances[@]}" > $MAX_VPN_INSTANCES )); then
        printf -- "-- Configuration files (%i) exceed allowed vpn instances (%i), add '-e MAX_VPN_INSTANCES=<NUMBER>' to change it\n" "${#OpenVPNInstances[@]}" "$MAX_VPN_INSTANCES"
        return 1
    fi

    printf -- "-- Starting %i OpenVPN instances ...\n" "${#OpenVPNInstances[@]}"
    
    mkdir -p "/etc/openvpn/logs"

    for config in "${OpenVPNInstances[@]}"; do
        local filenameWithoutExt=$(cut -d. -f1 <<< $config)
        
        mkdir -p "/etc/openvpn/logs/$filenameWithoutExt"

        local stdout_logs="/etc/openvpn/logs/$filenameWithoutExt/out.log"
        local stderr_logs="/etc/openvpn/logs/$filenameWithoutExt/err.log"
        local path="/etc/openvpn/config/$config"

        openvpn --config "$path" 1>"$stdout_logs" 2>"$stderr_logs" &

        local pid=$!
        local exit_status=$?

        if [[ $exit_status -ne 0 ]]; then
            printf -- "-- Failed starting OpenVPN instance\n"
            cat "$stderr_logs"
            return $exit_status  # Return the exit status of the OpenVPN command
        fi

        local listen_ip="$(grep -E '^listen' $path | cut -d' ' -f2)"
        local listen_port="$(grep -E '^port' $path | cut -d' ' -f2)"

        if [ -z $listen_ip ]; then
            listen_ip="0.0.0.0"
        fi

        pidlist+=($pid)

        local statusValue="$( grep -E '^status ' $path | cut -d' ' -f2)"
        local logValue="$( grep -E '^log ' $path | cut -d' ' -f2)"
        local protocol="$( grep -E '^proto ' $path | cut -d' ' -f2)"

        if [ -z "$logValue" ]; then
            logValue="$(grep -E '^log-append ' $path | cut -d' ' -f2)"
        fi

        instances[$config]="$pid:$statusValue:$logValue:$listen_ip:$listen_port:$protocol"
        printf -- "-- OpenVPN instance '%s' started\n" "$config"
        #printf -- "-- OpenVPN instance started\n\tFilename: %s\n\tListen: %s:%i\n\tPID: %i\n" "$config" "$listen_ip" "$listen_port" "$pid"    
    done

    start_Monitoring 
    
    for process in $pidlist; do
        wait $process
    done

    printf -- "-- All instances finished, exiting ...\n"
}

function create_test_PKI(){
    # Create profile + dhparam
    printf -- "-- Initializing test profile\n";
    echo -e "y\nn\n" | gpkih init -n test -s ~/test &>/dev/null
    
    # Set profile's OVPN client status file
    if ! gpkih set test @vpn.server status="/etc/openvpn/testPKI_client_status.txt" &>/dev/null; then
        printf -- "-- Setting client status value failed\n"
    fi
    
    # Check VPN_CLIENT_REMOTE ENV value and set if exists
    if ! [ -z "$VPN_CLIENT_REMOTE" ]; then
        printf -- "-- Setting clients' remote to %s\n" "$VPN_CLIENT_REMOTE"
        if ! gpkih set test vpn.client.remote="$VPN_CLIENT_REMOTE"; then
            printf -- "-- Setting vpn.client.remote failed\n";
        fi
    fi

    if ! gpkih add test -t ca -cn CA &>/dev/null; then
    # Create CA
        printf -- "-- Creating CA failed\n"
    fi
    
    # Create SV
    if ! gpkih add test -t sv -cn SV -y &>/dev/null; then
        printf -- "-- Creating SERVER failed\n"
    fi

    # Create CL
    if ! gpkih add test -t cl -cn CL -y &>/dev/null; then
        printf -- "-- Creating CLIENT failed\n"
    fi
EOF
    # Add the new config to /etc/openvpn/config
    cp ~/test/packs/SV/inline_SV.conf /etc/openvpn/config/
}

function main()
{
    trap SIGINT # clear SIGINT handlers
    trap __ctrl_c_handler SIGINT

    if [ ! -e "/.first_run" ]; then
        touch "/.first_run"
        if $CREATE_TEST_PKI; then
            printf -- "-- Creating test PKI\n"
            create_test_PKI
        fi
    fi

    start_OpenVPN
}

main