OpenVPN Alpine container
========
Container repo can be found at [DockerHub](https://hub.docker.com/r/gurgui/ovpn)

How to use
--------
A docker volume/local mountpoint must be mounted into **`/etc/openvpn/config`** containing 1 or more OpenVPN server configuration files - [server config template](https://github.com/OpenVPN/openvpn/blob/master/sample/sample-config-files/server.conf). However, as long as you don't set **CREATE_TEST_PKI** to **false**, you don't need to create/bring your own config file since it will be created on first run using [gpkih](https://github.com/gurguii/gpkih).  

- Create a volume
```bash
docker volume create ovpn
```
- Create a container, PKI will be created upon first run
```bash
docker run --name ovpn \
    -it \
    -v ovpn:/etc/openvpn/config \
    --privileged \
    -p 1194:1194/udp \
    -e MAX_VPN_INSTANCES=1 \
    gurgui/ovpn:latest
```  
The default profile generated with gpkih will also generate a client inline configuration which can be found at `/root/test/packs/CL/inline_CL.conf`.  

The only thing left to do is change the client remote with the server's IP and PORT and you'll have a ready-to-use client file. Import it in your [OpenVPN Connect Client](https://openvpn.net/client/) and securely connect to the server.

Environment variables
--------
 **Keyword**       | **Value**        | **Default** | **Description**                                  
:-----------------:|:----------------:|:-----------:|:------------------------------------------------:
 MAX_VPN_INSTANCES | unsigned integer | 2           | Limits the maximum amount of instances to be ran 
 CREATE_TEST_PKI   | boolean          | true        | Creates a test PKI using gpkih on first run      


Notes
--------
I don't know yet why using `--cap-add=NET_ADMIN` and avoiding `--privileged` keeps giving me a permission error(1) when trying to run the `openvpn --config <server.conf>` as root within the container