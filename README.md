# ifx-install-script

This script installs Informix versions 11.70 and 12.10 in Ubuntu.

## How to use.

You need an installation file of Informix for one of the Informix versions supported (you
can download no-charge versions from the 
[Informix downloads page] (http://www-01.ibm.com/software/data/informix/downloads.html)).

Run the script as `root` user and pass as the parameter the archive file of the Informix
version that you want to install, for example:

```console
$ ./ifx-install.sh iif.12.10.FC4IE.linux-x86_64.tar
```

The script will create the informix user needed for the Informix server if it does not exist
with the password disabled, you can add a password after the installation as `root` with the
command:

```console
$ passwd informix
```

The Informix installation is done in the directory `/opt/ibm/informix/${INFORMIX_VERSION}/`
and the data directory (chunks and log files) are created under the informix user home:

```console
/home/informix/
└── ${INFORMIX_VERSION}
    └── data
        ├── dbspaces
        │   └── rootdbs
        └── logs
            ├── online.con
            └── online.log
```

The ./config directory contains a common configuration file for the installation and a
specific file for each version supported, you can change some installation values from these
files. By default the `TAPEDEV` and `LTAPEDEV` values are set to `/dev/null` because this
script is mainly created with software testing purposes so you will need to modify these
values if you want to use the server for a more serious things.

### Services added.

The installation adds one new service to the /etc/services file automatically for each
version installed.

```console
$ cat /etc/services
# Local services
ifx1170    9087/tcp
ifx1210    9088/tcp
$
```

## Starting the server.

The installation creates a file with the environment variables needed to work with each
version installed in `/opt/ibm/informix/${INFORMIX_VERSION}/${INFORMIX_SERVER}.env`, by
default the informix server is `ifx1170` and `ifx1210` for the versions 11.70 and 12.10
respectively. For starting the server you need to switch to the informix user and load
the environment file before use the informix commands:

```console
$ su - informix
$ . /opt/ibm/informix/12.10/etc/ifx1210.env
```
then you can start the server:

```console
$ oninit
$ onstat -
```
the last command `onstat -` gives you information about the status of the server that should
be `On-Line`.

## Stoping the server.

With the environment file loaded use the command:

```console
$ onmode -ky
$ onstat -
```
now the `onstat -` command will give you a message like `shared memory not initialized
for INFORMIXSERVER` that means that the server is not running.

## Database creation.

No database is created by default. Please refer to the Informix documentation for that:
[CREATE DATABASE statement] (http://www-01.ibm.com/support/knowledgecenter/SSGU8G_11.50.0/com.ibm.sqls.doc/ids_sqs_0368.htm).

## Links.

- For other topics about Informix you can use the
[IBM Knowledge Center] (http://www-01.ibm.com/support/knowledgecenter/SSGU8G/welcomeIfxServers.html).
- To download a no-charge version of Informix go to the
[Informix downloads page] (http://www-01.ibm.com/software/data/informix/downloads.html).



