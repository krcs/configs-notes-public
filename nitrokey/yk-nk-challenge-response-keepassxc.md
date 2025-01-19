# Nitrokey/Yubikey challange-response KeePassXC.

## Generate a 20-byte hexadecimal string encoded to base32.

**nitropy**:

    nitropy nk3 rng -l 20 | xxd -r -p - | base32

or **openssl**

    openssl rand 20 | base32

You can save the hexadecimal value and store it in a secret location and
transfer it to another device and have a backup.

## Transfering secret to the device.

### Nitrokey:

    nitropy nk3 secrets add-challenge-response 2 <secret>

or

    nitropy nk3 rng -l 20 | xxd -r -p - | base32 | xargs nitropy nk3 secrets add-challenge-response 2 

### Yubikey:

    ykman otp otp chalresp -T -f 2 <secret

or

    openssl rand 20 | base32 | xargs ykman otp chalres -T -f 2

## KeepassXC

Add a response-challenge in KeepassXC, under the Database credentials tab.

## NOTES

Programming two keys at once with a single secret.

    nitropy nk3 rng -l 20 | xxd -r -p - | base32 | tee >( xargs ykman otp chalresp -T -f 2) >( nitropy nk3 secrets add-challange-response 2) > /dev/null
