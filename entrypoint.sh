#!/bin/bash

# BEG - Environment variables

# MAX_VPN_INSTANCES - maximum allowed instances to be executed, default 2
# CREATE_TEST_PKI   - create a PKI for testing purposes on first run, default true

# END - Environment variables

pidlist=() # List of openvpn instances' PID's

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

function start_OpenVPN(){
    local stdout_logs="/.out.log"
    local stderr_logs="/.err.log"

    if ! set_TUN; then
        return $?
    fi

    # Check server instances to launch (file must have .ovpn extension)
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
    
    for config in "${OpenVPNInstances[@]}"; do
        local path="/etc/openvpn/config/$config"

        openvpn --config "$path" 1>"$stdout_logs" 2>"$stderr_logs" &

        local pid=$!
        local exit_status=$?
        local filenameWithoutExt=$(cut -d. -f2 <<< $config)

        if [[ $exit_status -ne 0 ]]; then
            printf -- "-- Failed starting OpenVPN instance\n"
            cat "$stderr_logs"
            return $exit_status  # Return the exit status of the OpenVPN command
        fi

        local listen_ip="$(grep -Ev '^#' $path | grep "listen" | cut -d' ' -f2)"
        local listen_port="$(grep -Ev '^#' $path | grep "port" | cut -d' ' -f2)"

        if [ -z $listen_ip ]; then
            listen_ip="0.0.0.0"
        fi

        pidlist+=($pid)

        printf -- "-- OpenVPN instance started\n\tFilename: %s\n\tListen: %s:%i\n\tPID: %i\n" "$config" "$listen_ip" "$listen_port" "$pid"    
    done

    for process in $pidlist; do
        wait $process
    done

    printf -- "-- All instances finished, exiting ...\n"
}

function create_test_PKI(){
    # Create profile + dhparam
    echo -e "y\nn\n" | gpkih init -n test -s ~/test
    
    # Create CA
    if ! gpkih add test -t ca -cn CA; then
        printf -- "-- Creating CA failed\n"
    fi
    
    # Create SV
    if ! gpkih add test -t sv -cn SV -y; then
        printf -- "-- Creating SERVER failed\n"
    fi

    # Create CL
    if ! gpkih add test -t cl -cn CL -y; then
        printf -- "-- Creating CLIENT failed\n"
    fi
    
    # Add dhparam to server inline config
    cat << EOF >> ~/test/packs/SV/inline_SV.conf
<dh>
$(cat ~/test/pki/tls/dhparam4096)
</dh>
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