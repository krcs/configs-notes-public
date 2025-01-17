# Synapse - uprading PostgreSQL from 12 to 17 - Debian

## Environment

Data folders:

    /storage/db/pg12
    /storage/db/pg17

Binary:

    /usr/lib/postgresql/12/bin
    /usr/lib/postgresql/17/bin

## Initialization

Stop synapse service.

Switch to the postgres user:

    sudo su - postgres

Create and init new data folder.

    mkdir /storage/db/pg17

    /usr/lib/postgresql/17/bin/initdb \
        --lc-collate=C \
        --lc-ctype=C \
        --encoding=UTF8 \
        -D /storage/db/pg17 \
        -U postgres

Modfiy **postgresql.conf**. Change the listening port on the new instance if you want to run both instances at the same time.

    /storage/db/pg12/postgresql.conf
    /storage/db/pg17/postgresql.conf

Make sure that both instances are not running:

    /usr/lib/postgresql/12/pg_ctl stop -D /storage/db/pg12
    /usr/lib/postgresql/17/pg_ctl stop -D /storage/db/pg17

## pg_upgrade

Run the **pg_upgrade** command in the check mode.

    /usr/lib/postgres/17/bin/pg_upgrade \
        -b /usr/lib/postgresql/12/bin \
        -B /usr/bin/postgresql/17/bin \
        -d /storage/db/pg12/ \
        -D /storage/db/pg17/ \
        --username=postgres \
        --check

If everything is ok run above command without the _check_ parameter.

## homeserver.yaml

Check and/or modify the database section in the synapse config file - **homeserver.yaml** . 

Start new instance:

    /usr/lib/postgresql/17/pg_ctl start -D /storage/db/pg17

## NOTES

You may need to create a new user **synapse_user** in the new instance.

    /usr/lib/postgresql/17/bin/createuser --pwprompt synapse_user

In the file below, there is an entry that specifies the instance's startup mode.

    /etc/postgresql/<version>/main/start.conf

