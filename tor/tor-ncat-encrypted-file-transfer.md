# Encrypt and transfer file over Tor network using ncat.

## SERVER

Ensure that the Tor service is stopped.

Start Tor with the following parameters:

**hiddenservicedir** - Folder to store data files for the hidden service.

**hiddenserviceport** - Ports mapping.

Run Tor service:

    tor --hiddenservicedir <folder> --hiddenserviceport "<port> 127.0.0.1:<local_service_port>"

### GPG

On the other terminal window run **ncat** and pipe through **gpg**:

    ncat -l -p <local_service_port> -v | gpg -quiet --decrypt -o <file_name>

### OpenSSL

On the other terminal window run **ncat** and pipe through **openssl**:

    ncat -l -p <local_service_port> -v | openssl enc -aes-256-cbc -pbkdf2 -pass pass:<password> -d -in - -out <file_name>

The **folder/hostname** file contains the current onion address of the hidden service.

## CLIENT

### GPG

Asymetric encryption:

    gpg -r <recipient> -quiet -o - --encrypt <file_name> | pv | ncat --proxy 127.0.0.1:9050 --proxy-type socks5 <onion_address> <port>

Symetric encryption:

    gpg --batch --yes --passphrase <password> -o - --cipher-algo AES256 --symmetric <file_name> | pv | ncat --proxy 127.0.0.1:9050 --proxy-type socks5 <onion_address> <port>

### OpenSSL

     openssl enc -aes-256-cbc -pbkdf2 -pass pass:<password> -in <file_name> -out - | pv | ncat --proxy 127.0.0.1:9050 --proxy-type socks5 <onion_address> <port>


## NOTES

Tor Expert Bundle: https://www.torproject.org/download/tor/

Tor CLI: https://gitlab.torproject.org/tpo/core/tor/-/raw/main/doc/man/tor.1.txt

ncat: https://nmap.org/download.html
