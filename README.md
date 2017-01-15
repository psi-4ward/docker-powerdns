# PowerDNS Docker Container

[![Image Size](https://images.microbadger.com/badges/image/psitrax/powerdns.svg)]()
[![Docker Stars](https://img.shields.io/docker/stars/psitrax/powerdns.svg)]()
[![Docker Pulls](https://img.shields.io/docker/pulls/psitrax/powerdns.svg)]()
[![Docker Automated buil](https://img.shields.io/docker/automated/psitrax/powerdns.svg)]()

* Small Alpine based Image
* MySQL (default), Postgres, SQLight and Bind backend included
* Automatic MySQL database initialization
* Latest PowerDNS version (if not pls file an issue)
* Guardian process enabled
* Graceful shutdown using pdns_control

## Usage

```shell
# Start a MySQL Container
$ docker run -d \
  --name pdns-mysql \
  -e MYSQL_ROOT_PASSWORD=supersecret \
  -v $PWD/mysql-data:/var/lib/mysql \
  mariadb:10.1

$ docker run --name pdns \
  --link pdns-mysql:mysql \
  -p 53:53 \
  -p 53:53/udp \
  -e MYSQL_USER=root \
  -e MYSQL_PASS=supersecret \
  psitrax/powerdns \
    --cache-ttl=120 \
    --allow-axfr-ips=127.0.0.1 123.1.2.3
```

## Configuration

**Environment Configuration:**

* MySQL connection settings
  * `MYSQL_HOST=mysql`
  * `MYSQL_USER=root`
  * `MYSQL_PASS=root`
  * `MYSQL_DB=pdns`
* Want to disable mysql initialization? Use `MYSQL_AUTOCONF=false`
* Want to use own config files? Mount a Volume to `/etc/pdns/conf.d` or simply overwrite `/etc/pdns/pdns.conf`

**PowerDNS Configuration:**

Append the PowerDNS setting to the command as shown in the example above.  
See `docker run --rm psitrax/powerdns --help`


## Maintainer

* Christoph Wiechert <wio@psitrax.de>
