# docker NAT router *example*
> Is it possible to implement NAT routing or firewalling withing docker containers? **YES!**

> Should you use a setup like this in production? *Probably* **NOT!**


An example for building routed networks with *docker* and *docker-compose*; intended for *use in automated testing* setups.

> ⚠ This is no reference implementation of a NAT router container to be used in production! While the provided material may be used to build test benches, it is considered purely educational!


## Layout
💻 ⇆ *{external}* ☁ ⇆ **💻 ROUTER** ⇄ ☁ *{internal}* ⇄ 💻
### Networks

#### ☁ external
Default docker bridge network (`default` in *docker-compose*) Represents the *external* network to be routed to (e.g. "the internet").


#### ☁ internal
> Building a NAT router in docker is only possible from *macvlan* networks, as otherwise all IP traffic is handled directly by the host, outside the realm of influence of a container!

A *macvlan* network without parent interface. Containers in this network can communicate with each other but not reach targets outside the network by default. A virtual interface is automatically created as parent by docker. A custom subnet and gateway address may be specified from the compose file; if not, docker will assign a random subnet and the first usable (non-broadcast) address on the subnet as gateway to containers on the network.


### Containers
The stack is made up of three containers, where each container shares one network with the `router` container:
* `external`
* **`router`**
* `internal`

#### 🖥 `external`
Dummy container as ping target. Sharing the default docker bridge network (*external* above) with the `router` container. *No further configuration requirements for this container exist.*

#### 🖥 `router`
Attached to both networks. Performing NAT routing from *internal* to *external* network and DNS forwarding.

📌 The router assumes the routed *internal* network to be attached at the interface with the lowest index! Interface order is achieved by providing a `priority` value in compose. To not rely on interface ordering, use a fixed subnet and provide it in CIDR notation as environment variable `ROUTE_NET`.

##### network config
Docker assigns a gateway address as described above to all containers on the *internal* network. The router assigns itself this gateway address on the *internal* network interface, using either the explicitly specified address, or deducing the gateway address from the interfaces' subnet.

The address assigned by docker on the *internal* interface will be kept, to allow using dockers' internal DNS resolver to resolve the routers' address.

##### routing
NAT routing is performed using *iptables* rules. Modifying iptables, requires the container to be ran with `NET_ADMIN` capabilities. Routing will be configured from *internal* network to **all** other networks attached to the `router` container!

##### DNS forwarding
*dnsmasq* performs DNS forwarding for containers on the *internal* subnet, to the routers DNS resolver provided by docker. Dockers' DNS resolver only resolves container names on the same network. As the `router` is attached to both networks, the local resolver is able to resolve names from both these networks. The router mounts and updates a `resolv.conf` file in the `data/` directory, to be mounted by the internal containers as `/etc/resolv.conf`.

**A note on docker networks and DNS servers**
> Docker uses an internal DNS resolver for containers. Supplying additional DNS servers via command line or docker-compose adds these addresses to the internal resolver, but does not modify `/etc/resolv.conf` (except, when **explicitly** using and specifying a network as `bridge`-network). The internal resolver does not perform name lookup for DNS servers and has to reach all DNS server from the host network, thus prohibiting the use of container names as DNS servers.


#### 🖥 `internal`
Connected to the *internal* network only. For DNS resolution to containers on the *external* network, mounting `/data/resolv.conf` as `/etc/resolv.conf` is necessary! To ensure name resolution for applications, the internal container waits for the router to be up, using `depends_on: [router]` in compose. Gateway address is assigned by docker automatically, while the router container takes care of providing routing at that address.

Apart from mounting `resolv.conf` for container name resolution - if desired -, *no further configuration requirements for this container exist.*

## Usage
Examples are provided in `examples/`. Run `docker-compose` on the main compose file and the example to examine. Afterwards, play around; connect to containers and observe behavior; e.g:
add more containers, remove containers, remove the `router`-container, do not mount `resolv.conf`, etc..

### examples
compose files from `examples/`

#### up
Starts all containers. Runs a shell with attached tty in *internal* and *external* container to keep them alive. Use to run commands in the containers and observe the behavior; e.g. `docker-compose exec internal ping external`.

```
docker-compose -f docker-compose.yml -f examples/up.yml up
```

#### hello
* *external* container listens on port `8888` using *netcat*, echoing `hello from external @ channel opened from remote`.
* *internal* container connects to *external* on port `8888` using *netcat*, echoing `hello from internal`

The output from both containers can be observed in the *docker-compose* log.

```
docker-compose -f docker-compose.yml -f examples/hello.yml up
```

#### reverse-fail
Tries to ping *internal* from *external*. Uses `router` as DNS to resolve *internal* network container names. Run with `--abort-on-container-exit` to bring down all containers on individual container exit and observe exit code.

```
# NIX
docker-compose -f docker-compose.yml -f examples/reverse-fail.yml up --abort-on-container-exit; echo exit code: $?

# WIN
docker-compose -f docker-compose.yml -f examples/reverse-fail.yml up --abort-on-container-exit & echo exit code: %errorlevel%
```


### specify routed subnet or gateway
Find commented sections in `docker-compose.yml` relating to `ROUTE_NET` and/or `ROUTE_GATEWAY`. Setup IPAM config, and provide the subnet in CIDR notation to the `router`-container as `ROUTE_NET=<my.su.bn.et/prefix>`, to use a specific subnet. To use a specific gateway, provide `ROUTE_GATEWAY` in IPAM config and `router`-container environment.



