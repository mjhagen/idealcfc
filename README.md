idealcfc
========

ColdFusion implementation of the iDeal payment protocol version 3.3.1 used by Dutch banks.

###Requirements:

- [javaloader](https://github.com/markmandel/JavaLoader) which is used to compile idealcrypto.class

###Generate ideal certificates like this:

```shell
keytool -genkey -keyalg RSA -sigAlg SHA256withRSA -keysize 2048 -validity 1825 -alias {KeyStoreAlias} -keystore {keystoreFileName.ks}
```

Upload this file to your server (not to a web accessible directory)

```shell
keytool -export -v -rfc -alias {KeyStoreAlias} -keystore {keystoreFileName.ks} -file {certificateFileName.cer}
```

Upload this file to iDeal dashboard

###Config file

```ini
idealURL          URL TO IDEAL
ksFile            ABSOLUTE PATH TO KEYSTORE FILE.ks
ksAlias           KEYSTORE ALIAS
ksPassword        KEYSTORE PASSWORD
merchantID        00000000000
merchantReturnURL http://www.your-website-here.nl/index.cfm
```