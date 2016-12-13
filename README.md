# Cloud Haskell nodes

Program for broadcasting messages based on random numbers.

## Usage

You can run program with flag `-h` to see help info:

```
Usage: nodes --send-for S --wait-for S [--with-seed NUM] --nodes-conf PATH
  Cloud Haskell nodes

Available options:
  -h,--help                Show this help text
  --send-for S             Sending period, in seconds
  --wait-for S             Grace period, in seconds
  --with-seed NUM          Seed value for RNG
  --nodes-conf PATH        Path to config file with nodes' endpoints
```

Example command:

```
$ nodes --send-for 8 --wait-for 2 --nodes-conf ./nodes.conf
```

It means nodes will send messages to each other during 8 seconds. After that, during 2 seconds, nodes will print out results. `./nodes.conf` is the path to nodes config file.

## Nodes config file

Example of config file:

```
127.0.0.1:10300
127.0.0.1:10200
127.0.0.1:10201
127.0.0.1:10202
```

In this case program will try to start three last nodes, on `127.0.0.1:10200`, `127.0.0.1:10201` and `127.0.0.1:10202`. These are worker nodes. First endpoint is for special node (for special broadcasting commands).

## Workflow

Each node contains two processes, sender and receiver. Sender generates random numbers and sends them (with timestamps) to all other nodes. Receiver receives such a messages and collects them. Example of message:

```
(1481616425.126990, 0.28400448513890497)
```

First element - time message was sent at (UTC-timestamp with milliseconds), second one - random number from range `(0, 1]`.

After sending period expires, we send "stop message" to all nodes. Nodes stops sending messages and prepares result. Result is a tuple like this:

```
([0.28400448513890497, 0.39491548517890561, ...], 245.09809543677)
```

First element - list of the messages (without timestamps) sorted by sent time, second one - sum of the elements by formula:

```
m
Σ i * m(i)
i=1
```

where `i` - index of element in list of received messages, `m(i)` - i-th message from some node.

After preparing result node prints it out and dies. All nodes must die during grace period, otherwise program will killed.

## Fault tolerance

If we can't start node on the given endpoint (for example, due permissions problem), program won't crash and all other nodes will be started.

