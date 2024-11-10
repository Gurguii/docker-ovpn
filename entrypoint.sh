#!/bin/bash

# List of openvpn instances' PID's
pidlist=()

function __ctrl_c_handler(){
    printf -- "Cleaning up before exiting...\n"

    for id in "${pidlist[@]}"; do
        kill "$id"
        wait "$id"
    done
}

function set_TUN(){
    printf -- "-- Creating /dev/net/tun device\n"
    
    # Create the /dev/net directory if it does not exist
    
    if ! mkdir -p /dev/net; then
        printf -- "-- Failed to create /dev/net directory\n"
        return 1
    fi
    
    # Create the TUN device if it hasn't been created (on first run)
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

    # Check server instances to launch
    OpenVPNInstances=($(ls /etc/openvpn/config))
    
    if [ ${#OpenVPNInstances[@]} -eq 0 ]; then
        printf -- "-- No server configuration files found in /etc/openvpn/config\n"
        return 1 # Exit with error code    
    fi

    # TODO - Add ENV VAR indicating default maximum allowed instances e.g 2, allowing user modifying it with 'docker run -e MAX_VPN_INSTANCES=<Number>'
    printf -- "-- Starting %i OpenVPN instances ...\n" "${#OpenVPNInstances[@]}"
    
    for config in "${OpenVPNInstances[@]}"; do
        local path="/etc/openvpn/config/$config"

        openvpn --config "$path" 1>"$stdout_logs" 2>"$stderr_logs" &

        local pid=$!
        local exit_status=$?

        if [[ $exit_status -ne 0 ]]; then
            printf -- "-- Failed starting OpenVPN instance\n"
            cat "$stderr_logs"
            return $exit_status  # Return the exit status of the OpenVPN command
        fi

        local listen_ip="$(grep "listen" $path | cut -d' ' -f2)"
        local listen_port="$(grep "port" $path | cut -d' ' -f2)"

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

function main()
{
    trap SIGINT # clear SIGINT handlers
    trap __ctrl_c_handler SIGINT

    start_OpenVPN
}

main