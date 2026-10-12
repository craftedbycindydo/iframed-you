package com.wesbos.homehq;

import java.io.ByteArrayInputStream;
import java.io.ByteArrayOutputStream;
import java.nio.charset.StandardCharsets;
import java.security.GeneralSecurityException;
import java.security.KeyFactory;
import java.security.KeyPair;
import java.security.KeyPairGenerator;
import java.security.KeyStore;
import java.security.PrivateKey;
import java.security.SecureRandom;
import java.security.Signature;
import java.security.cert.Certificate;
import java.security.cert.CertificateFactory;
import java.security.cert.X509Certificate;
import java.security.spec.ECGenParameterSpec;
import java.security.spec.PKCS8EncodedKeySpec;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import javax.net.ssl.KeyManagerFactory;
import javax.net.ssl.SSLContext;

final class Identity {
  static final String KEY = "identity";
  private static final String[] FIRST_VERSION_KEYS = {"devices", "frameId"};
  private static final byte[] ECDSA_WITH_SHA256 = {0x06, 0x08, 0x2A, (byte) 0x86, 0x48, (byte) 0xCE, 0x3D, 0x04, 0x03, 0x02};
  private static final byte[] COMMON_NAME = {0x06, 0x03, 0x55, 0x04, 0x03};
  private static final char[] IN_MEMORY = "skylit".toCharArray();

  final byte[] fpRaw;
  final String fp;
  final String frameId;
  private final KeyValue storage;
  private final PrivateKey key;
  private final X509Certificate certificate;
  private final String keyHex;
  private final String certificateHex;
  private final List<Object> devices;

  private Identity(KeyValue storage, byte[] pkcs8, byte[] der, List<Object> devices) throws GeneralSecurityException {
    this.storage = storage;
    this.devices = devices;
    key = KeyFactory.getInstance("EC").generatePrivate(new PKCS8EncodedKeySpec(pkcs8));
    certificate = (X509Certificate) CertificateFactory.getInstance("X.509").generateCertificate(new ByteArrayInputStream(der));
    byte[] probe = {1};
    Signature verifier = Signature.getInstance("SHA256withECDSA");
    verifier.initVerify(certificate.getPublicKey());
    verifier.update(probe);
    if (!verifier.verify(sign(key, probe))) throw new GeneralSecurityException("The key does not belong to the certificate");
    keyHex = Digests.hex(pkcs8);
    certificateHex = Digests.hex(der);
    fpRaw = Digests.digest(certificate.getEncoded());
    fp = Digests.hex(fpRaw);
    frameId = fp.substring(0, 32);
  }

  static Identity open(KeyValue storage) {
    for (String old : FIRST_VERSION_KEYS) if (storage.get(old) != null) storage.put(old, null);
    try {
      Map<String, Object> saved = Json.map(Json.parse(storage.get(KEY)));
      byte[] pkcs8 = Digests.bytes(saved.get("key"));
      byte[] der = Digests.bytes(saved.get("certificate"));
      if (pkcs8 == null || der == null) throw new GeneralSecurityException("Unreadable identity");
      return new Identity(storage, pkcs8, der, paired(saved.get("devices")));
    } catch (Json.Malformed | GeneralSecurityException | RuntimeException absentOrUnreadable) {
      return create(storage);
    }
  }

  private static List<Object> paired(Object saved) {
    List<Object> rows = Json.list(saved);
    if (rows == null) return new ArrayList<>();
    for (Object row : rows) {
      Map<String, Object> device = Json.map(row);
      byte[] hash = device == null ? null : Digests.bytes(device.get("hash"));
      if (hash == null || hash.length != 32 || !(device.get("id") instanceof String)) return new ArrayList<>();
    }
    return rows;
  }

  private static Identity create(KeyValue storage) {
    try {
      SecureRandom random = new SecureRandom();
      KeyPairGenerator generator = KeyPairGenerator.getInstance("EC");
      generator.initialize(new ECGenParameterSpec("secp256r1"), random);
      KeyPair pair = generator.generateKeyPair();
      Identity created = new Identity(storage, pair.getPrivate().getEncoded(), certificate(pair, random), new ArrayList<>());
      created.save();
      return created;
    } catch (GeneralSecurityException unavailable) {
      throw new IllegalStateException(unavailable);
    }
  }

  static byte[] certificate(KeyPair pair, SecureRandom random) throws GeneralSecurityException {
    byte[] algorithm = der(0x30, ECDSA_WITH_SHA256);
    byte[] name = der(0x30, der(0x31, der(0x30, COMMON_NAME, der(0x0C, "Skylit".getBytes(StandardCharsets.UTF_8)))));
    byte[] serial = new byte[8];
    random.nextBytes(serial);
    serial[0] = (byte) (serial[0] & 0x7F | 0x40);
    byte[] validity = der(0x30, der(0x17, "200101000000Z".getBytes(StandardCharsets.US_ASCII)), der(0x17, "491231235959Z".getBytes(StandardCharsets.US_ASCII)));
    byte[] body = der(0x30, der(0xA0, der(0x02, new byte[] {2})), der(0x02, serial), algorithm, name, validity, name, pair.getPublic().getEncoded());
    return der(0x30, body, algorithm, der(0x03, new byte[] {0}, sign(pair.getPrivate(), body)));
  }

  private static byte[] sign(PrivateKey key, byte[] message) throws GeneralSecurityException {
    Signature signer = Signature.getInstance("SHA256withECDSA");
    signer.initSign(key);
    signer.update(message);
    return signer.sign();
  }

  private static byte[] der(int tag, byte[]... parts) {
    ByteArrayOutputStream content = new ByteArrayOutputStream();
    for (byte[] part : parts) content.write(part, 0, part.length);
    int length = content.size();
    if (length > 0xFFFF) throw new IllegalArgumentException("DER value too long");
    ByteArrayOutputStream out = new ByteArrayOutputStream();
    out.write(tag);
    if (length >= 0x100) {
      out.write(0x82);
      out.write(length >> 8);
    } else if (length >= 0x80) {
      out.write(0x81);
    }
    out.write(length & 0xFF);
    out.write(content.toByteArray(), 0, length);
    return out.toByteArray();
  }

  List<Object> devices() {
    return devices;
  }

  void save() {
    storage.put(KEY, Json.write(Json.object("key", keyHex, "certificate", certificateHex, "devices", devices)));
  }

  SSLContext tls() throws GeneralSecurityException {
    try {
      KeyStore store = KeyStore.getInstance(KeyStore.getDefaultType());
      store.load(null, null);
      store.setKeyEntry("skylit", key, IN_MEMORY, new Certificate[] {certificate});
      KeyManagerFactory keys = KeyManagerFactory.getInstance(KeyManagerFactory.getDefaultAlgorithm());
      keys.init(store, IN_MEMORY);
      SSLContext context = SSLContext.getInstance("TLSv1.2");
      context.init(keys.getKeyManagers(), null, null);
      return context;
    } catch (java.io.IOException impossible) {
      throw new GeneralSecurityException(impossible);
    }
  }
}
