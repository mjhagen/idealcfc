component {
  this.name = "idealcfcexample";

  public void function onApplicationStart() {
    if( structKeyExists( application, "ideal" )) {
      structDelete( application, "ideal" );
    }

    application.ideal = new ideal( expandPath( "./config/test.cfm" ));
  }

  public void function onRequestStart() {
    if( !structKeyExists( application, "ideal" ) || (
          structKeyExists( url, "reload" ) &&
          isBoolean( url.reload ) &&
          url.reload
        )) {
      onApplicationStart();
      application.ideal.reload = true;
    }

    request.ideal = application.ideal;
  }

  public void function onError( error ) {
    param error.message = "";
    param error.detail = "";

    writeOutput( '<h3>#error.message#</h3><h4>#error.detail#</h4>' );
    writeDump( error );
  }
}