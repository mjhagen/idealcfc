<cfcomponent>
  <cfset this.name = "idealcfcexample" />

  <cffunction name="onApplicationStart">
    <cfif structKeyExists( application, "ideal" )>
      <cfset structDelete( application, "ideal" ) />
    </cfif>

    <cfset application.ideal = createObject( "lib/cfc/ideal" ).init( config = expandPath( "./config/test.cfm" )) />
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
    <cfoutput>
      <h3>#error.message#</h3>
      <h4>#error.detail#</h4>
    </cfoutput>
    <cfdump var="#error#" />
  </cffunction>
</cfcomponent>