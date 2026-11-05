# etcd cluster

The PostgreSQL HA cluster uses three etcd members:

- etcd1
- etcd2
- etcd3

Each member has its own persistent Docker volume.

Patroni uses etcd v3 as its Distributed Configuration Store (DCS).

All members communicate over the internal Docker network.

