import javax.xml.crypto.dsig.*;
import javax.xml.crypto.dsig.spec.TransformParameterSpec;
import javax.xml.crypto.dsig.spec.C14NMethodParameterSpec;
import java.util.Collections;
import java.util.List;

public class idealcrypto
{
  public static final String SIGNATURE_REFERENCE_DIGEST_METHOD = DigestMethod.SHA256;
  public static final String SIGNATURE_REFERENCE_TRANSFORM_MODE = Transform.ENVELOPED;
  public static final String SIGNATURE_REFERENCE_URI = "";
  public static final String SIGNATURE_SIGNED_INFO_ALGORITHM = "http://www.w3.org/2001/04/xmldsig-more#rsa-sha256";
  public static final String SIGNATURE_SIGNED_INFO_CANONICALIZATION_METHOD = CanonicalizationMethod.EXCLUSIVE;

  public XMLSignatureFactory fac;
  public SignedInfo signedInfo;

  public idealcrypto() throws Exception
  {
    try
    {
      fac = XMLSignatureFactory.getInstance("DOM");

      DigestMethod digestMethod = fac.newDigestMethod( SIGNATURE_REFERENCE_DIGEST_METHOD, null );
      List<Transform> transformList = Collections.singletonList(fac.newTransform(SIGNATURE_REFERENCE_TRANSFORM_MODE, (TransformParameterSpec) null));
      Reference ref = fac.newReference(SIGNATURE_REFERENCE_URI, digestMethod, transformList, null, null);
      SignatureMethod method = fac.newSignatureMethod( SIGNATURE_SIGNED_INFO_ALGORITHM, null );
      CanonicalizationMethod canonicalizationMethod = fac.newCanonicalizationMethod(SIGNATURE_SIGNED_INFO_CANONICALIZATION_METHOD, (C14NMethodParameterSpec) null);
      
      signedInfo = fac.newSignedInfo(canonicalizationMethod, method, Collections.singletonList(ref));
    }
    catch( Exception e )
    {}
  }
}