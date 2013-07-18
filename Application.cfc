<cfcomponent>
  <cfset this.name = "idealcfcexample" />

  <cffunction name="onApplicationStart">
    <cfset application.ideal = createObject( "lib/cfc/ideal" ).init(
      initProperties = {
        idealURL          = "URL TO IDEAL",
        ksFile            = "ABSOLUTE PATH TO KEYSTORE FILE.ks",
        ksAlias           = "KEYSTORE ALIAS",
        ksPassword        = "KEYSTORE PASSWORD",
        merchantID        = "00000000000",
        merchantReturnURL = "http://www.your-website-here.nl/index.cfm",
        cacheName         = this.name
      }
    ) />
  </cffunction>

  <cffunction name="onRequestStart">
    <cfif not structKeyExists( application, "cache" ) or
          (
            structKeyExists( url, "reload" ) and
            isBoolean( url.reload ) and
            url.reload
          )>
      <cfset onApplicationStart() />
    </cfif>

    <cfset request.ideal = application.ideal />
  </cffunction>
</cfcomponent>