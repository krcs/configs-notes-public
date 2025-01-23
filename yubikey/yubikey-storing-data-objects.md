# Yubikey - storing data objects

## PIV standard-defined DataTags

| Number                  | Name             | PIN     |
| :---------------------: | :--------------: | :-----: |
| 0x0000007E              | DISCOVERY        | No      |
| 0x00007F61              | BITGT            | No      |
| 0x005FC101              | Card Auth (cert) | No      |
| 0x005FC102              | CHUID            | No      |
| **0x005FC103**          | **Fingerprints** | **Yes** |
| 0x005FC104              | -unused-         | No      |
| 0x005FC105              | Auth (cert)      | No      |
| 0x005FC106              | Security         | No      |
| 0x005FC107              | CCC              | No      |
| **0x005FC108**          | **Facial Image** | **Yes** |
| **0x005FC109**          | **Printed**      | **Yes** |
| 0x005FC10A              | Signature (cert) | No      |
| 0x005FC10B              | Key Mgmt (cert)  | No      |
| 0x005FC10C              | Key History      | No      |
| 0x005FC10D - 0x005FC120 | Retired (certs)  | No      |
| **0x005FC121**          | **Iris**         | **Yes** |
| 0x005FC122              | SM Signer (cert) | No      |
| 0x005FC123              | PC Ref Data      | No      |

### Yubico-defined DataTags

| Number                  | Name             | PIN  |
| :---------------------: | :--------------: | :--: |
| 0x005FFF00              | Admin Data       | No   |
| 0x005FFF01              | Attestation Cert | No   |
| 0x005FFF10              | MSCMAP           | No   |
| 0x005FFF11 - 0x005FFF15 | MSROOTS          | No   |

### Undefined DataTags

| Number range            | PIN  |
| :---------------------: | :--: |
| 0x005F0000 - 0x005FC100 | No   |
| 0x005FC124 - 0x005FFEFF | No   |
| 0x005FFF02 - 0x005FFF0F | No   |
| 0x005FFF16 - 0x005FFFFF | No   |

## Import/Export - first undefined DataTags range.

Range: 0x005F0000 to 0x005FC100.

Yubikey NEO, Firmawre 3.5.0 - maximum 2034 bytes for single undefined DataTag.

    (0x005FC100-0x005F0000)*2034 = 100495872 (~100MB)

Split input into chunks of 2034 bytes.

    split --verbose -b 2034 -a 8 --hex-suffixes=5f0000 <input_file> 0x

Import files to Yubikey:

    for n in 0x*; do
        ykman piv objects import -m "<management-key>" $n $n;
        rm $n;
    done

Export data from Yubikey:

    rm -f <output_file>
    for n in $(seq 0x5f0000 0x5Fc100); do
        ykman piv objects export $(printf "0x%08x" "$n") - >> <output_file>;
        if [ $? -ne 0 ]; then
            break;
        fi;
    done

Verify:

    sha256sum <input_file> <output_file>

## Reference/Notes

https://docs.yubico.com/yesdk/users-manual/application-piv/piv-objects.html

