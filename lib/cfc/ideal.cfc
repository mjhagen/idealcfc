<cfcomponent accessors="true" output="no" persistent="true">
  <cfprocessingdirective pageEncoding="utf-8" />
  <!--- 
    Generate ideal certificates like this:

    1.  keytool -genkey -keyalg RSA -sigAlg SHA256withRSA -keysize 2048 -validity 1825 -alias {KeyStoreAlias} -keystore {keystoreFileName.ks}
    2.  keytool -export -v -rfc -alias {KeyStoreAlias} -keystore {keystoreFileName.ks} -file {certificateFileName.cer}

    Upload ks file to your server ( not to a web accessible directory )
    Upload cer file to ideal dashboard

    Requirements:
     - javaloader which is used to compile idealcrypto.class
  --->

  <cfproperty name="timestamp" type="date" />
  <cfproperty name="issuerID" type="string" />
  <cfproperty name="merchantID" type="numeric" />
  <cfproperty name="subID" default="0" type="numeric" />
  <cfproperty name="purchaseID" type="numeric" hint="Order ID" />
  <cfproperty name="transactionID" default="" type="string" />
  <cfproperty name="amount" type="numeric" />
  <cfproperty name="currency" type="string" default="EUR" />
  <cfproperty name="language" type="string" default="nl" />
  <cfproperty name="description" type="string" hint="NO HTML ALLOWED!" />
  <cfproperty name="entranceCode" type="string" hint="Session ID" />
  <cfproperty name="expirationPeriod" type="string" hint="Optional, date period format: PnYnMnDTnHnMnS" />
  <cfproperty name="defaultCountry" default="Nederland" type="string" hint="Optional, set to country of website" />
  <cfproperty name="merchantReturnURL" type="string" />
  <cfproperty name="ksFile" type="string" />
  <cfproperty name="ksAlias" type="string" />
  <cfproperty name="ksPassword" type="string" />
  <cfproperty name="idealURL" required="yes" type="string" />

  <cfproperty name="debugIP" default="::1,fe80:0:0:0:0:0:0:1%1,127.0.0.1" required="no" type="string" />
  <cfproperty name="debugEmail" default="administrator@your-website-here.nl" required="no" type="string" />
  <cfproperty name="debugLog" default="ideal-cfc" required="no" type="string" />

  <cfset variables.cacheName = "cache" />

  <cfif not structKeyExists( server, 'idealcrypto' )>
    <cfset variables.pwd = getDirectoryFromPath( GetCurrentTemplatePath()) />
    <cfset variables.jl = new javaloader.JavaLoader( sourceDirectories = [ '#variables.pwd#\..\java' ]) />
    <cfset variables.idealcrypto = jl.create( 'idealcrypto' ) />
    <cfset server.idealcrypto = variables.idealcrypto />
  </cfif>

  <cfset variables.idealcrypto = server.idealcrypto />

  <!--- ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~ --->
  <cffunction name="init" output="no">
    <cfargument name="config" required="false" default="" />
    <cfargument name="initProperties" required="false" default="#{}#" />

    <cftry>
      <cfset var tempfunc = "" />
  
      <cfif not structKeyExists( application, variables.cacheName) or structKeyExists( url, "reload" )>
        <cfset application[variables.cacheName] = {} />
      </cfif>
  
      <!--- Optionally read config from a file, otherwise, just instantiate the cfc with your options as arguments. --->
      <cfif len( trim( arguments.config )) and fileExists( arguments.config )>
        <cfset application[variables.cacheName].properties = {} />
        <cffile action="read" file="#arguments.config#" variable="config" />
  
        <cfloop list="#config#" delimiters="#chr( 13 )##chr( 10 )#" index="valuePair">
          <cfif valuePair contains '<!---' or valuePair contains '--->'>
            <cfcontinue />
          </cfif>
  
          <cfset arguments.initProperties[listFirst( valuePair, ' #chr( 9 )#' )] = trim( listRest( valuePair, ' #chr( 9 )#' )) />
        </cfloop>
      </cfif>
  
      <cfloop collection="#arguments.initProperties#" item="key">
        <cfset tempfunc = evaluate( "set" & key ) />
        <cfset tempfunc( arguments.initProperties[key] ) />
      </cfloop>

      <cfif not fileExists( getKSFile())>
        <cfthrow message="Missing keystore file (#getKSFile()#)" />
      </cfif>

      <cfreturn this />

      <cfcatch>
        <cfreturn handleError( cfcatch ) />
      </cfcatch>
    </cftry>
  </cffunction>

  <cffunction name="handleError" output="no">
    <cfargument name="error" default="" />

    <!--- Display the error if the client IP is on the debugger list --->
    <cfif listFind( getDebugIP(), cgi.remote_addr )>
      <cfcontent reset=true /><cfsetting enableCFoutputOnly="false" />
      <cfdump var="#error#" />
      <cfabort />
    </cfif>

    <cflog file="#getDebugLog()#" type="Error" text="#error.message#, #error.detail#" />

    <cfmail from="#getDebugEmail()#" to="#getDebugEmail()#" subject="iDEAL Error: #error.message#" type="html">
      Error: <cfdump var="#error#" />
    </cfmail>

    <cfthrow errorCode="#error.errorCode#" message="#error.message#" detail="#error.detail#" extendedInfo="#error.extendedInfo#" />
  </cffunction>

  <!--- ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~ --->
  <cffunction name="directoryRequest" output="no">
    <cfargument name="class" default="" />

    <cftry>
      <cfset var cacheName = "DR_#dateFormat( now(), 'yyyymmdd' )#" />
      <cfset var issuerXML = "" />
      <cfset var issuerList = "" />
      <cfset var result = "" />
  
      <cfif not structKeyExists( application[variables.cacheName], cacheName )>
        <cfset var issuersXML = postRequest( "Directory" ) />
        <cfset var issuers = {} />
  
        <cfset var issuerLists = issuersXML.DirectoryRes.Directory />
        
        <cfif structKeyExists( issuersXML.DirectoryRes.Directory, "Country" )>
          <cfset issuerLists = issuersXML.DirectoryRes.Directory.Country />
        </cfif>
  
        <cfloop array="#issuerLists.xmlChildren#" index="issuerXML">
          <cfif issuerXML.xmlName eq "countryNames">
            <cfset issuerList = issuerXML.xmlText />
          </cfif>
  
          <cfif issuerXML.xmlName neq "Issuer">
            <cfcontinue />
          </cfif>
  
          <cfset var issuerID = issuerXML.xmlChildren[1].xmlText />
          <cfset var issuerName = issuerXML.xmlChildren[2].xmlText />
  
          <cfif not structKeyExists( issuers, issuerList )>
            <cfset issuers[issuerList] = [] />
          </cfif>
  
          <cfset arrayAppend( issuers[issuerList], {
            "id" = issuerID,
            "name" = issuerName
          } ) />
        </cfloop>
  
        <cfset application[variables.cacheName][cacheName] = issuers />
      </cfif>
      
      <cfset issuers = application[variables.cacheName][cacheName] />
      <cfset var issuerKeyList = listSort( structKeyList( issuers ), 'text' ) />
  
      <cfif len( getDefaultCountry())>
        <cfif listFindNoCase( issuerKeyList, getDefaultCountry())>
          <cfset issuerKeyList  = listDeleteAt( issuerKeyList, listFindNoCase( issuerKeyList, getDefaultCountry())) />
        </cfif>
        <cfset issuerKeyList  = listPrepend( issuerKeyList, getDefaultCountry()) />
      </cfif>
  
      <cfsavecontent variable="result"><cfoutput>
        <select name="issuerID" id="issuerID" style="margin-bottom:10px;" class="#arguments.class#">
          <option value="">Kies uw bank:</option>
  
          <cfloop list="#issuerKeyList#" index="key">
            <cfif not structKeyExists( issuers, key )>
              <cfcontinue />
            </cfif>
            <optgroup label="#key#">
              <cfloop array="#issuers[key]#" index="issuer">
                <option value="#issuer.id#">#issuer.name#</option>
              </cfloop>
            </optgroup>
          </cfloop>
        </select>
      </cfoutput></cfsavecontent>
  
      <cfreturn trim( result ) />

      <cfcatch>
        <cfreturn handleError( cfcatch ) />
      </cfcatch>
    </cftry>
  </cffunction>

  <!--- ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~ --->
  <cffunction name="transactionRequest" output="no">
    <cfargument name="redirect" default="true" />

    <cftry>
      <cfset var transactionXML = postRequest( "Transaction" ) />
  
      <cfif arguments.redirect>
        <cflocation url="#transactionXML.AcquirerTrxRes.Issuer.issuerAuthenticationURL.xmlText#" addToken="no" />
      </cfif>
  
      <cfset setTransactionID( transactionXML.AcquirerTrxRes.Transaction.transactionID.XmlText ) />
  
      <cfreturn transactionXML.AcquirerTrxRes.Issuer.issuerAuthenticationURL.xmlText />

      <cfcatch>
        <cfreturn handleError( cfcatch ) />
      </cfcatch>
    </cftry>
  </cffunction>

  <!--- ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~ --->
  <cffunction name="statusRequest" output="no">
    <cftry>
      <cfreturn postRequest( "Status" ) />

      <cfcatch>
        <cfreturn handleError( cfcatch ) />
      </cfcatch>
    </cftry>
  </cffunction>

  <!--- ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~ --->
  <cffunction name="postRequest" output="no">
    <cfargument name="requestType" />

    <cftry>
      <cfset var xmlString = '<?xml version="1.0" encoding="UTF-8"?>' />
  
      <cfset setTimestamp( now()) />
  
      <cfswitch expression="#arguments.requestType#">
        <!--- DirectoryRequest --->
        <cfcase value="Directory">
          <cfset xmlString &= '<DirectoryReq xmlns="http://www.idealdesk.com/ideal/messages/mer-acq/3.3.1" xmlns:ns2="http://www.w3.org/2000/09/xmldsig##" version="3.3.1">' />
          <cfset xmlString &= '<createDateTimestamp>#getFormattedTimestamp()#</createDateTimestamp>' />
          <cfset xmlString &= '<Merchant>' />
          <cfset xmlString &= '<merchantID>#getMerchantID()#</merchantID>' />
          <cfset xmlString &= '<subID>#getSubID()#</subID>' />
          <cfset xmlString &= '</Merchant>' />
          <cfset xmlString &= '</DirectoryReq>' />
        </cfcase>
  
        <!--- TransactionRequest --->
        <cfcase value="Transaction">
          <cfset setEntranceCode( getPurchaseID() ) />
          <cfset setDescription( right( getDescription(), 32 )) />
  
          <cfset xmlString &= '<AcquirerTrxReq xmlns="http://www.idealdesk.com/ideal/messages/mer-acq/3.3.1" version="3.3.1">' />
          <cfset xmlString &= '<createDateTimestamp>#getFormattedTimestamp()#</createDateTimestamp>' />
          <cfset xmlString &= '<Issuer>' />
          <cfset xmlString &= '<issuerID>#getIssuerID()#</issuerID>' />
          <cfset xmlString &= '</Issuer>' />
          <cfset xmlString &= '<Merchant>' />
          <cfset xmlString &= '<merchantID>#getMerchantID()#</merchantID>' />
          <cfset xmlString &= '<subID>#getSubID()#</subID>' />
          <cfset xmlString &= '<merchantReturnURL>#xmlFormat( getMerchantReturnURL())#</merchantReturnURL>' />
          <cfset xmlString &= '</Merchant>' />
          <cfset xmlString &= '<Transaction>' />
          <cfset xmlString &= '<purchaseID>#getPurchaseID()#</purchaseID>' />
          <cfset xmlString &= '<amount>#getAmount()#</amount>' />
          <cfset xmlString &= '<currency>#getCurrency()#</currency>' />
  
          <cfif len( getExpirationPeriod())>
            <cfset xmlString &= '<expirationPeriod>#getExpirationPeriod()#</expirationPeriod>' />
          </cfif>
  
          <cfset xmlString &= '<language>#getLanguage()#</language>' />
          <cfset xmlString &= '<description>#xmlFormat( getDescription())#</description>' />
  
          <cfif len( getEntranceCode())>
            <cfset xmlString &= '<entranceCode>#xmlFormat( getEntranceCode())#</entranceCode>' />
          </cfif>
  
          <cfset xmlString &= '</Transaction>' />
          <cfset xmlString &= '</AcquirerTrxReq>' />
        </cfcase>
  
        <!--- TODO: StatusRequest --->
        <cfcase value="Status">
          <cfset xmlString &= '<AcquirerStatusReq xmlns="http://www.idealdesk.com/ideal/messages/mer-acq/3.3.1" version="3.3.1">' />
          <cfset xmlString &= '<createDateTimestamp>#getFormattedTimestamp()#</createDateTimestamp>' />
          <cfset xmlString &= '<Merchant>' />
          <cfset xmlString &= '<merchantID>#getMerchantID()#</merchantID>' />
          <cfset xmlString &= '<subID>#getSubID()#</subID>' />
          <cfset xmlString &= '</Merchant>' />
          <cfset xmlString &= '<Transaction>' />
          <cfset xmlString &= '<transactionID>#getTransactionID()#</transactionID>' />
          <cfset xmlString &= '</Transaction>' />
          <cfset xmlString &= '</AcquirerStatusReq>' />
        </cfcase>
      </cfswitch>
  
      <cfset var xmlRequest = xmlParse( signXML( xmlString )) />
  
      <cfhttp url="#getIdealURL()#" method="post" charset="utf-8">
        <cfhttpparam type="header" name="content-type" value="text/xml; charset=""utf-8""" />
        <cfhttpparam type="header" name="content-length" value="#len( xmlRequest )#" />
        <cfhttpparam type="XML" value="#xmlRequest#" />
      </cfhttp>

      <cfif not isXML( cfhttp.fileContent )>
        <cfthrow message="#cfhttp.fileContent#" detail="#cfhttp.ErrorDetail#" />
      </cfif>

      <cfset var result = xmlParse( cfhttp.fileContent ) />

      <!--- Error logging --->
      <cfif structKeyExists( result, "AcquirerErrorRes" )>
        <cfthrow 
          errorCode="#result.AcquirerErrorRes.Error.errorCode.xmlText#" 
          message="#result.AcquirerErrorRes.Error.errorMessage.xmlText#" 
          detail="#result.AcquirerErrorRes.Error.errorDetail.xmlText#" 
          extendedInfo="#result.AcquirerErrorRes.Error.consumerMessage.xmlText#" />
      </cfif>

      <cfreturn result />

      <cfcatch>
        <cfreturn handleError( cfcatch ) />
      </cfcatch>
    </cftry>
  </cffunction>

  <!--- ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~ --->
  <cffunction name="signXML" returnType="any" output="no">
    <cfargument name="strToSign" />

    <cftry>
      <cfset var XMLSignatureFactory      = createObject( "java", "javax.xml.crypto.dsig.XMLSignatureFactory" ) />
      <cfset var DigestMethod             = createObject( "java", "javax.xml.crypto.dsig.DigestMethod" ) />
      <cfset var TransformService         = createObject( "java", "javax.xml.crypto.dsig.TransformService" ) />
      <cfset var DOMTransform             = createObject( "java", "org.jcp.xml.dsig.internal.dom.DOMTransform" ) />
      <cfset var DocumentBuilderFactory   = createObject( "java", "javax.xml.parsers.DocumentBuilderFactory" ) />
      <cfset var CanonicalizationMethod   = createObject( "java", "javax.xml.crypto.dsig.CanonicalizationMethod" ) />
      <cfset var C14NMethodParameterSpec  = createObject( "java", "javax.xml.crypto.dsig.spec.C14NMethodParameterSpec" ) />
      <cfset var InputSource              = createObject( "java", "org.xml.sax.InputSource" ) />
      <cfset var StringReader             = createObject( "java", "java.io.StringReader" ) />
      <cfset var PKCS8EncodedKeySpec      = createObject( "java", "java.security.spec.PKCS8EncodedKeySpec" ) />
      <cfset var KeyFactory               = createObject( "java", "java.security.KeyFactory" ).getInstance( "RSA" ) />
      <cfset var DOMSignContext           = createObject( "java", "javax.xml.crypto.dsig.dom.DOMSignContext" ) />
      <cfset var DOMSource                = createObject( "java", "javax.xml.transform.dom.DOMSource" ) />
      <cfset var TransformerFactory       = createObject( "java", "javax.xml.transform.TransformerFactory" ) />
      <cfset var Transformer              = createObject( "java", "javax.xml.transform.Transformer" ) />
      <cfset var StringWriter             = createObject( "java", "java.io.StringWriter" ).init() />
      <cfset var StreamResult             = createObject( "java", "javax.xml.transform.stream.StreamResult" ) />
      <cfset var DOMStructure             = createObject( "java", "javax.xml.crypto.dom.DOMStructure" ) />
  
      <cfset var KeyStore                 = createObject( "java", "java.security.KeyStore" ) />
      <cfset var PasswordProtection       = createObject( "java", "java.security.KeyStore$PasswordProtection" ).init( getKSPassword().toCharArray()) />
      <cfset var FileInputStream          = createObject( "java", "java.io.FileInputStream" ) />
  
      <!--- ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~ --->
      <!--- ~~ Signature creation: Step 1                                  ~~ --->
      <!--- ~~ Is now done in a java file compiled at runtime              ~~ --->
      <!--- ~~ idealcrypto.class                                           ~~ --->
      <!--- ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~ --->
      <cfset var facObj = variables.idealcrypto.init() />
      <cfset var fac = facObj.fac />
      <cfset var signedInfo = facObj.signedInfo />
  
      <!--- ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~ --->
      <!--- ~~ Signature creation: Step 2                                  ~~ --->
      <!--- ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~ --->
      
      <!--- Load the KeyStore and get the signing key and certificate. --->
      <cfset var ksfile = FileInputStream.init( getKSFile()) />
      <cfset var ks = KeyStore.getInstance( "JKS" ) />
      <cfset ks.load( ksfile, getKSPassword().toCharArray()) />
      <cfset var keyEntry = ks.getEntry( getKSAlias(), PasswordProtection ) />
      <cfset var cert = keyEntry.getCertificate() />
      <cfset ksfile.close() />
  
      <!--- Create the KeyInfo containing the X509Data. --->
      <cfset var kif = fac.getKeyInfoFactory() />
      <cfset var keyInfo = kif.newKeyInfo([kif.newKeyName( createSHA1Fingerprint( cert ))]) />
  
      <!--- ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~ --->
      <!--- ~~ Signature creation: Step 3                                  ~~ --->
      <!--- ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~ --->
  
      <!--- Instantiate the document to be signed. --->
      <cfset var dbf_i = DocumentBuilderFactory.newInstance() />
      <cfset dbf_i.setNamespaceAware( true ) />
      <cfset var doc = dbf_i.newDocumentBuilder().parse( InputSource.init( StringReader.init( arguments.strToSign ))) />
  
      <!--- Create a DOMSignContext and specify the RSA PrivateKey and location of
            the resulting XMLSignature's parent element. --->
      <cfset var dsc = DOMSignContext.init( keyEntry.getPrivateKey(), doc.getDocumentElement()) />
  
      <!--- Create the XMLSignature, but don't sign it yet. --->
      <cfset var signature = fac.newXMLSignature( signedInfo, keyInfo ) />
  
      <!--- Marshal, generate, and sign the enveloped signature. --->
      <cfset signature.sign( dsc ) />
  
      <!--- ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~ --->
      <!--- ~~ Signature creation: Step 4                                  ~~ --->
      <!--- ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~ --->
      <!--- Output the resulting document. --->
  
      <cfset var xmlResult = StreamResult.init( StringWriter ) />
      <cfset var ds = DOMSource.init( doc ) />
      <cfset var tf = TransformerFactory.newInstance() />
      <cfset var trans = tf.newTransformer() />
      <cfset trans.transform( ds, xmlResult ) />
  
      <cfreturn StringWriter.toString() />

      <cfcatch>
        <cfreturn handleError( cfcatch ) />
      </cfcatch>
    </cftry>
  </cffunction>

  <!--- ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~ --->
  <cffunction name="getFormattedTimestamp" returnType="string" output="no">
    <cftry>
      <cfset var timestamp = dateConvert( "local2utc", getTimestamp()) />
      <cfreturn dateFormat( timestamp, "yyyy-mm-dd" ) & "T" & timeFormat( timestamp, "HH:mm:ss.l" ) & "Z" />

      <cfcatch>
        <cfreturn handleError( cfcatch ) />
      </cfcatch>
    </cftry>
  </cffunction>

  <!--- ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~ --->
  <cffunction name="createSHA1Fingerprint" returntype="string" access="public" output="no">
    <cfargument name="cert" type="any" required="true" />

    <cftry>
      <cfset var sha1Md = createObject( "java", "java.security.MessageDigest" ).getInstance( "SHA-1" ) />
      <cfset sha1Md.update( cert.getEncoded()) />
  
      <cfreturn uCase( binaryEncode( sha1Md.digest(), 'hex' )) />

      <cfcatch>
        <cfreturn handleError( cfcatch ) />
      </cfcatch>
    </cftry>
  </cffunction>

  <!---
   indentXml pretty-prints XML and XML-like markup without requiring valid XML.
   
   @param xml 	 XML string to format. (Required)
   @param indent 	 String used for creating the indention. Defaults to a space. (Optional)
   @return Returns a string. 
   @author Barney Boisvert (&#98;&#98;&#111;&#105;&#115;&#118;&#101;&#114;&#116;&#64;&#103;&#109;&#97;&#105;&#108;&#46;&#99;&#111;&#109;) 
   @version 2, July 30, 2010 
  --->
  <cffunction name="indentXml" output="false" returntype="string">
    <cfargument name="xml" type="string" required="true" />
    <cfargument name="indent" type="string" default="  " hint="The string to use for indenting (default is two spaces)." />

    <cftry>
      <cfset var lines = "" />
      <cfset var depth = "" />
      <cfset var line = "" />
      <cfset var isCDATAStart = "" />
      <cfset var isCDATAEnd = "" />
      <cfset var isEndTag = "" />
      <cfset var isSelfClose = "" />
      <cfset xml = trim(REReplace(xml, "(^|>)\s*(<|$)", "\1#chr(10)#\2", "all")) />
      <cfset lines = listToArray(xml, chr(10)) />
      <cfset depth = 0 />
  
      <cfloop from="1" to="#arrayLen(lines)#" index="i">
        <cfset line = trim(lines[i]) />
        <cfset isCDATAStart = left(line, 9) EQ "<![CDATA[" />
        <cfset isCDATAEnd = right(line, 3) EQ "]]>" />
        <cfif NOT isCDATAStart AND NOT isCDATAEnd AND left(line, 1) EQ "<" AND right(line, 1) EQ ">">
          <cfset isEndTag = left(line, 2) EQ "</" />
          <cfset isSelfClose = right(line, 2) EQ "/>" OR REFindNoCase("<([a-z0-9_-]*).*</\1>", line) />
          <cfif isEndTag>
            <!--- use max for safety against multi-line open tags --->
            <cfset depth = max(0, depth - 1) />
          </cfif>
          <cfset lines[i] = repeatString(indent, depth) & line />
          <cfif NOT isEndTag AND NOT isSelfClose>
            <cfset depth = depth + 1 />
          </cfif>
        <cfelseif isCDATAStart>
          <!---
          we don't indent CDATA ends, because that would change the
          content of the CDATA, which isn't desirable
          --->
          <cfset lines[i] = repeatString(indent, depth) & line />
        </cfif>
      </cfloop>

      <cfreturn arrayToList(lines, chr(10)) />

      <cfcatch>
        <cfreturn handleError( cfcatch ) />
      </cfcatch>
    </cftry>
  </cffunction>
</cfcomponent>