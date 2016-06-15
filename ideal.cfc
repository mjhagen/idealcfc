component accessors=true hint="See https://github.com/mjhagen/idealcfc for implementation help." {
  property type="date"    name="timestamp";
  property type="numeric" name="amount";
  property type="numeric" name="merchantID";
  property type="numeric" name="purchaseID"                                     hint="Order ID";
  property type="numeric" name="subID"              default=0;
  property type="string"  name="cacheName"          default="ideal-cache"                hint="ideal.cfc is cached per application";
  property type="string"  name="currency"           default="EUR";
  property type="string"  name="debugEmail"         default="administrator@your-website-here.nl" required=false;
  property type="string"  name="debugIP"            default="::1,fe80:0:0:0:0:0:0:1%1,127.0.0.1" required=false;
  property type="string"  name="debugLog"           default="ideal-cfc" required=false;
  property type="string"  name="defaultCountry"     default="Nederland"             hint="Optional, set to country of website";
  property type="string"  name="description"                                    hint="NO HTML ALLOWED!";
  property type="string"  name="entranceCode"                                   hint="Session ID";
  property type="string"  name="expirationPeriod"                               hint="Optional, date period format: PnYnMnDTnHnMnS";
  property type="string"  name="idealURL"                               required=true;
  property type="string"  name="issuerID";
  property type="string"  name="ksAlias";
  property type="string"  name="ksFile";
  property type="string"  name="ksPassword";
  property type="string"  name="language"           default="nl";
  property type="string"  name="merchantReturnURL";
  property type="string"  name="transactionID"      default="";

  /**
   * Constructor method
   * @param config          Absolute path to the config file
   * @param initProperties  Properties to be set, for example:
   *                          init( initProperties={issuerID="12345"});
   */
  public ideal function init( string config="", struct initProperties={}) {
    try {
      lock name="lock_#application.applicationname#_init" timeout="5" type="exclusive" {
        if( !structKeyExists( application, getCacheName()) || structKeyExists( url, "reload" )) {
          application[ getCacheName()]={};
        }

        /* Optionally read config from a file, otherwise, just instantiate the cfc with your options as arguments */
        if( len( trim( config )) && fileExists( config )) {
          application[ getCacheName()].properties={};

          var configFile=fileRead( config, "utf-8" );

          for( var valuePair in listToArray( configFile, "#chr( 13 )##chr( 10 )#" )) {
            if( valuePair contains '<!---' ||
                valuePair contains '--->' ||
                valuePair contains '/*' ||
                valuePair contains '*/' ) {
              continue;
            }

            initProperties[ trim( listFirst( valuePair, ' #chr( 9 )#' ))]=trim( listRest( valuePair, ' #chr( 9 )#' ));
          }
        }
      }

      structAppend( variables, initProperties, true );

      param variables.ksFile="";

      if( left( variables.ksFile, 1 ) == "." ) {
        variables.ksFile = expandPath( variables.ksFile );
      }

      if( !fileExists( variables.ksFile )) {
        throw( type="nl.mingo.ideal.init", message="Missing keystore file" );
      }

      return this;
    } catch( any cfcatch ) {
      return handleError( cfcatch );
    }
  }

  /**
   * Method to generate a <select /> with a list of participating banks
   * @param class           CSS class name(s)
   * @param firstOption     Text on the first option
   * @param css             Inline CSS
   */
  public string function directoryRequest( string class="", string firstOption="Kies uw bank:", string css="margin-bottom:10px;" ) {
    try {
      var drCacheName="DR_#dateFormat( now(), 'yyyymmdd' )#";
      var issuerXML="";
      var issuerList="";
      var result="";

      // Per ideal request, this is cached for the duration of the application's life.
      if( !structKeyExists( application[ getCacheName()], drCacheName )) {
        var issuersXML=postRequest( "Directory" );
        var issuers={};
        var issuerLists=issuersXML.DirectoryRes.Directory;

        if( structKeyExists( issuersXML.DirectoryRes.Directory, "Country" )) {
          issuerLists=issuersXML.DirectoryRes.Directory.Country;
        }

        for( var issuerXML in issuerLists.xmlChildren ) {
          if( issuerXML.xmlName eq "countryNames" ) {
            issuerList=issuerXML.xmlText;
          }

          if( issuerXML.xmlName neq "Issuer" ) {
            continue;
          }

          if( !structKeyExists( issuers, issuerList )) {
            issuers[issuerList]=[];
          }

          arrayAppend( issuers[issuerList], {
            "id"=issuerXML.xmlChildren[1].xmlText,
            "name"=issuerXML.xmlChildren[2].xmlText
          });
        }

        application[ getCacheName()][drCacheName]=issuers;
      }

      issuers=application[ getCacheName()][drCacheName];
      var issuerKeyList=listSort( structKeyList( issuers ), 'text' );

      if( len( getDefaultCountry())) {
        if( listFindNoCase( issuerKeyList, getDefaultCountry())) {
          issuerKeyList=listDeleteAt( issuerKeyList, listFindNoCase( issuerKeyList, getDefaultCountry()));
        }
        issuerKeyList=listPrepend( issuerKeyList, getDefaultCountry());
      }

      result &='<select name="issuerID" id="issuerID" style="#css#" class="#class#">';
      result &='<option value="">#firstOption#</option>';

      for( var key in issuerKeyList ) {
        if( !structKeyExists( issuers, key )) {
          continue;
        }

        result &='<optgroup label="#key#">';

        for( var issuer in issuers[key] ) {
          result &='<option value="#issuer.id#">#issuer.name#</option>';
        }

        result &='</optgroup>';
      }

      result &='</select>';

      return result;
    } catch( any cfcatch ) {
      return handleError( cfcatch );
    }
  }

  /**
   * @param redirect        If you need to do more processing before being
   *                          redirected, set this to false.
   */
  public string function transactionRequest( boolean redirect=true ) {
    try {
      var transactionXML=postRequest( "Transaction" );

      if( redirect ) {
        location( url=transactionXML.AcquirerTrxRes.Issuer.issuerAuthenticationURL.xmlText,
                  addToken=false );
      }

      setTransactionID( transactionXML.AcquirerTrxRes.Transaction.transactionID.XmlText );

      return transactionXML.AcquirerTrxRes.Issuer.issuerAuthenticationURL.xmlText;
    } catch( any cfcatch ) {
      return handleError( cfcatch );
    }
  }

  /**
   * Returns the status of the current order being processed by ideal
   */
  public string function statusRequest() {
    try {
      return postRequest( "Status" );
    } catch( any cfcatch ) {
      return handleError( cfcatch );
    }
  }

  /**
   * Signs the supplied XML requests and appends that signature to the request.
   * @param strToSign       XML string to sign
   */
  public string function signXML( required string strToSign ) {
    try {
      var XMLSignatureFactory=createObject( "java", "javax.xml.crypto.dsig.XMLSignatureFactory" );
      var DigestMethod=createObject( "java", "javax.xml.crypto.dsig.DigestMethod" );
      var TransformService=createObject( "java", "javax.xml.crypto.dsig.TransformService" );
      var DOMTransform=createObject( "java", "org.jcp.xml.dsig.internal.dom.DOMTransform" );
      var DocumentBuilderFactory=createObject( "java", "javax.xml.parsers.DocumentBuilderFactory" );
      var CanonicalizationMethod=createObject( "java", "javax.xml.crypto.dsig.CanonicalizationMethod" );
      var C14NMethodParameterSpec=createObject( "java", "javax.xml.crypto.dsig.spec.C14NMethodParameterSpec" );
      var InputSource=createObject( "java", "org.xml.sax.InputSource" );
      var stringReader=createObject( "java", "java.io.StringReader" );
      var PKCS8EncodedKeySpec=createObject( "java", "java.security.spec.PKCS8EncodedKeySpec" );
      var KeyFactory=createObject( "java", "java.security.KeyFactory" ).getInstance( "RSA" );
      var DOMSignContext=createObject( "java", "javax.xml.crypto.dsig.dom.DOMSignContext" );
      var DOMSource=createObject( "java", "javax.xml.transform.dom.DOMSource" );
      var TransformerFactory=createObject( "java", "javax.xml.transform.TransformerFactory" );
      var Transformer=createObject( "java", "javax.xml.transform.Transformer" );
      var stringWriter=createObject( "java", "java.io.StringWriter" ).init();
      var StreamResult=createObject( "java", "javax.xml.transform.stream.StreamResult" );
      var DOMstructure=createObject( "java", "javax.xml.crypto.dom.DOMStructure" );
      var KeyStore=createObject( "java", "java.security.KeyStore" );
      var PasswordProtection=createObject( "java", "java.security.KeyStore$PasswordProtection" ).init( getKSPassword().toCharArray());
      var FileInputStream=createObject( "java", "java.io.FileInputStream" );
      var Collections=createObject( "java", "java.util.Collections" );

      /* ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~ */
      /* ~~ Signature creation: Step 1                                  ~~ */
      /* ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~ */

      var SIGNATURE_REFERENCE_DIGEST_METHOD = DigestMethod.SHA256;
      var SIGNATURE_REFERENCE_TRANSFORM_MODE = "http://www.w3.org/2000/09/xmldsig##enveloped-signature";
      var SIGNATURE_REFERENCE_URI = "";
      var SIGNATURE_SIGNED_INFO_ALGORITHM = "http://www.w3.org/2001/04/xmldsig-more##rsa-sha256";
      var SIGNATURE_SIGNED_INFO_CANONICALIZATION_METHOD = CanonicalizationMethod.EXCLUSIVE;
      var fac = XMLSignatureFactory.getInstance( "DOM" );
      var digestMethod = fac.newDigestMethod( SIGNATURE_REFERENCE_DIGEST_METHOD, nil());
      var transformList = Collections.singletonList( fac.newTransform( SIGNATURE_REFERENCE_TRANSFORM_MODE, nil())); // (TransformParameterSpec)
      var ref = fac.newReference( SIGNATURE_REFERENCE_URI, digestMethod, transformList, nil(), nil());
      var method = fac.newSignatureMethod( SIGNATURE_SIGNED_INFO_ALGORITHM, nil());
      var canonicalizationMethod = fac.newCanonicalizationMethod( SIGNATURE_SIGNED_INFO_CANONICALIZATION_METHOD, nil());
      var signedInfo = fac.newSignedInfo( canonicalizationMethod, method, Collections.singletonList( ref ));

      /* ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~ */
      /* ~~ Signature creation: Step 2                                  ~~ */
      /* ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~ */

      /* Load the KeyStore and get the signing key and certificate. */
      var ksfile=FileInputStream.init( getKSFile());
      var ks=KeyStore.getInstance( "JKS" );
      ks.load( ksfile, getKSPassword().toCharArray());
      var keyEntry=ks.getEntry( getKSAlias(), PasswordProtection );
      var cert=keyEntry.getCertificate();
      ksfile.close();

      /* Create the KeyInfo containing the X509Data. */
      var kif=fac.getKeyInfoFactory();
      var keyInfo=kif.newKeyInfo([kif.newKeyName( createSHA1Fingerprint( cert ))]);

      /* ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~ */
      /* ~~ Signature creation: Step 3                                  ~~ */
      /* ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~ */

      /* Instantiate the document to be signed. */
      var dbf_i=DocumentBuilderFactory.newInstance();
      dbf_i.setNamespaceAware( true );
      var doc=dbf_i.newDocumentBuilder().parse( InputSource.init( stringReader.init( strToSign )));

      /* Create a DOMSignContext and specify the RSA PrivateKey and location of
            the resulting XMLSignature's parent element. */
      var dsc=DOMSignContext.init( keyEntry.getPrivateKey(), doc.getDocumentElement());

      /* Create the XMLSignature, but don't sign it yet. */
      var signature=fac.newXMLSignature( signedInfo, keyInfo );

      /* Marshal, generate, and sign the enveloped signature. */
      signature.sign( dsc );

      /* ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~ */
      /* ~~ Signature creation: Step 4                                  ~~ */
      /* ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~ */
      /* Output the resulting document. */

      var xmlResult=StreamResult.init( stringWriter );
      var ds=DOMSource.init( doc );
      var tf=TransformerFactory.newInstance();
      var trans=tf.newTransformer();
      trans.transform( ds, xmlResult );

      return stringWriter.tostring();
    } catch( any cfcatch ) {
      return handleError( cfcatch );
    }
  }

  /**
   * Returns the fingerprint of the certificate set in the config file.
   */
  public string function getFingerprint() {
    try {
      var jFileInputStream=createObject( "java", "java.io.FileInputStream" );
      var jKeyStore=createObject( "java", "java.security.KeyStore" );
      var jPasswordProtection=createObject( "java", "java.security.KeyStore$PasswordProtection" );

      var ks=jKeyStore.getInstance( "JKS" );
      ks.load( jFileInputStream.init( getKSFile()), getKSPassword().toCharArray());

      var keyEntry=ks.getEntry( getKSAlias(), jPasswordProtection.init( getKSPassword().toCharArray()));

      return createSHA1Fingerprint( keyEntry.getCertificate());
    } catch( any cfcatch ) {
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
    if( listFind( getDebugIP(), cgi.remote_addr )) {
      // getpagecontext().getcfoutput().clearall();
      if( structKeyExists( error, "extendedInfo" ) && len( trim( error.extendedInfo ))) {
        writeOutput( error.extendedInfo );
      }

      writeOutput( local.errorDump );
      abort;
    }

    writeLog( text="#error.message#, #error.detail#",
              type="Error",
              file=getDebugLog());

    var mailService=new mail();
        mailService.setTo( getDebugEmail());
        mailService.setFrom( getDebugEmail());
        mailService.setType( "HTML" );
        mailService.setSubject( "iDEAL Error: #error.message#" );
        mailService.setBody( local.errorDump );
        mailService.send();

    throw( type="nl.mingo.ideal.handleError",
           errorCode="#error.errorCode#",
           message="#error.message#",
           detail="#error.detail#",
           extendedInfo="#error.extendedInfo#" );
  }

  /**
   * @param requestType     The type of ideal request, see docs.
   */
  private string function postRequest( required string requestType ) {
    try {
      var xmlstring='<?xml version="1.0" encoding="UTF-8"?>';

      setTimestamp( now());

      switch( requestType ) {
        case "Directory":
          xmlstring &='<DirectoryReq xmlns="http://www.idealdesk.com/ideal/messages/mer-acq/3.3.1" xmlns:ns2="http://www.w3.org/2000/09/xmldsig##" version="3.3.1">'
                    & '<createDateTimestamp>#getFormattedTimestamp()#</createDateTimestamp>'
                    & '<Merchant>'
                    & '<merchantID>#getMerchantID()#</merchantID>'
                    & '<subID>#getSubID()#</subID>'
                    & '</Merchant>'
                    & '</DirectoryReq>';
          break;
        case "Transaction":
          setEntranceCode( getPurchaseID());
          setDescription( right( getDescription(), 32 ));

          xmlstring &='<AcquirerTrxReq xmlns="http://www.idealdesk.com/ideal/messages/mer-acq/3.3.1" version="3.3.1">'
                    & '<createDateTimestamp>#getFormattedTimestamp()#</createDateTimestamp>'
                    & '<Issuer>'
                    & '<issuerID>#getIssuerID()#</issuerID>'
                    & '</Issuer>'
                    & '<Merchant>'
                    & '<merchantID>#getMerchantID()#</merchantID>'
                    & '<subID>#getSubID()#</subID>'
                    & '<merchantReturnURL>#xmlFormat( getMerchantReturnURL())#</merchantReturnURL>'
                    & '</Merchant>'
                    & '<Transaction>'
                    & '<purchaseID>#getPurchaseID()#</purchaseID>'
                    & '<amount>#getAmount()#</amount>'
                    & '<currency>#getCurrency()#</currency>';

          if( len( getExpirationPeriod())) {
            xmlstring &='<expirationPeriod>#getExpirationPeriod()#</expirationPeriod>';
          }

          xmlstring &='<language>#getLanguage()#</language>'
                    & '<description>#xmlFormat( getDescription())#</description>';

          if( len( getEntranceCode())) {
            xmlstring &='<entranceCode>#xmlFormat( getEntranceCode())#</entranceCode>';
          }

          xmlstring &='</Transaction>'
                    & '</AcquirerTrxReq>';
          break;
        case "Status":
          xmlstring &='<AcquirerStatusReq xmlns="http://www.idealdesk.com/ideal/messages/mer-acq/3.3.1" version="3.3.1">'
                    & '<createDateTimestamp>#getFormattedTimestamp()#</createDateTimestamp>'
                    & '<Merchant>'
                    & '<merchantID>#getMerchantID()#</merchantID>'
                    & '<subID>#getSubID()#</subID>'
                    & '</Merchant>'
                    & '<Transaction>'
                    & '<transactionID>#getTransactionID()#</transactionID>'
                    & '</Transaction>'
                    & '</AcquirerStatusReq>';
          break;
      }

      var singedXML=signXML( xmlstring );
      var xmlRequest=xmlParse( singedXML );
      var httpService=new http();

      httpService.setURL( getIdealURL());
      httpService.setMethod( "post" );
      httpService.setCharset( "utf-8" );
      httpService.addParam( type="header", name="content-type", value='text/xml; charset="utf-8"' );
      httpService.addParam( type="header", name="content-length", value=len( xmlRequest ));
      httpService.addParam( type="XML", value=xmlRequest );

      var httpRequest=httpService.send().getPrefix();

      if( !isXML( httpRequest.fileContent )) {
        throw(  type="nl.mingo.ideal.postRequest",
                message="#httpRequest.fileContent#",
                detail="#httpRequest.ErrorDetail#" );
      }

      var result=xmlParse( httpRequest.fileContent );

      /* Error logging */
      if( structKeyExists( result, "AcquirerErrorRes" )) {
        throw(  type="nl.mingo.ideal.postRequest",
                message="#result.AcquirerErrorRes.Error.errorMessage.xmlText#",
                detail="#result.AcquirerErrorRes.Error.errorDetail.xmlText#",
                errorCode="#result.AcquirerErrorRes.Error.errorCode.xmlText#",
                extendedInfo='<table><tr><td valign="top"><pre>#htmlEditFormat( indentXml( singedXML ))#</pre></td><td valign="top"><pre>#htmlEditFormat( indentXml( httpRequest.fileContent ))#</pre></td></tr></table>' );
      }

      return result;
    } catch( any cfcatch ) {
      return handleError( cfcatch );
    }
  }

  /**
   * Returns the timestamp property properly formatted (YYYY-mm-ddTHH:mm:ssZ)
   */
  private string function getFormattedTimestamp() {
    try {
      var timestamp=dateConvert( "local2utc", getTimestamp());
      return dateFormat( timestamp, "yyyy-mm-dd" ) & "T" & timeFormat( timestamp, "HH:mm:ss.l" ) & "Z";
    } catch( any cfcatch ) {
      return handleError( cfcatch );
    }
  }

  /**
   * Returns a SHA-1 fingerprint of the supplied certificate.
   */
  private string function createSHA1Fingerprint( required any cert ) {
    try {
      var sha1Md=createObject( "java", "java.security.MessageDigest" ).getInstance( "SHA-1" );
      sha1Md.update( cert.getEncoded());

      return uCase( binaryEncode( sha1Md.digest(), 'hex' ));
    } catch( any cfcatch ) {
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
  private string function indentXml( required string xml, string indent="  " ) {
    try {
      var lines=[];
      var depth=0;
      var line="";
      var isCDATAStart=false;
      var isCDATAEnd=false;
      var isEndTag=false;
      var isSelfClose=false;

      xml=trim( REReplace( xml, "(^|>)\s*(<|$)", "\1#chr(10)#\2", "all" ));
      lines=listToArray( xml, chr( 10 ));

      for( var i=1; i lte arrayLen( lines ); i++ ) {
        line=trim( lines[i]);
        isCDATAStart=left( line, 9 ) EQ "<![CDATA[";
        isCDATAEnd=right( line, 3 ) EQ "]]>";

        if( !isCDATAStart && !isCDATAEnd && left( line, 1 ) EQ "<" && right( line, 1 ) EQ ">" ) {
          isEndTag=left( line, 2 ) EQ "</";
          isSelfClose=right( line, 2 ) EQ "/>" OR REFindNoCase( "<([a-z0-9_-]*).*</\1>", line );

          if( isEndTag ) {
            /* use max for safety against multi-line open tags */
            depth=max( 0, depth-1 );
          }

          lines[i]=repeatstring( indent, depth ) & line;

          if( !isEndTag && !isSelfClose ) {
            depth=depth + 1;
          }
        } else if( isCDATAStart ) {
          /*
            we don't indent CDATA ends, because that would change the
            content of the CDATA, which isn't desirable
          */
          lines[i]=repeatstring( indent, depth ) & line;
        }
      }

      return arrayToList( lines, chr( 10 ));
    } catch( any cfcatch ) {
      return handleError( cfcatch );
    }
  }

  /**
   * null function: Provides CFML with a null value which is needed for some
   *  java interaction
   */
  private void function nil(){}
}