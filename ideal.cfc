component accessors=true hint="See https://github.com/mjhagen/idealcfc for implementation help." {
  property type="date"    name="timestamp";
  property type="numeric" name="amount";
  property type="numeric" name="merchantId";
  property type="numeric" name="purchaseId" hint="Order ID";
  property type="numeric" name="subId";
  property type="string"  name="cacheName" hint="ideal.cfc is cached per application";
  property type="string"  name="currency";
  property type="string"  name="debugEmail";
  property type="string"  name="debugIp";
  property type="string"  name="debugLog";
  property type="string"  name="defaultCountry" hint="Optional, set to country of website";
  property type="string"  name="description" hint="NO HTML ALLOWED!";
  property type="string"  name="entranceCode" hint="Session ID";
  property type="string"  name="expirationPeriod" hint="Optional, date period format: PnYnMnDTnHnMnS";
  property type="string"  name="idealUrl" required=true;
  property type="string"  name="issuerId";
  property type="string"  name="ksAlias";
  property type="string"  name="ksFile";
  property type="string"  name="ksPassword";
  property type="string"  name="language";
  property type="string"  name="merchantReturnUrl";
  property type="string"  name="transactionId";

  /**
  * Constructor method
  * @param config          Absolute path to the config file
  * @param initProperties  Properties to be set, for example:
  *                          init( initProperties={issuerID="12345"});
  */
  public component function init( string config = '', struct initProperties = {} ) {
    param type="numeric" name="subId"              default=0;
    param type="string"  name="cacheName"          default="ideal-cache";
    param type="string"  name="currency"           default="EUR";
    param type="string"  name="debugEmail"         default="administrator@your-website-here.nl";
    param type="string"  name="debugIp"            default="::1,fe80:0:0:0:0:0:0:1%1,127.0.0.1";
    param type="string"  name="debugLog"           default="ideal-cfc";
    param type="string"  name="defaultCountry"     default="Nederland";
    param type="string"  name="language"           default="nl";
    param type="string"  name="transactionId"      default="";

    var pwd = getDirectoryFromPath( getCurrentTemplatePath() );

    if ( !structKeyExists( server, 'idealcrypto' ) || structKeyExists( url, 'idealreload' ) ) {
      var jl = new javaloader.JavaLoader( [ '#pwd#/lib/' ] );
      var idealcrypto = jl.create( 'idealcrypto' );
      server.idealcrypto = idealcrypto;
    }

    variables.idealcrypto = server.idealcrypto;

    try {
      lock name="lock_#application.applicationname#_init" timeout="5" type="exclusive" {
        if ( !structKeyExists( application, variables.cachename ) || structKeyExists( url, 'reload' ) ) {
          application[ variables.cachename ] = {};
        }

        /* Optionally read config from a file, otherwise, just instantiate the cfc with your options as arguments */
        if ( len( trim( config ) ) && fileExists( config ) ) {
          application[ variables.cachename ].properties = {};

          var configFile = fileRead( config, 'utf-8' );

          for ( var valuePair in listToArray( configFile, '#chr( 13 )##chr( 10 )#' ) ) {
            if ( valuePair contains '<!---' ||
            valuePair contains '--->' ||
            valuePair contains '/*' ||
            valuePair contains '*/' ) {
              continue;
            }

            initProperties[ trim( listFirst( valuePair, ' #chr( 9 )#' ) ) ] = trim( listRest( valuePair, ' #chr( 9 )#' ) );
          }
        }
      }

      structAppend( variables, initProperties, true );

      param variables.ksFile='';

      if ( left( variables.ksFile, 1 ) == '.' ) {
        variables.ksFile = expandPath( variables.ksFile );
      }

      if ( !fileExists( variables.ksFile ) ) {
        throw( type = 'nl.mingo.ideal.init', message = 'Missing keystore file' );
      }

      return this;
    } catch ( any cfcatch ) {
      return handleError( cfcatch );
    }
  }

  /**
  * Method to generate a <select /> with a list of participating banks
  * @param class           CSS class name(s)
  * @param firstOption     Text on the first option
  * @param css             Inline CSS
  */
  public string function directoryRequest( string class = '', string firstOption = 'Kies uw bank:', string css = 'margin-bottom:10px;' ) {
    try {
      var drCacheName = 'DR_#dateFormat( now(), 'yyyymmdd' )#';
      var issuerXML = '';
      var issuerList = '';
      var result = '';

      // Per ideal request, this is cached for the duration of the application's life.
      if ( !structKeyExists( application[ variables.cachename ], drCacheName ) ) {
        var issuersXML = postRequest( 'Directory' );
        var issuers = {};
        var issuerLists = issuersXML.DirectoryRes.Directory;

        if ( structKeyExists( issuersXML.DirectoryRes.Directory, 'Country' ) ) {
          issuerLists = issuersXML.DirectoryRes.Directory.Country;
        }

        for ( var issuerXML in issuerLists.xmlChildren ) {
          if ( issuerXML.xmlName eq 'countryNames' ) {
            issuerList = issuerXML.xmlText;
          }

          if ( issuerXML.xmlName neq 'Issuer' ) {
            continue;
          }

          if ( !structKeyExists( issuers, issuerList ) ) {
            issuers[ issuerList ] = [];
          }

          arrayAppend( issuers[ issuerList ], { 'id' = issuerXML.xmlChildren[ 1 ].xmlText, 'name' = issuerXML.xmlChildren[ 2 ].xmlText } );
        }

        application[ variables.cacheName ][ drCacheName ] = issuers;
      }

      issuers = application[ variables.cachename ][ drCacheName ];
      var issuerKeyList = listSort( structKeyList( issuers ), 'text' );

      if ( len( variables.defaultCountry ) ) {
        if ( listFindNoCase( issuerKeyList, variables.defaultCountry ) ) {
          issuerKeyList = listDeleteAt( issuerKeyList, listFindNoCase( issuerKeyList, variables.defaultCountry ) );
        }
        issuerKeyList = listPrepend( issuerKeyList, variables.defaultCountry );
      }

      result &= '<select name="issuerID" id="issuerID" style="#css#" class="#class#">';
      result &= '<option value="">#firstOption#</option>';

      var issuerKeyListLength = listLen( issuerKeyList );

      for ( var i = 0; i <= issuerKeyListLength; i = i + 1 ) {
        var key = issuerKeyList[ i ];
        if ( !structKeyExists( issuers, key ) ) {
          continue;
        }

        result &= '<optgroup label="#key#">';

        for ( var issuer in issuers[ key ] ) {
          result &= '<option value="#issuer.id#">#issuer.name#</option>';
        }

        result &= '</optgroup>';
      }

      result &= '</select>';

      return result;
    } catch ( any cfcatch ) {
      return handleError( cfcatch );
    }
  }

  /**
  * @param redirect        If you need to do more processing before being
  *                          redirected, set this to false.
  */
  public string function transactionRequest( boolean redirect = true ) {
    try {
      var transactionXML = postRequest( 'Transaction' );

      if ( redirect ) {
        location( url = transactionXML.AcquirerTrxRes.Issuer.issuerAuthenticationURL.xmlText, addToken = false );
      }

      variables.transactionId = transactionXML.AcquirerTrxRes.Transaction.transactionID.XmlText;

      return transactionXML.AcquirerTrxRes.Issuer.issuerAuthenticationURL.xmlText;
    } catch ( any cfcatch ) {
      return handleError( cfcatch );
    }
  }

  /**
  * Returns the status of the current order being processed by ideal
  */
  public string function statusRequest() {
    try {
      return postRequest( 'Status' );
    } catch ( any cfcatch ) {
      return handleError( cfcatch );
    }
  }

  /**
  * Signs the supplied XML requests and appends that signature to the request.
  * @param strToSign       XML string to sign
  */
  public string function signXML( required string strToSign ) {
    try {
      /* ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~ */
      /* ~~ Signature creation: Step 1                                  ~~ */
      /* ~~ Is now done in a java file                                  ~~ */
      /* ~~ idealcrypto.class                                           ~~ */
      /* ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~ */
      var facObj = variables.idealcrypto.init();
      var fac = facObj.fac;
      var signedInfo = facObj.signedInfo;

      /* ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~ */
      /* ~~ Signature creation: Step 2                                  ~~ */
      /* ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~ */

      /* Load the KeyStore and get the signing key and certificate. */
      var ksfile = createObject( 'java', 'java.io.FileInputStream' ).init( variables.ksFile );
      var ks = createObject( 'java', 'java.security.KeyStore' ).getInstance( 'JKS' );
      ks.load( ksfile, variables.ksPassword.toCharArray() );
      var keyEntry = ks.getEntry(
        variables.ksAlias,
        createObject( 'java', 'java.security.KeyStore$PasswordProtection' ).init( variables.ksPassword.toCharArray() )
      );
      var cert = keyEntry.getCertificate();
      ksfile.close();

      /* Create the KeyInfo containing the X509Data. */
      var kif = fac.getKeyInfoFactory();
      var keyInfo = kif.newKeyInfo( [ kif.newKeyName( createSHA1Fingerprint( cert ) ) ] );

      /* ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~ */
      /* ~~ Signature creation: Step 3                                  ~~ */
      /* ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~ */

      /* Instantiate the document to be signed. */
      var dbf_i = createObject( 'java', 'javax.xml.parsers.DocumentBuilderFactory' ).newInstance();
      dbf_i.setNamespaceAware( true );
      var doc = dbf_i.newDocumentBuilder()
        .parse(
        createObject( 'java', 'org.xml.sax.InputSource' ).init( createObject( 'java', 'java.io.StringReader' ).init( strToSign ) )
      );

      /* Create a DOMSignContext and specify the RSA PrivateKey and location of
            the resulting XMLSignature's parent element. */
      var dsc = createObject( 'java', 'javax.xml.crypto.dsig.dom.DOMSignContext' ).init(
        keyEntry.getPrivateKey(),
        doc.getDocumentElement()
      );

      /* Create the XMLSignature, but don't sign it yet. */
      var signature = fac.newXMLSignature( signedInfo, keyInfo );

      /* Marshal, generate, and sign the enveloped signature. */
      signature.sign( dsc );

      /* ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~ */
      /* ~~ Signature creation: Step 4                                  ~~ */
      /* ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~ */
      /* Output the resulting document. */

      var stringWriter = createObject( 'java', 'java.io.StringWriter' ).init();
      var xmlResult = createObject( 'java', 'javax.xml.transform.stream.StreamResult' ).init( stringWriter );
      var ds = createObject( 'java', 'javax.xml.transform.dom.DOMSource' ).init( doc );
      var tf = createObject( 'java', 'javax.xml.transform.TransformerFactory' ).newInstance();
      var trans = tf.newTransformer();
      trans.transform( ds, xmlResult );

      return stringWriter.tostring();
    } catch ( any cfcatch ) {
      return handleError( cfcatch );
    }
  }

  /**
  * Returns the fingerprint of the certificate set in the config file.
  */
  public string function getFingerprint() {
    try {
      var jFileInputStream = createObject( 'java', 'java.io.FileInputStream' );
      var jKeyStore = createObject( 'java', 'java.security.KeyStore' );
      var jPasswordProtection = createObject( 'java', 'java.security.KeyStore$PasswordProtection' );

      var ks = jKeyStore.getInstance( 'JKS' );
      ks.load( jFileInputStream.init( variables.ksFile ), variables.ksPassword.toCharArray() );

      var keyEntry = ks.getEntry( variables.ksAlias, jPasswordProtection.init( variables.ksPassword.toCharArray() ) );

      return createSHA1Fingerprint( keyEntry.getCertificate() );
    } catch ( any cfcatch ) {
      return handleError( cfcatch );
    }
  }

  // PRAVIATE METHODS BELOW:

  /**
  * Global error handler
  * @param error           Struct containing the thrown error
  */
  private Void function handleError( any error ) {
    param name="error.message" default="";
    param name="error.detail" default="";
    param name="error.errorCode" default="";
    param name="error.extendedInfo" default="";

    savecontent variable="local.errorDump" {
      writeDump( error );
    }

    /* Display the error if the client IP is on the debugger list */
    if ( listFind( variables.debugIp, cgi.remote_addr ) ) {
      // getpagecontext().getcfoutput().clearall();
      if ( structKeyExists( error, 'extendedInfo' ) && len( trim( error.extendedInfo ) ) ) {
        writeOutput( error.extendedInfo );
      }

      writeOutput( local.errorDump );
      abort;
    }

    writeLog( text = '#error.message#, #error.detail#', type = 'Error', file = variables.debugLog );

    var debugemail = variables.debugEmail;
    if ( isDefined( 'debugemail' ) ) {
      var mailService =new mail();
      mailService.setTo( debugemail );
      mailService.setFrom( debugemail );
      mailService.setType( 'HTML' );
      mailService.setSubject( 'iDEAL Error: #error.message#' );
      mailService.setBody( local.errorDump );
      mailService.send();
    }
    throw(
      type = 'nl.mingo.ideal.handleError',
      errorCode = '#error.errorCode#',
      message = '#error.message#',
      detail = '#error.detail#',
      extendedInfo = '#error.extendedInfo#'
    );
  }

  /**
  * @param requestType     The type of ideal request, see docs.
  */
  private string function postRequest( required string requestType ) {
    try {
      var xmlstring = '<?xml version="1.0" encoding="UTF-8"?>';

      variables.timestamp = getFormattedTimestamp();

      switch ( requestType ) {
        case 'Directory':
          xmlstring &= '<DirectoryReq xmlns="http://www.idealdesk.com/ideal/messages/mer-acq/3.3.1" xmlns:ns2="http://www.w3.org/2000/09/xmldsig##" version="3.3.1">'
          & '<createDateTimestamp>#variables.timestamp#</createDateTimestamp>'
          & '<Merchant>'
          & '<merchantID>#variables.merchantId#</merchantID>'
          & '<subID>#variables.subId#</subID>'
          & '</Merchant>'
          & '</DirectoryReq>';
          break;
        case 'Transaction':
          variables.entranceCode = variables.purchaseId;
          variables.description = right( variables.description, 32 );

          xmlstring &= '<AcquirerTrxReq xmlns="http://www.idealdesk.com/ideal/messages/mer-acq/3.3.1" version="3.3.1">'
          & '<createDateTimestamp>#variables.timestamp#</createDateTimestamp>'
          & '<Issuer>'
          & '<issuerID>#variables.issuerId#</issuerID>'
          & '</Issuer>'
          & '<Merchant>'
          & '<merchantID>#variables.merchantId#</merchantID>'
          & '<subID>#variables.subId#</subID>'
          & '<merchantReturnURL>#xmlFormat( variables.merchantReturnUrl )#</merchantReturnURL>'
          & '</Merchant>'
          & '<Transaction>'
          & '<purchaseID>#variables.purchaseId#</purchaseID>'
          & '<amount>#variables.amount#</amount>'
          & '<currency>#variables.currency#</currency>';

          if ( len( variables.expirationPeriod ) ) {
            xmlstring &= '<expirationPeriod>#variables.expirationPeriod#</expirationPeriod>';
          }

          xmlstring &= '<language>#variables.language#</language>'
          & '<description>#xmlFormat( variables.description )#</description>';

          if ( len( variables.entranceCode ) ) {
            xmlstring &= '<entranceCode>#xmlFormat( variables.entranceCode )#</entranceCode>';
          }

          xmlstring &= '</Transaction>'
          & '</AcquirerTrxReq>';
          break;
        case 'Status':
          xmlstring &= '<AcquirerStatusReq xmlns="http://www.idealdesk.com/ideal/messages/mer-acq/3.3.1" version="3.3.1">'
          & '<createDateTimestamp>#variables.timestamp#</createDateTimestamp>'
          & '<Merchant>'
          & '<merchantID>#variables.merchantId#</merchantID>'
          & '<subID>#variables.subId#</subID>'
          & '</Merchant>'
          & '<Transaction>'
          & '<transactionID>#variables.transactionId#</transactionID>'
          & '</Transaction>'
          & '</AcquirerStatusReq>';
          break;
      }

      var singedXML = signXML( xmlstring );
      var xmlRequest = xmlParse( singedXML );
      var httpService =new http();

      httpService.setURL( variables.idealUrl );
      httpService.setMethod( 'post' );
      httpService.setCharset( 'utf-8' );
      httpService.addParam( type = 'header', name = 'content-type', value = 'text/xml; charset="utf-8"' );
      httpService.addParam( type = 'header', name = 'content-length', value = len( xmlRequest ) );
      httpService.addParam( type = 'XML', value = xmlRequest );

      var objSecurity = createObject( 'java', 'java.security.Security' );
      var storeProvider = objSecurity.getProvider( 'JsafeJCE' );

      if ( !isNull( storeProvider ) ) {
        var dhKeyAgreement = storeProvider.getProperty( 'KeyAgreement.DiffieHellman' );
        storeProvider.remove( 'KeyAgreement.DiffieHellman' );
      }

      var httpRequest = httpService.send().getPrefix();

      if ( !isNull( storeProvider ) ) {
        storeProvider.put( 'KeyAgreement.DiffieHellman', dhKeyAgreement );
      }

      if ( !isXML( httpRequest.fileContent ) ) {
        throw( type = 'nl.mingo.ideal.postRequest', message = '#httpRequest.fileContent#', detail = '#httpRequest.ErrorDetail#' );
      }

      var result = xmlParse( httpRequest.fileContent );

      /* Error logging */
      if ( structKeyExists( result, 'AcquirerErrorRes' ) ) {
        var errorFileContent = htmlEditFormat( indentXml( httpRequest.fileContent ) );
        throw(
          type = 'nl.mingo.ideal.postRequest',
          message = '#result.AcquirerErrorRes.Error.errorMessage.xmlText#',
          detail = '#result.AcquirerErrorRes.Error.errorDetail.xmlText#',
          errorCode = '#result.AcquirerErrorRes.Error.errorCode.xmlText#',
          extendedInfo = '<table><tr><td valign="top"><pre>#htmlEditFormat( indentXml( singedXML ) )#</pre></td><td valign="top"><pre>#errorFileContent#</pre></td></tr></table>'
        );
      }

      return result;
    } catch ( any cfcatch ) {
      return handleError( cfcatch );
    }
  }

  /**
  * Returns the timestamp property properly formatted (YYYY-mm-ddTHH:mm:ssZ)
  */
  private string function getFormattedTimestamp() {
    try {
      var ts = dateConvert( 'local2utc', now() );
      return dateFormat( ts, 'yyyy-mm-dd' ) & 'T' & timeFormat( ts, 'HH:mm:ss.l' ) & 'Z';
    } catch ( any cfcatch ) {
      return handleError( cfcatch );
    }
  }

  /**
  * Returns a SHA-1 fingerprint of the supplied certificate.
  */
  private string function createSHA1Fingerprint( required any cert ) {
    try {
      var sha1Md = createObject( 'java', 'java.security.MessageDigest' ).getInstance( 'SHA-1' );
      sha1Md.update( cert.getEncoded() );

      return uCase( binaryEncode( sha1Md.digest(), 'hex' ) );
    } catch ( any cfcatch ) {
      return handleError( cfcatch );
    }
  }

  /**
  * indentXml pretty-prints XML and XML-like markup without requiring valid XML.
  * @param   xml           string to format.
  * @param   indent        The string to use for indenting
  * @author  Barney Boisvert
  * @version 2, July 30, 2010
  * @version 3, April 28, 2015 Mingo Hagen
  */
  private string function indentXml( required string xml, string indent = '  ' ) {
    try {
      var lines = [];
      var depth = 0;
      var line = '';
      var isCDATAStart = false;
      var isCDATAEnd = false;
      var isEndTag = false;
      var isSelfClose = false;

      xml = trim( reReplace( xml, '(^|>)\s*(<|$)', '\1#chr( 10 )#\2', 'all' ) );
      lines = listToArray( xml, chr( 10 ) );

      for ( var i = 1; i lte arrayLen( lines ); i++ ) {
        line = trim( lines[ i ] );
        isCDATAStart = left( line, 9 ) EQ '<![CDATA[';
        isCDATAEnd = right( line, 3 ) EQ ']]>';

        if ( !isCDATAStart && !isCDATAEnd && left( line, 1 ) EQ '<' && right( line, 1 ) EQ '>' ) {
          isEndTag = left( line, 2 ) EQ '</';
          isSelfClose = right( line, 2 ) EQ '/>' OR reFindNoCase( '<([a-z0-9_-]*).*</\1>', line );

          if ( isEndTag ) {
            /* use max for safety against multi-line open tags */
            depth = max( 0, depth - 1 );
          }

          lines[ i ] = repeatString( indent, depth ) & line;

          if ( !isEndTag && !isSelfClose ) {
            depth = depth + 1;
          }
        } else if ( isCDATAStart ) {
          /*
            we don't indent CDATA ends, because that would change the
            content of the CDATA, which isn't desirable
          */
          lines[ i ] = repeatString( indent, depth ) & line;
        }
      }

      return arrayToList( lines, chr( 10 ) );
    } catch ( any cfcatch ) {
      return handleError( cfcatch );
    }
  }

  /**
  * null function: Provides CFML with a null value which is needed for some
  *  java interaction
  */
  private void function nil() {
  }
}