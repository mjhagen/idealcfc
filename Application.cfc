<cfcomponent>
  <cfset this.name = "idealcfcexample" />

  <cffunction name="onApplicationStart">
    <cfset application.ideal = createObject( "lib/cfc/ideal" ).init( config = expandPath( "./config/production.cfm" )) />
  </cffunction>

  <cffunction name="onRequestStart">
    <cfif not structKeyExists( application, "ideal" ) or
          (
            structKeyExists( url, "reload" ) and
            isBoolean( url.reload ) and
            url.reload
          )>
      <cfset onApplicationStart() />
      <cfset application.ideal.reload = true />
    </cfif>

    <cfset request.ideal = application.ideal />
  </cffunction>

  <cffunction name="onError">
    <cfargument name="error" />

    <cfdump var="#application#" />
    <cfdump var="#error#" />
  </cffunction>
</cfcomponent>