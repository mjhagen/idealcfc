<cfset ideal = request.ideal />
<!---
  Set return URL to your test suite
  <cfset ideal.setMerchantReturnURL( "http://www.your-website-here.nl/index.cfm" ) />
--->

<!--- ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~ --->
<!--- ~~ STEP 1, DIRECTORY REQUEST:                                      ~~ --->
<!--- ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~ --->
<form method="post" action="index.cfm">
  <fieldset>
    <legend>Ideal.cfc Test Suite</legend>
    <div><cfoutput>#ideal.directoryRequest()#</cfoutput></div>
    <button type="submit" name="amount" value="1">Run test 1</button>
    <button type="submit" name="amount" value="2">Run test 2</button>
    <button type="submit" name="amount" value="3">Run test 3</button>
    <button type="submit" name="amount" value="4">Run test 4</button>
    <button type="submit" name="amount" value="5">Run test 5</button>
    <button type="submit" name="amount" value="7">Run test 7</button>
  </fieldset>
</form>

<!--- ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~ --->
<!--- ~~ STEP 2, TRANSACTION REQUEST:                                    ~~ --->
<!--- ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~ --->
<cfif structKeyExists( form, "amount" ) and
      structKeyExists( form, "issuerID" ) and
      len( trim( form.issuerID ))>
  <cfset ideal.setAmount( form.amount ) />
  <cfset ideal.setIssuerID( form.issuerID ) />
  <cfset ideal.setPurchaseID( randRange( 1000, 9999 )) />
  <cfset ideal.setDescription( "test" ) />
  <cfset ideal.transactionRequest() />
</cfif>

<!--- ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~ --->
<!--- ~~ STEP 3, STATUS REQUEST:                                         ~~ --->
<!--- ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~ --->
<cfif structKeyExists( url, "trxid" )>
  <cfset ideal.setTransactionID( url.trxid ) />
  <cfset local.status = ideal.statusRequest() />
  <hr />
  Status: <strong><cfoutput>#local.status.AcquirerStatusRes.Transaction.status.xmlText#</cfoutput></strong>
</cfif>