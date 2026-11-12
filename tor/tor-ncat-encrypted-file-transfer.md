# Encrypt and transfer file over Tor network using ncat.

## Receiver (decryption)

Ensure that the Tor service is stopped.

Create folder for the hidden service data and change its permission.

    mkdir <folder>
    chmod 700 <folder>

This folder will contain a hostname file with the onion address.

Start Tor with the following parameters:

**hiddenservicedir** - Folder to store data files for the hidden service.

**hiddenserviceport** - Ports mapping.

**SocksPort** - optional - Tor listening port. Default 9050.

Run Tor service:

    tor --ignore-missing-torrc \
        --SocksPort <socksport> \
        --hiddenservicedir <folder> \
        --hiddenserviceport "<port> 127.0.0.1:<local_service_port>" \

### GPG

    ncat -l -p <local_service_port> -v | gpg -quiet --decrypt -o <file_name>

### OpenSSL

    ncat -l -p <local_service_port> -v | openssl enc -aes-256-cbc -pbkdf2 -pass pass:<password> -d -in - -out <file_name>

### AGE

    ncat -l -l <local_service_port> -v | age -d -i <identity> -o <file_name>


## Sender (encryption)

### GPG

Asymetric encryption:

    gpg -r <recipient> -quiet -o - --encrypt <file_name> | pv | ncat --proxy 127.0.0.1:9050 --proxy-type socks5 <onion_address> <port>

Symetric encryption:

    gpg --batch --yes --passphrase <password> -o - --cipher-algo AES256 --symmetric <file_name> | pv | ncat --proxy 127.0.0.1:9050 --proxy-type socks5 <onion_address> <port>

### OpenSSL

     openssl enc -aes-256-cbc -pbkdf2 -pass pass:<password> -in <file_name> -out - | pv | ncat --proxy 127.0.0.1:9050 --proxy-type socks5 <onion_address> <port>

### AGE

    age -e -r <recipient> -o - <file_name> | pv | ncat --proxy 127.0.0.1:9050 --proxy-type socks5 <onion_adress> <port>

## NOTES

Tor Expert Bundle: https://www.torproject.org/download/tor/

Tor CLI reference: https://gitlab.torproject.org/tpo/core/tor/-/raw/main/doc/man/tor.1.txt

ncat: https://nmap.org/download.html

age: https://github.com/FiloSottile/age
