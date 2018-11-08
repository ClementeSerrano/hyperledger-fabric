# Hyperledger basic network

All the source code to set up and run a basic private blockchain network.

## Built With

- [Hyperledger Fabric](https://hyperledger-fabric.readthedocs.io/en/latest/whatis.html)

## Local deployment (for macOS)

These instructions will get you a copy of the project up and running on your local machine for development and testing purposes.

### Prerequisites

- [cURL](https://curl.haxx.se/download.html) (latest version)
- [Docker and Docker Compose](https://www.docker.com/get-started)
- [Go](https://golang.org/dl/) (version 1.11.x)
- [Node.js](https://nodejs.org/en/download/) > v8.9.x. and < v9.x (version 9.x not supported)
- [Npm](https://www.npmjs.com/package/download)
- Python v2.7.x
- Git.
- [Binaries and Docker Images of Hyperledger Fabric](https://hyperledger-fabric.readthedocs.io/en/latest/install.html) (just run `$ curl -sSL http://bit.ly/2ysbOFE | bash -s 1.3.0` on the root of evolve-network folder).

### Cloning and running

First of all clone the repo in your local machine by running:

```
$ git clone https://github.com/ClementeSerrano/hyperledger-fabric.git
```

Enter to the directory of the blockchain network (`$ cd basic-network`) and ensure that you have the Fabric binaries folder (`./bin`) with the principal tools init:

- cryptogen (to create the blockchain network topology and the X.509 certificates of each entity)
- configtxgen (to generates the requisite configuration artifacts for orderer bootstrap and channel creation)
- fabric-ca-client
- configtxlator
- discover
- idemixgen
- orderer
- peer

Finally, set_up and run the network by executing:

```
$ bash network.sh [OPPERATION]
```

where (follow the steps order):

- `OPPERATION=shutdown`: Stop the blockchain network.
- `OPPERATION=setup`: Set up the network by creating the crypto materials and channel-artifacts (channel tx and genesis block).
- `OPPERATION=start`: Run the blockchain network.
- `OPPERATION=restart`: Restart any pre configured blockchain network.
- `OPPERATION=upgrade`: Upgrade configured blockchain network.

Note: If you just run `$ bash network.sh`, the script will automatically run shutdown, setup and start (just what you need to run for a common local deployment).

TO BE CONTINUED...

### Useful tutorials and links

- [Official Hyperledger Fabric Tutorial to built a network](https://hyperledger-fabric.readthedocs.io/en/latest/build_network.html).
- [Youtube tutorial](https://www.youtube.com/watch?v=MPNkUqOKhVE&index=1&list=PLjsqymUqgpSTGC4L6ULHCB_Mqmy43OcIh).

## Authors

- [Clemente Serrano](https://github.com/ClementeSerrano)
