component accessors=true
          persistent=true
          hint="See https://github.com/mjhagen/idealcfc for implementation help."
{
  property name="timestamp" type="date";
  property name="issuerID" type="String";
  property name="merchantID" type="numeric";
  property name="subID" type="numeric" default="0";
  property name="purchaseID" type="numeric"                                     hint="Order ID";
  property name="transactionID" type="String" default="";
  property name="amount" type="numeric";
  property name="currency" type="String" default="EUR";
  property name="language" type="String" default="nl";
  property name="description" type="String"                                     hint="NO HTML ALLOWED!";
  property name="entranceCode" type="String"                                    hint="Session ID";
  property name="expirationPeriod" type="String"                                hint="Optional, date period format: PnYnMnDTnHnMnS";
  property name="defaultCountry" type="String"  default="Nederland"             hint="Optional, set to country of website";
  property name="merchantReturnURL" type="String";
  property name="ksFile" type="String";
  property name="ksAlias" type="String";
  property name="ksPassword" type="String";
  property name="idealURL" required="yes" type="String";
  property name="debugIP" type="String" default="::1,fe80:0:0:0:0:0:0:1%1,127.0.0.1" required=false;
  property name="debugEmail" type="String" default="administrator@your-website-here.nl" required=false;
  property name="debugLog" type="String" default="ideal-cfc" required=false;

  // ideal.cfc is cached per application.
  variables.cacheName="cache";

  // idealcrypto.class is dynamically compiled, but only once per server.
  if( not structKeyExists( server, 'idealcrypto' ))
  {
    variables.pwd=getDirectoryFromPath( GetCurrentTemplatePath());
    variables.jl=new javaloader.JavaLoader( sourceDirectories=[ '#variables.pwd#\..\java' ]);
    variables.idealcrypto=jl.create( 'idealcrypto' );
    server.idealcrypto=variables.idealcrypto;
  }
  variables.idealcrypto=server.idealcrypto;

  /* ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~ */
  /**
   * ConStructor method
   * @param config          String    absolute path to the config file
   * @param initProperties  Struct    properties to be set, for example: init( "config", { issuerID="12345" });
   */
  public ideal function init( String config="", Struct initProperties={} )
  {
    try
    {
      var tempfunc="";

      lock  name="lock_#application.applicationname#_init"
            timeout="5"
            type="exclusive"
      {
        if( not structKeyExists( application, variables.cacheName) or structKeyExists( url, "reload" ))
        {
          application[variables.cacheName]={};
        }

        /* Optionally read config from a file, otherwise, just instantiate the cfc with your options as arguments */
        if( len( trim( config )) and fileExists( config ))
        {
          application[variables.cacheName].properties={};

          local.config=fileRead( config );

          for( valuePair in listToArray( local.config, "#chr( 13 )##chr( 10 )#" ))
          {
            if(
                valuePair contains '<!---' or
                valuePair contains '--->' or
                valuePair contains '/*' or
                valuePair contains '*/'
              )
            {
              continue;
            }

            initProperties[trim( listFirst( valuePair, ' #chr( 9 )#' ))]=trim( listRest( valuePair, ' #chr( 9 )#' ));
          }
        }
      }

      for( var key in initProperties )
      {
        tempfunc=this["set#key#"];
        tempfunc( initProperties[key] );
      }

      if( not fileExists( getKSFile()))
      {
        throw( message="Missing keystore file (#getKSFile()#)" );
      }

      return this;
    }
    catch( Any cfcatch )
    {
      return handleError( cfcatch );
    }
  }

  /* ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~ */
  /**
   * Method to generate a <select /> with a list of participating banks
   * @param calss           String    CSS class name(s)
   */
  public Void function directoryRequest( String class="" )
  {
    try
    {
      var cacheName="DR_#dateFormat( now(), 'yyyymmdd' )#";
      var issuerXML="";
      var issuerList="";
      var result="";

      // Per ideal request, this is cached for the duration of the application's life.
      if( not structKeyExists( application[variables.cacheName], cacheName ))
      {
        var issuersXML=postRequest( "Directory" );
        var issuers={};
        var issuerLists=issuersXML.DirectoryRes.Directory;

        if( structKeyExists( issuersXML.DirectoryRes.Directory, "Country" ))
        {
          issuerLists=issuersXML.DirectoryRes.Directory.Country;
        }

        for( var issuerXML in issuerLists.xmlChildren )
        {
          if( issuerXML.xmlName eq "countryNames" )
          {
            issuerList=issuerXML.xmlText;
          }

          if( issuerXML.xmlName neq "Issuer" )
          {
            continue;
          }

          if( not structKeyExists( issuers, issuerList ))
          {
            issuers[issuerList]=[];
          }

          arrayAppend( issuers[issuerList], {
            "id"=issuerXML.xmlChildren[1].xmlText,
            "name"=issuerXML.xmlChildren[2].xmlText
          });
        }

        application[variables.cacheName][cacheName]=issuers;
      }

      issuers=application[variables.cacheName][cacheName];
      var issuerKeyList=listSort( structKeyList( issuers ), 'text' );

      if( len( getDefaultCountry()))
      {
        if( listFindNoCase( issuerKeyList, getDefaultCountry()))
        {
          issuerKeyList=listDeleteAt( issuerKeyList, listFindNoCase( issuerKeyList, getDefaultCountry()));
        }
        issuerKeyList=listPrepend( issuerKeyList, getDefaultCountry());
      }

      result &='<select name="issuerID" id="issuerID" style="margin-bottom:10px;" class="#class#">';
      result &='<option value="">Kies uw bank:</option>';

      for( var key in issuerKeyList )
      {
        if( not structKeyExists( issuers, key ))
        {
          continue;
        }

        result &='<optgroup label="#key#">';

        for( var issuer in issuers[key] )
        {
          result &='<option value="#issuer.id#">#issuer.name#</option>';
        }

        result &='</optgroup>';
      }

      result &='</select>';

      return result;
    }
    catch( Any cfcatch )
    {
      return handleError( cfcatch );
    }
  }

  /* ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~ */
  /**
   * @param redirect        boolean   if you need to do more processing before
   *                                  being redirected, set this to false.
   */
  public Void function transactionRequest( boolean redirect=true )
  {
    try
    {
      var transactionXML=postRequest( "Transaction" );

      if( redirect )
      {
        location( url=transactionXML.AcquirerTrxRes.Issuer.issuerAuthenticationURL.xmlText,
                  addToken=false );
      }

      setTransactionID( transactionXML.AcquirerTrxRes.Transaction.transactionID.XmlText );

      return transactionXML.AcquirerTrxRes.Issuer.issuerAuthenticationURL.xmlText;
    }
    catch( Any cfcatch )
    {
      return handleError( cfcatch );
    }
  }

  /* ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~ */
  /**
   * @return  Returns the status of the current order being processed by ideal
   */
  public Void function statusRequest()
  {
    try
    {
      return postRequest( "Status" );
    }
    catch( Any cfcatch )
    {
      return handleError( cfcatch );
    }
  }

  /* ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~ */
  /**
   * Signs the supplied XML requests and appends that signature to the request.
   * @param   strToSign   String  XML String to sign
   * @return              String  Signed XML (including the signature)
   */
  public String function signXML( required String strToSign )
  {
    try
    {
      var XMLSignatureFactory=createObject( "java", "javax.xml.crypto.dsig.XMLSignatureFactory" );
      var DigestMethod=createObject( "java", "javax.xml.crypto.dsig.DigestMethod" );
      var TransformService=createObject( "java", "javax.xml.crypto.dsig.TransformService" );
      var DOMTransform=createObject( "java", "org.jcp.xml.dsig.internal.dom.DOMTransform" );
      var DocumentBuilderFactory=createObject( "java", "javax.xml.parsers.DocumentBuilderFactory" );
      var CanonicalizationMethod=createObject( "java", "javax.xml.crypto.dsig.CanonicalizationMethod" );
      var C14NMethodParameterSpec=createObject( "java", "javax.xml.crypto.dsig.spec.C14NMethodParameterSpec" );
      var InputSource=createObject( "java", "org.xml.sax.InputSource" );
      var StringReader=createObject( "java", "java.io.StringReader" );
      var PKCS8EncodedKeySpec=createObject( "java", "java.security.spec.PKCS8EncodedKeySpec" );
      var KeyFactory=createObject( "java", "java.security.KeyFactory" ).getInstance( "RSA" );
      var DOMSignContext=createObject( "java", "javax.xml.crypto.dsig.dom.DOMSignContext" );
      var DOMSource=createObject( "java", "javax.xml.transform.dom.DOMSource" );
      var TransformerFactory=createObject( "java", "javax.xml.transform.TransformerFactory" );
      var Transformer=createObject( "java", "javax.xml.transform.Transformer" );
      var StringWriter=createObject( "java", "java.io.StringWriter" ).init();
      var StreamResult=createObject( "java", "javax.xml.transform.stream.StreamResult" );
      var DOMStructure=createObject( "java", "javax.xml.crypto.dom.DOMStructure" );
      var KeyStore=createObject( "java", "java.security.KeyStore" );
      var PasswordProtection=createObject( "java", "java.security.KeyStore$PasswordProtection" ).init( getKSPassword().toCharArray());
      var FileInputStream=createObject( "java", "java.io.FileInputStream" );

      /* ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~ */
      /* ~~ Signature creation: Step 1                                  ~~ */
      /* ~~ Is now done in a java file compiled at runtime              ~~ */
      /* ~~ idealcrypto.class                                           ~~ */
      /* ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~ */
      var facObj=variables.idealcrypto.init();
      var fac=facObj.fac;
      var signedInfo=facObj.signedInfo;

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
      var doc=dbf_i.newDocumentBuilder().parse( InputSource.init( StringReader.init( strToSign )));

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

      var xmlResult=StreamResult.init( StringWriter );
      var ds=DOMSource.init( doc );
      var tf=TransformerFactory.newInstance();
      var trans=tf.newTransformer();
      trans.transform( ds, xmlResult );

      return StringWriter.toString();
    }
    catch( Any cfcatch )
    {
      return handleError( cfcatch );
    }
  }

  /* ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~ */
  /**
   * @return  String  Returns the fingerprint of the certificate set in the config file.
   */
  public String function getFingerprint()
  {
    try
    {
      var jFileInputStream=createObject( "java", "java.io.FileInputStream" );
      var jKeyStore=createObject( "java", "java.security.KeyStore" );
      var jPasswordProtection=createObject( "java", "java.security.KeyStore$PasswordProtection" );

      var ks=jKeyStore.getInstance( "JKS" );
      ks.load( jFileInputStream.init( getKSFile()), getKSPassword().toCharArray());

      var keyEntry=ks.getEntry( getKSAlias(), jPasswordProtection.init( getKSPassword().toCharArray()));

      return createSHA1Fingerprint( keyEntry.getCertificate());
    }
    catch( Any cfcatch )
    {
      return handleError( cfcatch );
    }
  }




  // PRAVIATE METHODS BELOW:

  /* ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~ */
  /**
   * Global error handler
   * @param error           Any       Struct containing the thrown error
   */
  private Void function handleError( Any error )
  {
    param name="error.message" default="";
    param name="error.detail" default="";
    param name="error.errorCode" default="";
    param name="error.extendedInfo" default="";

    savecontent variable="local.errorDump"
    {
      writeDump( error );
    }

    /* Display the error if the client IP is on the debugger list */
    if( listFind( getDebugIP(), cgi.remote_addr ))
    {
      // getpagecontext().getcfoutput().clearall();
      if( structKeyExists( error, "extendedInfo" ) and len( trim( error.extendedInfo )))
      {
        writeOutput( error.extendedInfo );
      }

      writeOutput( local.errorDump );
      abort;
    }

    writeLog( text="#error.message#, #error.detail#",
              type="Error",
              file=getDebugLog());

    var mailService=new mail();
        mailService.setTo( getDebugEmail() );
        mailService.setFrom( getDebugEmail() );
        mailService.setType( "HTML" );
        mailService.setSubject( "iDEAL Error: #error.message#" );
        mailService.setBody( local.errorDump );
        mailService.send();

    throw(  errorCode="#error.errorCode#",
            message="#error.message#",
            detail="#error.detail#",
            extendedInfo="#error.extendedInfo#" );
  }

  /* ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~ */
  /**
   * @param   requestType   String
   */
  private String function postRequest( required String requestType )
  {
    try
    {
      var xmlString='<?xml version="1.0" encoding="UTF-8"?>';

      setTimestamp( now());

      switch( requestType )
      {
        case "Directory":
          xmlString &='<DirectoryReq xmlns="http://www.idealdesk.com/ideal/messages/mer-acq/3.3.1" xmlns:ns2="http://www.w3.org/2000/09/xmldsig##" version="3.3.1">';
          xmlString &='<createDateTimestamp>#getFormattedTimestamp()#</createDateTimestamp>';
          xmlString &='<Merchant>';
          xmlString &='<merchantID>#getMerchantID()#</merchantID>';
          xmlString &='<subID>#getSubID()#</subID>';
          xmlString &='</Merchant>';
          xmlString &='</DirectoryReq>';
        break;

        case "Transaction":
          setEntranceCode( getPurchaseID() );
          setDescription( right( getDescription(), 32 ));

          xmlString &='<AcquirerTrxReq xmlns="http://www.idealdesk.com/ideal/messages/mer-acq/3.3.1" version="3.3.1">';
          xmlString &='<createDateTimestamp>#getFormattedTimestamp()#</createDateTimestamp>';
          xmlString &='<Issuer>';
          xmlString &='<issuerID>#getIssuerID()#</issuerID>';
          xmlString &='</Issuer>';
          xmlString &='<Merchant>';
          xmlString &='<merchantID>#getMerchantID()#</merchantID>';
          xmlString &='<subID>#getSubID()#</subID>';
          xmlString &='<merchantReturnURL>#xmlFormat( getMerchantReturnURL())#</merchantReturnURL>';
          xmlString &='</Merchant>';
          xmlString &='<Transaction>';
          xmlString &='<purchaseID>#getPurchaseID()#</purchaseID>';
          xmlString &='<amount>#getAmount()#</amount>';
          xmlString &='<currency>#getCurrency()#</currency>';

          if( len( getExpirationPeriod()) )
          {
            xmlString &='<expirationPeriod>#getExpirationPeriod()#</expirationPeriod>';
          }

          xmlString &='<language>#getLanguage()#</language>';
          xmlString &='<description>#xmlFormat( getDescription())#</description>';

          if( len( getEntranceCode()) )
          {
            xmlString &='<entranceCode>#xmlFormat( getEntranceCode())#</entranceCode>';
          }

          xmlString &='</Transaction>';
          xmlString &='</AcquirerTrxReq>';
        break;

        case "Status":
          xmlString &='<AcquirerStatusReq xmlns="http://www.idealdesk.com/ideal/messages/mer-acq/3.3.1" version="3.3.1">';
          xmlString &='<createDateTimestamp>#getFormattedTimestamp()#</createDateTimestamp>';
          xmlString &='<Merchant>';
          xmlString &='<merchantID>#getMerchantID()#</merchantID>';
          xmlString &='<subID>#getSubID()#</subID>';
          xmlString &='</Merchant>';
          xmlString &='<Transaction>';
          xmlString &='<transactionID>#getTransactionID()#</transactionID>';
          xmlString &='</Transaction>';
          xmlString &='</AcquirerStatusReq>';
        break;
      }

      var singedXML=signXML( xmlString );
      var xmlRequest=xmlParse( singedXML );
      var httpService=new http();

      httpService.setURL( getIdealURL());
      httpService.setMethod( "post" );
      httpService.setCharset( "utf-8" );
      httpService.addParam( type="header", name="content-type", value='text/xml; charset="utf-8"' );
      httpService.addParam( type="header", name="content-length", value=len( xmlRequest ));
      httpService.addParam( type="XML", value=xmlRequest );

      var httpRequest=httpService.send().getPrefix();

      if( not isXML( httpRequest.fileContent ))
      {
        throw(  message="#httpRequest.fileContent#",
                detail="#httpRequest.ErrorDetail#" );
      }

      var result=xmlParse( httpRequest.fileContent );

      /* Error logging */
      if( structKeyExists( result, "AcquirerErrorRes" ))
      {
        throw(  message="#result.AcquirerErrorRes.Error.errorMessage.xmlText#",
                detail="#result.AcquirerErrorRes.Error.errorDetail.xmlText#",
                errorCode="#result.AcquirerErrorRes.Error.errorCode.xmlText#",
                extendedInfo='<table><tr><td valign="top"><pre>#htmlEditFormat( indentXml( singedXML ))#</pre></td><td valign="top"><pre>#htmlEditFormat( indentXml( httpRequest.fileContent ))#</pre></td></tr></table>' );
      }

      return result;
    }
    catch( Any cfcatch )
    {
      return handleError( cfcatch );
    }
  }

  /* ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~ */
  /**
   * @return  String  Returns the timestamp property properly formatted (YYYY-mm-ddTHH:mm:ssZ)
   */
  private String function getFormattedTimestamp()
  {
    try
    {
      var timestamp=dateConvert( "local2utc", getTimestamp());
      return dateFormat( timestamp, "yyyy-mm-dd" ) & "T" & timeFormat( timestamp, "HH:mm:ss.l" ) & "Z";
    }
    catch( Any cfcatch )
    {
      return handleError( cfcatch );
    }
  }

  /* ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~ */
  /**
   * @return  String  Returns a SHA-1 fingerprint of the supplied certificate.
   */
  private String function createSHA1Fingerprint( required Any cert )
  {
    try
    {
      var sha1Md=createObject( "java", "java.security.MessageDigest" ).getInstance( "SHA-1" );
      sha1Md.update( cert.getEncoded());

      return uCase( binaryEncode( sha1Md.digest(), 'hex' ));
    }
    catch( Any cfcatch )
    {
      return handleError( cfcatch );
    }
  }

  /* ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~ */
  /**
   * indentXml pretty-prints XML and XML-like markup without requiring valid XML.
   * @param   xml     XML     String to format. (Required)
   * @param   indent  String  The String to use for indenting (default is two spaces).
   * @return  Returns a String.
   * @author  Barney Boisvert
   * @version 2, July 30, 2010
   * @version 3, April 28, 2015 Mingo Hagen
   */
  private String function indentXml( required String xml, String indent="  " )
  {
    try
    {
      var lines=[];
      var depth=0;
      var line="";
      var isCDATAStart=false;
      var isCDATAEnd=false;
      var isEndTag=false;
      var isSelfClose=false;

      xml=trim( REReplace( xml, "(^|>)\s*(<|$)", "\1#chr(10)#\2", "all" ));
      lines=listToArray( xml, chr( 10 ));

      for( var i=1; i lte arrayLen( lines ); i++ )
      {
        line=trim( lines[i]);
        isCDATAStart=left( line, 9 ) EQ "<![CDATA[";
        isCDATAEnd=right( line, 3 ) EQ "]]>";

        if( NOT isCDATAStart AND NOT isCDATAEnd AND left( line, 1 ) EQ "<" AND right( line, 1 ) EQ ">" )
        {
          isEndTag=left( line, 2 ) EQ "</";
          isSelfClose=right( line, 2 ) EQ "/>" OR REFindNoCase( "<([a-z0-9_-]*).*</\1>", line );

          if( isEndTag )
          {
            /* use max for safety against multi-line open tags */
            depth=max( 0, depth-1 );
          }

          lines[i]=repeatString( indent, depth ) & line;

          if( NOT isEndTag AND NOT isSelfClose )
          {
            depth=depth + 1;
          }
        }
        else if( isCDATAStart )
        {
          /*
            we don't indent CDATA ends, because that would change the
            content of the CDATA, which isn't desirable
          */
          lines[i]=repeatString( indent, depth ) & line;
        }
      }

      return arrayToList( lines, chr( 10 ));
    }
    catch( Any cfcatch )
    {
      return handleError( cfcatch );
    }
  }
}