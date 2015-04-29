component
{
  this.name = "idealcfcexample";

  public void function onApplicationStart()
  {
    if( structKeyExists( application, "ideal" ))
    {
      structDelete( application, "ideal" );
    }

    application.ideal = createObject( "lib/cfc/ideal" ).init( config = expandPath( "./config/test.cfm" ));
  }

  public void function onRequestStart()
  {
    if(
        not structKeyExists( application, "ideal" ) or
        (
          structKeyExists( url, "reload" ) and
          isBoolean( url.reload ) and
          url.reload
        )
      )
    {
      onApplicationStart();
      application.ideal.reload = true;
    }

    request.ideal = application.ideal;
  }

  public void function onError( error )
  {
    param error.message = "";
    param error.detail = "";

    writeOutput( '<h3>#error.message#</h3><h4>#error.detail#</h4>' );
    writeDump( error );
  }
}