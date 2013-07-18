<cfcomponent>
  <cffunction name="onRequestStart">
    <cfset attributes = {} />
    <cfset structAppend( attributes, url ) />
    <cfset structAppend( attributes, form ) />
    
    <cfscript>
      if(
            not structKeyExists( application, "cache" ) or
            (
              structKeyExists( attributes, "bRecycle" ) and
              isBoolean( attributes.bRecycle ) and
              attributes.bRecycle
            ) or
            (
              structKeyExists( attributes, "bRecycleIdeal" ) and
              isBoolean( attributes.bRecycleIdeal ) and
              attributes.bRecycleIdeal
            )
        )
      {
        application.cache = {};
      }
    
      if( not structKeyExists( application.cache, "ideal" ))
      {
        application.cache.ideal = createObject( "lib/cfc/ideal" ).init(
          initProperties  = {
            idealURL          = "URL TO IDEAL",
            ksFile            = "ABSOLUTE PATH TO KEYSTORE FILE.ks",
            ksAlias           = "KEYSTORE ALIAS",
            ksPassword        = "KEYSTORE PASSWORD",
            merchantID        = "00000000000",
            merchantReturnURL = "http://www.your-website-here.nl/index.cfm"
          }
        );
      }
    
      request.ideal = application.cache.ideal;
    </cfscript>
  </cffunction>
</cfcomponent>