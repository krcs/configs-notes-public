# Storing random data in Nitrokey HSM.

Generate a key of 4096 bytes and store it in Nitrokey HSM.

### Generate key

    dd bs=512 count=8 if=/dev/random of=[key file] iflag=fullblock

or

    openssl rand 4096 > [key file]

or

    pkcs11-tool --generate-random 4096 > [key file]

### Save key to Nitrokey HSM.

    pkcs11-tool --login --id [id] --type data --label [label] --private --always-auth --write-object [key file]

### Read key

    pkcs11-tool --login --type data --label [label] --read-object 

### Delete key file.

    shred -u [key file]

## Links/Reference

https://raymii.org/s/articles/Storing_arbitraty_data_in_the_Nitrokey_HSM.html

